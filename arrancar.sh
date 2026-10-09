#!/usr/bin/env bash
# Arranca el backend con las claves de ~/sila_llanolat/credenciales.txt.
#   ./arrancar.sh              -> modo jwt (login real). Es el modo normal, tambien en desarrollo.
#   ./arrancar.sh desarrollo   -> identidad por cabeceras X-Usuario/X-Rol: CUALQUIERA puede ser ADMIN.
#                                 Solo por excepcion; nunca en produccion.
set -euo pipefail
CRED="$HOME/sila_llanolat/credenciales.txt"
export LLANOLAT_APP_PWD="$(awk '/^LLANOLAT_APP/{print $2}' "$CRED")"
export SILA_JWT_SECRET="$(awk '/^SILA_JWT_SECRET/{print $2}' "$CRED")"
export SILA_MFA_KEY="$(awk '/^SILA_MFA_KEY/{print $2}' "$CRED")"
export SILA_MODO="${1:-jwt}"
# En http://localhost la cookie no puede ser Secure en todos los navegadores; en produccion (HTTPS) siempre true.
export SILA_COOKIE_SECURE="${SILA_COOKIE_SECURE:-false}"
# Origenes del dashboard permitidos (CORS y anti-CSRF), separados por coma. Con ngrok el navegador manda como
# Origin la URL de ngrok: pasala asi (sin barra final):  SILA_NGROK=https://tu-dominio.ngrok-free.dev ./arrancar.sh
export SILA_CORS_ORIGENES="http://localhost:4200${SILA_NGROK:+,$SILA_NGROK}"
cd "$(dirname "$0")"
exec ./mvnw spring-boot:run
