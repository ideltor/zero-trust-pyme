#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
sync-policies.py - Sincronización de roles entre Keycloak y OPA

Este script consulta la API REST de Keycloak para obtener la lista actual
de roles y genera una política Rego que OPA utiliza para las decisiones
de autorización. Está diseñado para ejecutarse periódicamente (ej. cada minuto)
mediante systemd timer o tarea programada.

Dependencias:
    - requests (pip install requests)

Autor: Trabajo Fin de Estudio - Grado en Ingeniería Informática
Versión: 1.0
Fecha: Marzo 2026
"""

import requests
import json
import os
import sys
import logging
from datetime import datetime
from pathlib import Path

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Constantes de configuración
KEYCLOAK_URL = "http://localhost:8080"
REALM = "pyme-realm"
ADMIN_USER = "admin"
ADMIN_PASS = "admin123"
OPA_URL = "http://localhost:8181/v1/policies/authz"

# Ruta de la política (compatible con Windows y Linux)
POLICY_PATH = Path("/opt/zt/opa/policy.rego")


def get_keycloak_token() -> str:
    """
    Obtiene un token de acceso desde Keycloak usando credenciales de administrador.

    Returns:
        str: Token JWT de acceso

    Raises:
        Exception: Si la autenticación falla o la API no responde
    """
    token_url = f"{KEYCLOAK_URL}/realms/master/protocol/openid-connect/token"
    payload = {
        "client_id": "admin-cli",
        "username": ADMIN_USER,
        "password": ADMIN_PASS,
        "grant_type": "password"
    }

    try:
        response = requests.post(token_url, data=payload, timeout=10)
        response.raise_for_status()
        token = response.json().get("access_token")
        if not token:
            raise ValueError("No se recibió token en la respuesta")
        logger.info("Token obtenido correctamente desde Keycloak")
        return token
    except requests.exceptions.RequestException as e:
        logger.error(f"Error al obtener token de Keycloak: {e}")
        raise


def get_roles_from_keycloak(token: str) -> list:
    """
    Obtiene la lista de roles desde el realm configurado.

    Args:
        token (str): Token JWT de autenticación

    Returns:
        list: Lista de roles (cada rol es un diccionario con 'name', 'id', etc.)

    Raises:
        Exception: Si la consulta falla
    """
    roles_url = f"{KEYCLOAK_URL}/admin/realms/{REALM}/roles"
    headers = {"Authorization": f"Bearer {token}"}

    try:
        response = requests.get(roles_url, headers=headers, timeout=10)
        response.raise_for_status()
        roles = response.json()
        logger.info(f"Obtenidos {len(roles)} roles desde Keycloak")
        return roles
    except requests.exceptions.RequestException as e:
        logger.error(f"Error al obtener roles de Keycloak: {e}")
        raise


def generate_rego_policy(roles: list) -> str:
    """
    Genera una política Rego a partir de la lista de roles.

    La política generada permite el acceso solo si el rol del usuario
    existe en Keycloak y el dispositivo está marcado como confiable.

    Args:
        roles (list): Lista de roles obtenida desde Keycloak

    Returns:
        str: Política en formato Rego
    """
    rego_lines = [
        "package authz",
        "",
        "default allow := false",
        ""
    ]

    for role in roles:
        role_name = role.get("name")
        if role_name:
            rego_lines.append(f"allow {{")
            rego_lines.append(f'    input.user.role == "{role_name}"')
            rego_lines.append(f"    input.device.trusted == true")
            rego_lines.append(f"}}")
            rego_lines.append("")

    rego_lines.append("# Denegación por defecto si no cumple mínimo privilegio")

    return "\n".join(rego_lines)


def save_policy_to_file(policy_content: str) -> None:
    """
    Guarda la política Rego en el archivo correspondiente.

    Args:
        policy_content (str): Contenido de la política en formato Rego
    """
    try:
        POLICY_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(POLICY_PATH, "w", encoding="utf-8") as f:
            f.write(policy_content)
        logger.info(f"Política guardada en: {POLICY_PATH}")
    except IOError as e:
        logger.error(f"Error al guardar la política: {e}")
        raise


def update_opa_policy(policy_content: str) -> bool:
    """
    Actualiza la política en OPA a través de su API REST.

    Args:
        policy_content (str): Contenido de la política en formato Rego

    Returns:
        bool: True si la actualización fue exitosa, False en caso contrario
    """
    try:
        response = requests.put(OPA_URL, data=policy_content.encode("utf-8"), timeout=5)
        response.raise_for_status()
        logger.info("Política actualizada correctamente en OPA")
        return True
    except requests.exceptions.RequestException as e:
        logger.warning(f"OPA no disponible o error en la actualización: {e}")
        return False


def main() -> None:
    """
    Función principal que orquesta el proceso de sincronización.
    """
    logger.info("Iniciando sincronización de políticas Keycloak -> OPA")

    try:
        token = get_keycloak_token()
        roles = get_roles_from_keycloak(token)
        policy_content = generate_rego_policy(roles)
        save_policy_to_file(policy_content)
        update_opa_policy(policy_content)

        logger.info(f"Sincronización completada: {len(roles)} roles procesados")

    except Exception as e:
        logger.error(f"Error durante la sincronización: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()