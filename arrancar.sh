#!/usr/bin/env bash
# Arranca UNA instancia del backend de SILA Empresas: una por empresa, mismo codigo, cada una con su esquema, sus claves,
# su puerto y su directorio de archivos (empresas/<ESQUEMA>/instancia.env + credenciales.txt).
#   ./arrancar.sh                          -> SILA_EMPRESAS (como siempre), modo jwt
#   ./arrancar.sh SILA_LACTEOS_EJEMPLO     -> esa empresa
#   ./arrancar.sh [ESQUEMA] desarrollo     -> identidad por cabeceras X-Usuario/X-Rol: CUALQUIERA puede ser ADMIN.
#                                              Solo por excepcion; nunca en produccion.
#   ./arrancar.sh [ESQUEMA] jar            -> corre el jar empaquetado (./mvnw -DskipTests package) en vez de spring-boot:run;
#                                              asi se pueden tener VARIAS empresas a la vez sin que compartan target/.
# La configuracion de cada empresa vive fuera de git; este script solo la lee.
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")" && pwd)"

ESQ="SILA_EMPRESAS"; MODO="jwt"; JAR=0
for a in "$@"; do
    case "$a" in
        desarrollo|jwt) MODO="$a" ;;
        jar) JAR=1 ;;
        *) ESQ="$(printf '%s' "$a" | tr '[:lower:]' '[:upper:]')" ;;
    esac
done
[[ "$ESQ" =~ ^[A-Z][A-Z0-9_]{1,18}$ ]] || { echo "Empresa invalida: $ESQ" >&2; exit 1; }
# Esta rama jamas debe arrancar contra el esquema de Llanolat.
case "$ESQ" in *LLANOLAT*) echo "RECHAZADO: esta rama no arranca contra Llanolat." >&2; exit 1;; esac

INST="$RAIZ/empresas/$ESQ/instancia.env"
[ -f "$INST" ] || { echo "No existe $INST: la empresa $ESQ no esta creada (use sql/crear_empresa.sh)." >&2; exit 1; }
# KEY=VALUE por linea; se LEE, no se ejecuta.
inst() { awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$INST"; }
CRED="${CREDENCIALES:-$(inst CREDENCIALES)}"
[ -f "$CRED" ] || { echo "No existe el archivo de credenciales de $ESQ: $CRED" >&2; exit 1; }
clave() { awk -v k="$1" '$1==k{print $2}' "$CRED"; }

export SILA_DB_ESQUEMA="$(clave SILA_DB_ESQUEMA)"
export SILA_DB_USUARIO="$(clave SILA_DB_USUARIO)"
export SILA_DB_CLAVE="$(clave SILA_DB_CLAVE)"
export SILA_JWT_SECRET="$(clave SILA_JWT_SECRET)"
export SILA_MFA_KEY="$(clave SILA_MFA_KEY)"
export SILA_DOCS_KEY="$(clave SILA_DOCS_KEY)"
[ "$SILA_DB_ESQUEMA" = "$ESQ" ] || { echo "Las credenciales dicen $SILA_DB_ESQUEMA pero se pidio $ESQ: me detengo." >&2; exit 1; }
case "${SILA_DB_ESQUEMA^^}${SILA_DB_USUARIO^^}" in *LLANOLAT*) echo "RECHAZADO: las credenciales apuntan a Llanolat." >&2; exit 1;; esac
[ -n "$SILA_DB_ESQUEMA" ] && [ -n "$SILA_DB_USUARIO" ] && [ -n "$SILA_DB_CLAVE" ] || { echo "Faltan datos de la base en $CRED" >&2; exit 1; }

# Base en la NUBE (Oracle Autonomous Database con wallet): si instancia.env trae SILA_DB_URL se usa; si no, rige el Oracle local
# de application.yml. Para volver a local basta arrancar una empresa creada en local (o quitar esa linea de instancia.env).
URL_BD="${SILA_DB_URL:-$(inst SILA_DB_URL)}"
[ -z "$URL_BD" ] || export SILA_DB_URL="$URL_BD"
# La base gratuita de la nube admite pocas sesiones simultaneas (unas 20 en total): con la nube, pool chico por empresa.
# Se cambia con SILA_POOL_NUBE (maximo); sin SILA_DB_URL (base local) esto no hace nada.
if [ -n "${SILA_DB_URL:-}" ]; then
    export SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE="${SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE:-${SILA_POOL_NUBE:-3}}"
    export SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE="${SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE:-1}"
fi

# Puerto, origen del dashboard y directorio de archivos: propios de la empresa.
export SILA_PUERTO="${SILA_PUERTO:-$(inst SILA_PUERTO)}"
export SILA_DOCS_DIR="${SILA_DOCS_DIR:-$(inst SILA_DOCS_DIR)}"
[ -n "$SILA_PUERTO" ] && [ -n "$SILA_DOCS_DIR" ] || { echo "Faltan SILA_PUERTO o SILA_DOCS_DIR en $INST" >&2; exit 1; }
case "$SILA_PUERTO" in 8080|8081|4200) echo "RECHAZADO: el puerto $SILA_PUERTO es de Llanolat." >&2; exit 1;; esac
mkdir -p "$SILA_DOCS_DIR"; chmod 700 "$SILA_DOCS_DIR"
ORIGEN="${SILA_CORS_ORIGEN:-$(inst SILA_CORS_ORIGENES)}"
export SILA_CORS_ORIGENES="${ORIGEN:-http://127.0.0.1:4300}${SILA_NGROK:+,$SILA_NGROK}"

# Version vigente de los documentos legales de ESTA empresa (opcional en instancia.env; si no, rige application.yml).
for v in SILA_LEGAL_TERMINOS_VERSION SILA_LEGAL_TERMINOS_FECHA SILA_LEGAL_PRIVACIDAD_VERSION SILA_LEGAL_PRIVACIDAD_FECHA; do
    valor="${!v:-$(inst "$v")}"
    [ -z "$valor" ] || export "$v=$valor"
done

# Asistente de IA (n8n): opcional y propio de cada empresa. Sin SILA_ASISTENTE_URL el backend lo deja APAGADO y nunca llama a n8n.
#   instancia.env     SILA_ASISTENTE_URL=http://127.0.0.1:5678/webhook/<ruta>   (n8n, solo en esta maquina)
#                     SILA_ASISTENTE_BASE_URL=<API de esta empresa vista DESDE n8n>   (si falta rige application.yml)
#   credenciales.txt  SILA_ASISTENTE_SECRETO <valor>   (cabecera X-Sila-Secreto que el webhook debe comprobar)
# Una variable ya presente en el entorno gana sobre el archivo.
for v in SILA_ASISTENTE_URL SILA_ASISTENTE_BASE_URL; do
    valor="${!v:-$(inst "$v")}"
    [ -z "$valor" ] || export "$v=$valor"
done
valor="${SILA_ASISTENTE_SECRETO:-$(clave SILA_ASISTENTE_SECRETO)}"
[ -z "$valor" ] || export SILA_ASISTENTE_SECRETO="$valor"
# Por defecto del servidor (opcional): empresas/_asistente/asistente.env, KEY=VALUE con SILA_ASISTENTE_URL y SILA_ASISTENTE_SECRETO
# (se escribe con servidor/configurar_asistente_global.sh). Lo propio de la empresa SIEMPRE gana: solo se usa lo que a la empresa
# le falta, asi una empresa recien creada ya arranca con el asistente. Sin URL propia, SILA_ASISTENTE_BASE_URL se arma con el
# puerto de ESTA empresa (su API vista desde n8n, en la misma maquina). Para dejar una empresa SIN asistente aunque exista el
# global: SILA_ASISTENTE=off en su instancia.env. El archivo se LEE, no se ejecuta.
GLOBAL_ASISTENTE="$RAIZ/empresas/_asistente/asistente.env"
if [ "$(inst SILA_ASISTENTE)" = "off" ]; then
    unset SILA_ASISTENTE_URL SILA_ASISTENTE_BASE_URL SILA_ASISTENTE_SECRETO
elif [ -f "$GLOBAL_ASISTENTE" ]; then
    glob() { awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$GLOBAL_ASISTENTE"; }
    if [ -z "${SILA_ASISTENTE_URL:-}" ]; then
        valor="$(glob SILA_ASISTENTE_URL)"
        if [ -n "$valor" ]; then
            export SILA_ASISTENTE_URL="$valor"
            [ -n "${SILA_ASISTENTE_BASE_URL:-}" ] || export SILA_ASISTENTE_BASE_URL="http://127.0.0.1:${SILA_PUERTO}/api/v1"
        fi
    fi
    if [ -n "${SILA_ASISTENTE_URL:-}" ] && [ -z "${SILA_ASISTENTE_SECRETO:-}" ]; then
        valor="$(glob SILA_ASISTENTE_SECRETO)"
        [ -z "$valor" ] || export SILA_ASISTENTE_SECRETO="$valor"
    fi
fi
if [ -n "${SILA_ASISTENTE_URL:-}" ]; then
    echo "Asistente: n8n en ${SILA_ASISTENTE_URL} (secreto $([ -n "${SILA_ASISTENTE_SECRETO:-}" ] && echo definido || echo VACIO))" >&2
else
    echo "Asistente: APAGADO (sin SILA_ASISTENTE_URL)" >&2
fi

# Antivirus: se enciende solo si clamd responde en SILA_CLAMAV_HOST:SILA_CLAMAV_PUERTO (por defecto 127.0.0.1:3310; en
# desarrollo corre en el contenedor `sila-clamav`). Si no responde queda APAGADO (las subidas no se escanean) y se avisa; el
# perfil de produccion se niega a arrancar con el antivirus apagado. Se puede forzar con SILA_CLAMAV=true|false.
if [ -z "${SILA_CLAMAV:-}" ]; then
  if [ "$(printf 'PING\n' | timeout 3 nc "${SILA_CLAMAV_HOST:-127.0.0.1}" "${SILA_CLAMAV_PUERTO:-3310}" 2>/dev/null)" = "PONG" ]; then
    SILA_CLAMAV=true
  else
    SILA_CLAMAV=false
    echo "AVISO: clamd no responde; antivirus APAGADO (docker start sila-clamav)" >&2
  fi
fi
export SILA_CLAMAV
export SILA_MODO="$MODO"
# En http://127.0.0.1 la cookie no puede ser Secure en todos los navegadores; en produccion (HTTPS) siempre true.
export SILA_COOKIE_SECURE="${SILA_COOKIE_SECURE:-false}"

echo "Base de datos: $([ -n "${SILA_DB_URL:-}" ] && echo NUBE \(wallet\) || echo LOCAL \(Oracle en este equipo\))" >&2
echo "Empresa $ESQ en el puerto $SILA_PUERTO (dashboard permitido: $SILA_CORS_ORIGENES; archivos: $SILA_DOCS_DIR)" >&2
cd "$RAIZ"
if [ "$JAR" = "1" ]; then
    JARFILE="$(ls -t target/*.jar 2>/dev/null | grep -v '\.original$' | head -1)"
    [ -n "$JARFILE" ] || { echo "No hay jar en target/: corra ./mvnw -DskipTests package" >&2; exit 1; }
    # shellcheck disable=SC2086
    exec java ${JAVA_OPTS:-} -jar "$JARFILE"
fi
exec ./mvnw spring-boot:run
