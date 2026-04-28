# Zero Trust Architecture para PYMEs

> **Trabajo Fin de Grado en Ingeniería Informática** — Universidad Internacional de La Rioja (UNIR)
>
> **Autor:** Ignacio Delgado Torrejón
>
> **Directora:** Alba Cristina Vicuña Pilataxi
>
> **Curso:** 2025/2026
>
> **Licencia:** MIT

Este repositorio contiene los scripts de automatización desarrollados en el Trabajo Fin de Grado *"Diseño de una arquitectura Zero Trust para entornos corporativos"*.

Los scripts permiten desplegar y operar una arquitectura de seguridad basada en el modelo Zero Trust, adaptada a pequeñas y medianas empresas con recursos limitados. La solución se articula en tres estratos funcionales:

1. **Gestión de identidades y autenticación** (Keycloak + OPA)
2. **Segmentación de red y microsegmentación lógica** (802.1X + VLAN dinámica)
3. **Automatización de políticas y scripts de soporte** (Ansible, Python, Bash)

## Scripts incluidos

| Script | Descripción |
|--------|-------------|
| `zt-deploy.yml` | Playbook Ansible para despliegue inicial de Keycloak, OPA y nginx |
| `sync-policies.py` | Script Python para sincronizar roles de Keycloak a OPA |
| `collect-telemetry.sh` | Script Bash para recolección de telemetría y envío a OPA |

## Requisitos del sistema

- **Sistema operativo**: Ubuntu 24.04 LTS o superior
- **Software requerido**:
  - Docker Engine 24.x o superior
  - Docker Compose Plugin 2.x
  - Ansible 2.16 o superior
  - Python 3.12 o superior
  - nginx 1.18 o superior
  - tcpdump 4.99 o superior
  - curl

## Instalación

### 1. Clonar el repositorio

```bash
git clone https://github.com/ideltor/zero-trust-pyme.git
cd zero-trust-pyme
```

### 2. Instalación de dependencias

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin ansible python3 python3-pip nginx tcpdump curl
```

### 3. Configurar inventario de Ansible

Crea un archivo `inventario.ini` con el siguiente contenido:

```ini
[zt_nodes]
localhost ansible_connection=local
```

## Uso de los scripts

### Script 1: zt-deploy.yml (despliegue inicial)

Este playbook de Ansible despliega Keycloak, PostgreSQL, OPA y configura nginx como Policy Enforcement Point (PEP).

```bash
ansible-playbook -i inventario.ini zt-deploy.yml
```

**Qué hace:**

- Instala los paquetes necesarios (Docker, nginx, etc.)
- Crea la estructura de directorios en `/opt/zt/`
- Despliega los contenedores con Docker Compose
- Configura nginx como proxy inverso
- Inicia todos los servicios

**Verificar que los servicios están funcionando:**

```bash
docker ps
# Debería ver los contenedores: postgres, keycloak, opa
curl http://localhost:8080  # Keycloak
curl http://localhost:8181   # OPA
```

### Script 2: sync-policies.py (sincronización de políticas)

Este script consulta Keycloak para obtener los roles definidos y genera una política Rego que OPA utiliza para las decisiones de autorización.

```bash
python3 sync-policies.py
```

**Qué hace:**

- Se autentica en Keycloak con credenciales de administrador
- Obtiene la lista de roles del realm `pyme-realm`
- Genera un archivo `policy.rego` en `/opt/zt/opa/`
- Actualiza OPA vía API REST

**Configurar ejecución periódica (cada minuto):**

Crear un archivo `/etc/systemd/system/sync-policies.service`:

```ini
[Unit]
Description=Sincronización Keycloak-OPA
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/zt/sync-policies.py
User=root
```

Crear un archivo `/etc/systemd/system/sync-policies.timer`:

```ini
[Unit]
Description=Timer para sync-policies

[Timer]
OnCalendar=*:0/1
Persistent=true

[Install]
WantedBy=timers.target
```

Habilitar el timer:

```bash
sudo systemctl enable sync-policies.timer
sudo systemctl start sync-policies.timer
```

### Script 3: collect-telemetry.sh (recolección de telemetría)

Este script captura tráfico de red mediante tcpdump, lo procesa y envía a OPA para decisiones de acceso contextual.

```bash
chmod +x collect-telemetry.sh
sudo ./collect-telemetry.sh
```

**Qué hace:**

- Captura 500 paquetes en la interfaz `eth0` (puertos 80 y 443)
- Procesa la captura con Python inline
- Genera un archivo JSON en `/var/log/zt-telemetry/`
- Envía el JSON a OPA vía API REST

**Configurar ejecución periódica (cada 5 minutos):**

Añadir al crontab:

```bash
sudo crontab -e
```

Añadir la línea:

```
*/5 * * * * /usr/local/bin/collect-telemetry.sh
```

Copiar el script a `/usr/local/bin/`:

```bash
sudo cp collect-telemetry.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/collect-telemetry.sh
```

## Configuración inicial de Keycloak

Después del despliegue, es necesario crear un realm y un cliente en Keycloak:

1. Acceder a `http://localhost:8080`
2. Iniciar sesión con `admin` / `admin123`
3. Crear un nuevo realm llamado `pyme-realm`
4. Crear un cliente llamado `zt-client`
5. Crear los roles necesarios (ej. `finanzas`, `recursos_humanos`)
6. Crear usuarios y asignarles roles

> ⚠️ **Aviso de seguridad.** Las credenciales `admin/admin123` son únicamente para el entorno de laboratorio descrito en el TFG. En cualquier despliegue real deben sustituirse por credenciales robustas y gestionarse mediante Ansible Vault o un secrets manager externo, tal como se indica en el apartado 4.5 de la memoria.

## Verificación del funcionamiento

### Comprobar que OPA responde correctamente

```bash
curl -X POST http://localhost:8181/v1/data/authz/allow \
  -H "Content-Type: application/json" \
  -d '{"input": {"user": {"role": "finanzas"}, "device": {"trusted": true}}}'
# Respuesta esperada: {"result": true}
```

### Comprobar que la telemetría se recibe en OPA

```bash
curl http://localhost:8181/v1/data/telemetry
# Respuesta esperada: JSON con los datos de telemetría
```

### Comprobar que nginx actúa como PEP

```bash
curl -H "X-User-Role: finanzas" http://app.zt-pyme.local/dashboard
```

## Solución de problemas comunes

Para dificultades habituales durante el despliegue (Docker, Keycloak, sincronización de políticas, telemetría, 802.1X), véase el documento [`docs/solucion-problemas.md`](docs/solucion-problemas.md).

## Licencia

Este repositorio se distribuye bajo licencia **MIT**. Véase el archivo [`LICENSE`](LICENSE) para los términos completos.

La licencia MIT permite el uso, copia, modificación y distribución del código sin restricciones, manteniendo únicamente el aviso de copyright y la exención de responsabilidad.

## Contexto académico

Este repositorio forma parte del Trabajo Fin de Grado titulado *Diseño de una arquitectura Zero Trust para entornos corporativos*, presentado en la Escuela Superior de Ingeniería y Tecnología de la Universidad Internacional de La Rioja (UNIR) en el curso 2025/2026. La fundamentación teórica, el diseño de la arquitectura, la metodología de validación y los resultados experimentales se documentan en la memoria del trabajo.

Para citar este repositorio:

> Delgado, I. (2026). *Zero Trust Architecture para PYMEs* [Software]. GitHub. https://github.com/ideltor/zero-trust-pyme
