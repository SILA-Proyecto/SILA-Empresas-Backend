#!/usr/bin/env bash
# Corre cualquier script de sql/ contra la base de la NUBE (Oracle Autonomous Database) en vez del Oracle local.
#   sql/nube.sh crear_empresa.sh --esquema SILA_NUBE ...      (mismos argumentos que el script)
#   sql/nube.sh migrar.sh                                      (con ESQUEMA=... en el entorno)
# Pone SILA_BD=nube y toma la clave de ADMIN de empresas/_nube/credenciales.txt (linea `OCI_ADMIN <clave>`); en la nube
# ADMIN hace el papel de SYSTEM (el proxy admin[ESQUEMA] reemplaza a system[ESQUEMA]). Para volver a local: no use este envoltorio.
# Configuracion (fuera de git): empresas/_nube/{nube.env, credenciales.txt, wallet/, sqlnet_docker.ora}. Ver sql/LEEME.md, seccion Nube.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(dirname "$AQUI")"
CRED_NUBE="${CREDENCIALES_NUBE:-$RAIZ/empresas/_nube/credenciales.txt}"
[ -f "$CRED_NUBE" ] || { echo "Falta $CRED_NUBE (linea: OCI_ADMIN <clave de ADMIN>)." >&2; exit 1; }
SYSTEM_PWD="$(awk '$1=="OCI_ADMIN"{print $2; exit}' "$CRED_NUBE")"
[ -n "$SYSTEM_PWD" ] || { echo "$CRED_NUBE no tiene OCI_ADMIN." >&2; exit 1; }
[ $# -ge 1 ] || { echo "Uso: $0 <script.sh> [argumentos...]" >&2; exit 1; }
SCRIPT="$1"; shift
[[ "$SCRIPT" =~ ^[a-z_]+\.sh$ && -f "$AQUI/$SCRIPT" ]] || { echo "Script desconocido: $SCRIPT (debe estar en sql/)." >&2; exit 1; }
export SILA_BD=nube SYSTEM_PWD
exec "$AQUI/$SCRIPT" "$@"
