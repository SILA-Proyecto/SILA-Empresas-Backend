# Codigo comun de desplegar_base.sh, migrar.sh, crear_empresa.sh, modulos.sh y empresa.sh. Se usa con `source`; no se ejecuta.
# UN solo lugar para: nombres derivados del esquema (y la negativa a tocar Llanolat), ejecucion de SQL, sustitucion de
# marcadores y deteccion de errores de Oracle. Nada de esto se duplica en los scripts que lo usan.

AQUI_SQL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ_REPO="$(dirname "$AQUI_SQL")"
SERVICIO_DB="//localhost:1521/XEPDB1"

# --- Destino de la base: LOCAL (Oracle XE en Docker; por defecto) o NUBE (Oracle Autonomous Database, con wallet). ---
# La nube se activa SOLO con sql/nube.sh <script> ... (pone SILA_BD=nube); sin eso todo funciona exactamente como siempre.
# Lo que cambia entre uno y otro: el servicio, el usuario administrador (system | admin), los tablespaces y el cliente SQL*Plus.
# La configuracion de la nube vive fuera de git, en empresas/_nube/nube.env (KEY=VALUE: ALIAS=<servicio TNS>).
SILA_BD="${SILA_BD:-local}"
if [ "$SILA_BD" = "nube" ]; then
    NUBE_DIR="$RAIZ_REPO/empresas/_nube"
    [ -f "$NUBE_DIR/nube.env" ] || { echo "Falta $NUBE_DIR/nube.env (vea sql/LEEME.md, seccion Nube)." >&2; exit 1; }
    SERVICIO_DB="$(awk -F= '$1=="ALIAS"{print $2; exit}' "$NUBE_DIR/nube.env")"
    [ -n "$SERVICIO_DB" ] || { echo "nube.env no trae ALIAS." >&2; exit 1; }
    ADMIN_BD="admin"; TS_DATOS="data"; TS_TEMP="temp"
    IMAGEN_CLIENTE_SQL="${IMAGEN_CLIENTE_SQL:-container-registry.oracle.com/database/express:latest}"
elif [ "$SILA_BD" = "local" ]; then
    ADMIN_BD="system"; TS_DATOS="users"; TS_TEMP="temp"
else
    echo "SILA_BD invalido: $SILA_BD (use local o nube)." >&2; exit 1
fi
export SILA_BD ADMIN_BD TS_DATOS TS_TEMP
# Operaciones que solo existen en el Oracle local (Data Pump y archivos del contenedor): se niegan en la nube.
solo_local() { [ "$SILA_BD" = "local" ] || { echo "RECHAZADO: esta operacion solo existe con la base LOCAL (usa Data Pump y archivos del contenedor)." >&2; exit 1; }; }

# --- Nombres derivados del esquema y negativa a tocar Llanolat. Exporta ESQUEMA, USR_*, ROL_*, PERFIL y CTX. ---
nombres_derivados() {
    : "${ESQUEMA:?Falta ESQUEMA (p. ej. SILA_EMPRESAS)}"
    ESQUEMA="$(printf '%s' "$ESQUEMA" | tr '[:lower:]' '[:upper:]')"
    [[ "$ESQUEMA" =~ ^[A-Z][A-Z0-9_]{1,18}$ ]] || { echo "ESQUEMA invalido: letras, digitos y _, maximo 19 caracteres." >&2; return 1; }
    USR_APP="${ESQUEMA}_APP";           USR_REPORTES="${ESQUEMA}_REPORTES"
    ROL_APP="ROL_${ESQUEMA}_APP";       ROL_LECTURA="ROL_${ESQUEMA}_LECTURA";  ROL_AUDITORIA="ROL_${ESQUEMA}_AUDITORIA"
    PERFIL="PRF_${ESQUEMA}_SERVICIO";   CTX="CTX_${ESQUEMA}"
    # Nombres que usa Llanolat (esquema, cuentas, roles, perfil y contexto): ninguno puede ser destino ni derivado.
    local prohibidos=" LLANOLAT LLANOLAT_APP LLANOLAT_REPORTES ROL_SILA_APP ROL_SILA_LECTURA ROL_SILA_AUDITORIA PRF_SILA_SERVICIO CTX_SILA " n
    for n in "$ESQUEMA" "$USR_APP" "$USR_REPORTES" "$ROL_APP" "$ROL_LECTURA" "$ROL_AUDITORIA" "$PERFIL" "$CTX"; do
        case "$prohibidos" in *" $n "*) echo "RECHAZADO: $n es un nombre de Llanolat. Este script no toca Llanolat." >&2; return 1;; esac
    done
    [[ "$ESQUEMA" != *LLANOLAT* ]] || { echo "RECHAZADO: el esquema nombra a Llanolat." >&2; return 1; }
    export ESQUEMA USR_APP USR_REPORTES ROL_APP ROL_LECTURA ROL_AUDITORIA PERFIL CTX
}

# --- Ejecucion de SQL. La clave viaja por stdin, no por argv. ---
# sql_con "<conexion>" < script        (el contenedor es $CONTENEDOR, por defecto oracle-xe)
# En la nube el cliente es el SQL*Plus de la imagen de Oracle, en un contenedor desechable que monta el wallet (no enciende la base local).
sql_con() {
    if [ "$SILA_BD" = "nube" ]; then
        { printf 'WHENEVER OSERROR EXIT FAILURE\nCONNECT %s\n' "$1"; cat; } | docker run --rm -i -u 0 -e NLS_LANG=.AL32UTF8 -e TNS_ADMIN=/wallet \
            -v "$NUBE_DIR/wallet:/wallet:ro,z" -v "$NUBE_DIR/sqlnet_docker.ora:/wallet/sqlnet.ora:ro,z" \
            --entrypoint sqlplus "$IMAGEN_CLIENTE_SQL" -s -L /nolog
    else
        { printf 'WHENEVER OSERROR EXIT FAILURE\nCONNECT %s\n' "$1"; cat; } | docker exec -i -e NLS_LANG=.AL32UTF8 "${CONTENEDOR:-${C:-oracle-xe}}" sqlplus -s -L /nolog
    fi
}
conexiones() {   # define SYS_CONN y PROXY_CONN (necesita SYSTEM_PWD y ESQUEMA; SYSTEM_PWD es la clave de SYSTEM o, en la nube, la de ADMIN)
    : "${SYSTEM_PWD:?Falta SYSTEM_PWD (clave de SYSTEM)}"
    SYS_CONN="$ADMIN_BD/\"$SYSTEM_PWD\"@$SERVICIO_DB"
    PROXY_CONN="$ADMIN_BD[$ESQUEMA]/\"$SYSTEM_PWD\"@$SERVICIO_DB"
}
sql_sys()   { sql_con "$SYS_CONN"; }
# SQLBLANKLINES ON: una linea en blanco NO termina la sentencia (si no, un texto con saltos de linea podria colar comandos).
sql_dueno() { { printf 'SET DEFINE OFF\nSET SQLBLANKLINES ON\nWHENEVER SQLERROR EXIT FAILURE\n'; cat; } | sql_con "$PROXY_CONN"; }
# Un valor escalar: valor "<consulta sin ;>" con sql_sys o sql_dueno -> valor_sys / valor_dueno
valor_sys()   { printf 'SET HEADING OFF FEEDBACK OFF PAGESIZE 0\n%s;\n' "$1" | sql_sys   | tr -d '[:space:]'; }
valor_dueno() { printf 'SET HEADING OFF FEEDBACK OFF PAGESIZE 0\n%s;\n' "$1" | sql_dueno | tr -d '[:space:]'; }
# Escapa comillas simples para meter un texto en un literal SQL.
esc() { printf '%s' "${1//\'/\'\'}"; }
# Aborta (exit) si un texto que va a un literal SQL trae saltos de linea, tabuladores u otros caracteres de control: esc() solo
# duplica comillas, y en SQL*Plus una linea en blanco termina la sentencia. Llamar SIEMPRE en el shell principal, no dentro de $( ).
# sin_control "<nombre del dato>" "<valor>"
sin_control() {
    [[ "$2" != *[[:cntrl:]]* ]] || { echo "RECHAZADO: $1 no puede llevar saltos de linea, tabuladores ni otros caracteres de control." >&2; exit 1; }
}
clave() { openssl rand -base64 24 | tr -d '/+=' | cut -c1-20; }

# --- Sustitucion de marcadores __X__ en una copia (modo 600). Aborta si queda alguno sin valor. ---
# render <archivo.sql> <destino>
render() {
    PWD_APP="${PWD_APP:-}" PWD_REP="${PWD_REP:-}" perl -pe '
        BEGIN { for (qw(ESQUEMA USR_APP USR_REPORTES ROL_APP ROL_LECTURA ROL_AUDITORIA PERFIL CTX PWD_APP PWD_REP ADMIN_BD TS_DATOS TS_TEMP)) {
                    $m{$_} = $ENV{$_} if defined $ENV{$_} && $ENV{$_} ne "" } }
        s/__([A-Z_]+?)__/exists $m{$1} ? $m{$1} : die "marcador sin valor: __${1}__ ($ARGV, linea $.)\n"/ge;
    ' "$1" > "$2"
}

# Falla (devuelve 1) si el log trae errores de Oracle o de SQL*Plus.
sin_errores() { ! grep -nE "ORA-[0-9]+|PLS-[0-9]+|SP2-[0-9]+|Warning: .*(created|compiled) with (compilation )?errors" "$1"; }

# Recompila el esquema y comprueba 0 invalidos y 0 triggers deshabilitados. Imprime el resultado; devuelve 1 si no.
verificar_esquema() {
    local inv trg
    printf "BEGIN DBMS_UTILITY.COMPILE_SCHEMA(schema => '%s', compile_all => FALSE); END;\n/\n" "$ESQUEMA" | sql_dueno > /dev/null
    inv=$(valor_sys "SELECT COUNT(*) FROM dba_objects WHERE owner = '$ESQUEMA' AND status <> 'VALID'")
    trg=$(valor_sys "SELECT COUNT(*) FROM dba_triggers WHERE owner = '$ESQUEMA' AND status <> 'ENABLED'")
    echo "verificacion de $ESQUEMA: objetos invalidos = $inv, triggers deshabilitados = $trg"
    [ "$inv" = "0" ] && [ "$trg" = "0" ]
}

# --- Registro local de empresas (sin secretos): empresas/registro.tsv ---
REGISTRO="$RAIZ_REPO/empresas/registro.tsv"
REGISTRO_COLS="esquema	nombre	nombre_corto	puerto	origen	fecha_alta	version_esquema	prueba	estado"
registro_asegurar() {
    mkdir -p "$RAIZ_REPO/empresas"; chmod 700 "$RAIZ_REPO/empresas"
    [ -f "$REGISTRO" ] || { printf '%s\n' "$REGISTRO_COLS" > "$REGISTRO"; chmod 600 "$REGISTRO"; }
}
registro_campo() {   # registro_campo ESQUEMA N  -> valor de la columna N (1 = esquema)
    [ -f "$REGISTRO" ] || return 0
    awk -F'\t' -v e="$1" -v n="$2" '$1 == e {print $n}' "$REGISTRO"
}
registro_poner() {   # registro_poner ESQUEMA N VALOR  -> cambia la columna N de esa fila
    [ -f "$REGISTRO" ] || return 0
    local tmp; tmp="$(mktemp)"
    awk -F'\t' -v OFS='\t' -v e="$1" -v n="$2" -v v="$3" '$1 == e {$n = v} {print}' "$REGISTRO" > "$tmp" && cat "$tmp" > "$REGISTRO"; rm -f "$tmp"
}

# --- Objetos globales de una empresa (dueno, cuentas, roles, perfil, contexto) ---
# Los borra (DROP ... CASCADE): borrar_empresa_prueba.sh y baja_empresa.sh. Exige 0 sesiones abiertas. Imprime los restos (0 = limpio).
borrar_objetos_globales() {
    local sesiones resto
    sesiones=$(valor_sys "SELECT COUNT(*) FROM v\$session WHERE username IN ('$ESQUEMA','$USR_APP','$USR_REPORTES')")
    [ "$sesiones" = "0" ] || { echo "RECHAZADO: hay $sesiones sesion(es) abiertas de $ESQUEMA. Pare su backend y vuelva a intentar." >&2; return 1; }
    local salida
    salida=$(sql_sys <<FIN
WHENEVER SQLERROR EXIT FAILURE
DROP USER $USR_APP CASCADE;
DROP USER $USR_REPORTES CASCADE;
DROP USER $ESQUEMA CASCADE;
DROP ROLE $ROL_APP;
DROP ROLE $ROL_LECTURA;
DROP ROLE $ROL_AUDITORIA;
DROP PROFILE $PERFIL;
DROP CONTEXT $CTX;
FIN
) || { printf '%s\n' "$salida" >&2; echo "Fallo el borrado en la base (ver arriba)." >&2; return 1; }
    resto=$(valor_sys "SELECT (SELECT COUNT(*) FROM dba_users WHERE username IN ('$ESQUEMA','$USR_APP','$USR_REPORTES')) + (SELECT COUNT(*) FROM dba_roles WHERE role IN ('$ROL_APP','$ROL_LECTURA','$ROL_AUDITORIA')) + (SELECT COUNT(*) FROM dba_context WHERE namespace = '$CTX') + (SELECT COUNT(DISTINCT profile) FROM dba_profiles WHERE profile = '$PERFIL') FROM dual")
    echo "$resto"
}

# --- Respaldos con Data Pump (baja_empresa.sh, restaurar_empresa.sh) ---
# DATA_PUMP_DIR no sirve en este contenedor (ORA-48189 al resolver su ruta por PDB): se usa un DIRECTORY propio, SILA_RESPALDOS,
# en una carpeta del volumen de datos de Oracle. Los .dmp solo pasan por ahi: el script los saca a disco y los borra del contenedor.
DIR_RESPALDOS="SILA_RESPALDOS"
RUTA_RESPALDOS="/opt/oracle/oradata/sila_respaldos"
asegurar_dir_respaldos() {
    solo_local
    docker exec "${CONTENEDOR:-oracle-xe}" bash -c "mkdir -p '$RUTA_RESPALDOS' && chmod 700 '$RUTA_RESPALDOS'"
    printf "CREATE OR REPLACE DIRECTORY %s AS '%s';\n" "$DIR_RESPALDOS" "$RUTA_RESPALDOS" | sql_sys > /dev/null
}
# datapump expdp|impdp <parametros...>: la clave viaja en un parfile 600 dentro del contenedor, que se borra al terminar.
datapump() {
    solo_local
    local herramienta="$1"; shift
    local pf="/tmp/sila_dp_$$.par"
    printf 'userid=system/"%s"@%s\n' "$SYSTEM_PWD" "${SERVICIO_DB#//}" | docker exec -i "${CONTENEDOR:-oracle-xe}" bash -c "umask 077; cat > $pf"
    docker exec "${CONTENEDOR:-oracle-xe}" bash -c "$herramienta parfile=$pf $*; r=\$?; rm -f $pf; exit \$r"
}
