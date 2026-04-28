#!/bin/bash
# -*- coding: utf-8 -*-

# =============================================================================
# collect-telemetry.sh - Recolección de telemetría ligera para Zero Trust
# =============================================================================
#
# Descripción:
#   Captura tráfico de red relevante mediante tcpdump, lo procesa con Python
#   para generar un JSON estructurado, y lo envía a OPA para su uso en
#   decisiones de autorización contextual.
#
# Dependencias:
#   - tcpdump
#   - curl
#   - python3 (con json y datetime)
#
# Instalación:
#   sudo apt install tcpdump curl python3
#
# Configuración en crontab (ejecutar cada 5 minutos):
#   */5 * * * * /usr/local/bin/collect-telemetry.sh
#
# Autor: Trabajo Fin de Estudio - Grado en Ingeniería Informática
# Versión: 1.0
# Fecha: Marzo 2026
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURACIÓN
# =============================================================================

INTERFACE="${ZT_INTERFACE:-eth0}"
CAPTURE_COUNT="${ZT_CAPTURE_COUNT:-500}"
LOG_DIR="${ZT_LOG_DIR:-/var/log/zt-telemetry}"
OPA_URL="${ZT_OPA_URL:-http://localhost:8181/v1/data/telemetry}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${LOG_DIR}/telemetry-${TIMESTAMP}.json"

# =============================================================================
# FUNCIONES
# =============================================================================

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

# =============================================================================
# VALIDACIÓN DE PRERREQUISITOS
# =============================================================================

# Verificar que tcpdump está instalado
if ! command -v tcpdump &> /dev/null; then
    log_error "tcpdump no está instalado. Ejecute: sudo apt install tcpdump"
    exit 1
fi

# Verificar que curl está instalado
if ! command -v curl &> /dev/null; then
    log_error "curl no está instalado. Ejecute: sudo apt install curl"
    exit 1
fi

# Verificar que python3 está instalado
if ! command -v python3 &> /dev/null; then
    log_error "python3 no está instalado. Ejecute: sudo apt install python3"
    exit 1
fi

# =============================================================================
# CREACIÓN DE DIRECTORIO DE LOGS
# =============================================================================

if [[ ! -d "${LOG_DIR}" ]]; then
    mkdir -p "${LOG_DIR}"
    log_info "Directorio creado: ${LOG_DIR}"
fi

# =============================================================================
# CAPTURA DE TRÁFICO CON TCPDUMP Y PROCESAMIENTO CON PYTHON
# =============================================================================

log_info "Iniciando captura de telemetría en interfaz ${INTERFACE}"

# Capturar tráfico con tcpdump y procesar con Python inline
tcpdump -i "${INTERFACE}" -c "${CAPTURE_COUNT}" -nn 'tcp port 443 or tcp port 80' -tt 2>/dev/null | \
    python3 -c '
import sys
import json
from datetime import datetime

def parse_tcpdump_line(line):
    """Parsea una línea de tcpdump y extrae información relevante."""
    parts = line.split()
    if len(parts) < 8:
        return None
    
    timestamp = parts[0]
    ip_proto = parts[1]
    src = parts[2]
    dst = parts[4]
    
    return {
        "timestamp": timestamp,
        "protocol": ip_proto,
        "source": src.rstrip(":"),
        "destination": dst,
        "raw": line.strip()
    }

def main():
    data = {
        "capture_timestamp": datetime.now().isoformat(),
        "flows": []
    }
    
    for line in sys.stdin:
        line = line.strip()
        if not line or "IP" not in line:
            continue
        
        flow = parse_tcpdump_line(line)
        if flow:
            data["flows"].append(flow)
    
    # Limitar a los primeros 100 flujos para no sobrecargar OPA
    if len(data["flows"]) > 100:
        data["flows"] = data["flows"][:100]
    
    data["total_flows"] = len(data["flows"])
    
    json.dump(data, sys.stdout, indent=2)

if __name__ == "__main__":
    main()
' > "${LOG_FILE}"

# =============================================================================
# VERIFICACIÓN DE CAPTURA
# =============================================================================

if [[ ! -s "${LOG_FILE}" ]]; then
    log_error "No se generó archivo de telemetría o está vacío"
    exit 1
fi

log_info "Telemetría guardada en: ${LOG_FILE}"

# =============================================================================
# ENVÍO A OPA
# =============================================================================

log_info "Enviando telemetría a OPA (${OPA_URL})"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    --data-binary "@${LOG_FILE}" \
    -H "Content-Type: application/json" \
    "${OPA_URL}" 2>/dev/null)

if [[ "${HTTP_CODE}" -eq 200 ]] || [[ "${HTTP_CODE}" -eq 204 ]]; then
    log_info "Telemetría enviada correctamente a OPA (HTTP ${HTTP_CODE})"
else
    log_error "Error al enviar telemetría a OPA. Código HTTP: ${HTTP_CODE}"
    exit 1
fi

# =============================================================================
# LIMPIEZA DE ARCHIVOS ANTIGUOS (conservar últimos 7 días)
# =============================================================================

find "${LOG_DIR}" -name "telemetry-*.json" -type f -mtime +7 -delete 2>/dev/null || true
log_info "Limpieza de archivos antiguos completada"

log_info "Telemetría finalizada correctamente"
exit 0