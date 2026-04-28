# Solución de problemas comunes

Este documento recoge las dificultades habituales encontradas durante el despliegue y operación de la arquitectura Zero Trust descrita en el TFE.

## Despliegue inicial

**El playbook de Ansible falla al instalar Docker.** Verifica que el usuario que ejecuta Ansible tiene permisos sudo sin contraseña, o pasa la opción `--ask-become-pass` al lanzar el playbook.

**Keycloak no arranca.** Comprueba que el contenedor tiene al menos 2 GB de memoria asignados y que el puerto 8080 no está ocupado por otro servicio. Para ver los logs del contenedor: `docker logs keycloak`.

**Los contenedores de Docker no se inician.** Asegúrate de que el servicio Docker está activo: `sudo systemctl status docker`. Si no lo está, arráncalo con `sudo systemctl start docker`.

## Sincronización de políticas

**`sync-policies.py` no detecta cambios en Keycloak.** Asegúrate de que las credenciales del cliente admin en Keycloak son correctas y de que el usuario tiene rol `realm-admin` asignado.

**OPA devuelve error 400 al recibir las políticas.** Valida la sintaxis Rego con `opa fmt policy.rego` antes de enviarla. Un error frecuente son las llaves mal cerradas en políticas con varios roles.

**El timer de systemd no ejecuta el script.** Comprueba el estado con `sudo systemctl status sync-policies.timer` y los logs con `sudo journalctl -u sync-policies.service`.

## Telemetría

**`collect-telemetry.sh` no captura tráfico.** El script requiere privilegios de superusuario para acceder a la interfaz de red. Ejecútalo con `sudo` o configura `setcap` sobre `tcpdump`.

**Los logs crecen demasiado.** Ajusta el muestreo modificando la variable de entorno `ZT_CAPTURE_COUNT` antes de ejecutar el script. Por defecto captura 500 paquetes cada 5 minutos.

**El script falla con "interfaz no encontrada".** Verifica el nombre de tu interfaz de red con `ip a`. La interfaz puede no llamarse `eth0` en sistemas modernos (suele ser `enp0s3`, `ens33` o similar). Sobrescribe la variable con `export ZT_INTERFACE=tu_interfaz` antes de ejecutar.

## Microsegmentación 802.1X

**El switch no asigna VLAN dinámica.** Verifica que el switch soporta IEEE 802.1X y que el atributo `Tunnel-Private-Group-ID` se está enviando correctamente desde FreeRADIUS al switch.

**FreeRADIUS no se comunica con Keycloak.** Revisa los logs de FreeRADIUS en `/var/log/freeradius/radius.log` y comprueba que la configuración del módulo de autenticación apunta al endpoint correcto de Keycloak.

## Comprobación general del entorno

**Los servicios parecen activos pero no responden.** Lanza la batería de comprobaciones del README en orden:

1. `docker ps` para confirmar que los contenedores están en ejecución.
2. `curl http://localhost:8080` para verificar Keycloak.
3. `curl http://localhost:8181` para verificar OPA.
4. `curl -X POST http://localhost:8181/v1/data/authz/allow ...` con el ejemplo del README para verificar que OPA evalúa políticas correctamente.

Si alguno de estos pasos falla, el resto no funcionará. Aborda los problemas en este orden.
