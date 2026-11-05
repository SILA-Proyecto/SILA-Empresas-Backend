#!/usr/bin/env bash
# BAJA de una empresa (real o de prueba): respaldo completo y luego borrado de la base y del disco. Se revierte con
# sql/restaurar_empresa.sh <carpeta del respaldo>.
#
#   SYSTEM_PWD=<clave de SYSTEM> sql/baja_empresa.sh SILA_LACTEOS_EJEMPLO
#
# Requisitos (si falta uno, no se toca nada):
#   * se NIEGA con LLANOLAT (cualquier nombre que lo contenga);
#   * la empresa esta en empresas/registro.tsv y en la base, y esta SUSPENDIDA (sql/empresa.sh suspender): la baja nunca es el
#     primer paso;
#   * su backend no escucha en su puerto y no hay sesiones abiertas de sus cuentas;
#   * se ESCRIBE el nombre del esquema para confirmar (o CONFIRMO_BAJA=<ESQUEMA> si no hay terminal, como hace el panel).
# Pasos:
#   1. Respaldo de la base con Data Pump (expdp, esquema completo: tablas, datos, paquetes, vistas, permisos a sus roles).
#      Si expdp no termina «successfully completed» SIN errores, se detiene: no se borra nada.
#   2. Respaldo del disco: claves (credenciales.txt, aunque este fuera de la carpeta), instancia.env, archivos cifrados y logs.
#      SIN las claves los archivos cifrados no se pueden abrir: el respaldo las lleva, por eso es 600 y fuera de git.
#   3. Huellas SHA-256 de todo (SHA256SUMS) y un LEEME.txt con lo necesario para restaurar.
#   4. Borra de la base el esquema, las cuentas, los roles, el perfil y el contexto; borra empresas/<E> y la carpeta de archivos.
#   5. empresas/registro.tsv: la fila queda con estado «baja» (el puerto y el origen siguen reservados para poder restaurarla).
# El respaldo queda en ${SILA_BAJAS_DIR:-empresas/_bajas}/<ESQUEMA>_<fecha-hora>/ (700; archivos 600).
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/lib_sql.sh"
solo_local   # Data Pump y archivos del contenedor: solo con la base local

fallo() { echo "RECHAZADO: $*" >&2; exit 1; }

ESQUEMA="${1:-}"; [ -n "$ESQUEMA" ] || { sed -n '2,24p' "$0"; exit 1; }
nombres_derivados || exit 1
E="$ESQUEMA"
conexiones

# ---------- 0. Validaciones (no tocan nada) ----------
[ -n "$(registro_campo "$E" 1)" ] || fallo "$E no esta en empresas/registro.tsv."
[ "$(registro_campo "$E" 9)" != "baja" ] || fallo "$E ya esta dada de baja."
[ "$(valor_sys "SELECT COUNT(*) FROM dba_users WHERE username = '$E'")" = "1" ] || fallo "el esquema $E no existe en la base."
estado=$(valor_dueno "SELECT estado FROM empresa" 2>/dev/null || true)
[ -n "$estado" ] && [[ "$estado" =~ ^[A-Z]+$ ]] || fallo "no se pudo leer el estado de $E (falta aplicar 33_estado_empresa.sql con migrar.sh?)."
[ "$estado" = "SUSPENDIDA" ] || fallo "$E esta $estado. Primero suspendala: EMPRESA_MOTIVO='...' ESQUEMA=$E sql/empresa.sh suspender"
PUERTO="$(registro_campo "$E" 4)"
! ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$PUERTO\$" || fallo "algo escucha en el puerto $PUERTO (la instancia de $E sigue en marcha). Parela primero."
sesiones=$(valor_sys "SELECT COUNT(*) FROM v\$session WHERE username IN ('$E','$USR_APP','$USR_REPORTES')")
[ "$sesiones" = "0" ] || fallo "hay $sesiones sesion(es) abiertas de $E."

DIR="$RAIZ_REPO/empresas/$E"
[[ "$E" =~ ^[A-Z][A-Z0-9_]+$ ]] && [ -d "$DIR" ] || fallo "no existe la carpeta $DIR."
inst() { [ -f "$DIR/instancia.env" ] && sed -n "s/^$1=//p" "$DIR/instancia.env" | tail -1 | sed -e "s/^[\"']//" -e "s/[\"']\$//"; }
CRED="$(inst CREDENCIALES)"; CRED="${CRED:-$DIR/credenciales.txt}"
case "$CRED" in /*) ;; *) CRED="$RAIZ_REPO/$CRED" ;; esac
DOCS="$(inst SILA_DOCS_DIR)"; DOCS="${DOCS:-$DIR/docs}"
case "$DOCS" in /*) ;; *) DOCS="$RAIZ_REPO/$DOCS" ;; esac
[ -f "$CRED" ] || fallo "no encuentro las credenciales de $E ($CRED): sin ellas el respaldo no se puede restaurar."
DOCS_FUERA=0; case "$DOCS" in "$DIR"/*) ;; *) [ -d "$DOCS" ] && DOCS_FUERA=1 ;; esac

BAJAS="${SILA_BAJAS_DIR:-$RAIZ_REPO/empresas/_bajas}"
SELLO="$(date +%Y%m%d-%H%M%S)"
DEST="$BAJAS/${E}_$SELLO"
[ ! -e "$DEST" ] || fallo "ya existe $DEST."
DMP="baja_${E}_$SELLO"

echo "Se va a dar de BAJA la empresa $E ($(registro_campo "$E" 2)):"
echo "  1. respaldo de la base (Data Pump) y del disco en: $DEST"
echo "  2. se BORRAN de la base: esquema $E, cuentas $USR_APP y $USR_REPORTES, roles $ROL_APP/$ROL_LECTURA/$ROL_AUDITORIA, perfil $PERFIL, contexto $CTX"
echo "  3. se BORRAN del disco: $DIR$( [ "$DOCS_FUERA" = 1 ] && echo " y $DOCS")$( [ "$CRED" != "$DIR/credenciales.txt" ] && echo " (las credenciales de $CRED se respaldan pero NO se borran: estan fuera de la carpeta)")"
echo "  4. registro: estado «baja». Se revierte con sql/restaurar_empresa.sh $DEST"
if [ "${CONFIRMO_BAJA:-}" = "$E" ]; then :
elif [ -t 0 ]; then
    read -r -p "Escriba el nombre del esquema ($E) para confirmar: " resp
    [ "$resp" = "$E" ] || { echo "No coincide: cancelado, no se toco nada." >&2; exit 1; }
else
    echo "Sin terminal: confirme con CONFIRMO_BAJA=$E. Cancelado, no se toco nada." >&2; exit 1
fi

umask 077
mkdir -p "$BAJAS" "$DEST"; chmod 700 "$BAJAS" "$DEST"
limpiar_contenedor() { docker exec "${CONTENEDOR:-oracle-xe}" rm -f "$RUTA_RESPALDOS/$DMP.dmp" "$RUTA_RESPALDOS/$DMP.log" || true; }
trap limpiar_contenedor EXIT

# ---------- 1. Respaldo de la base ----------
echo ">> respaldo de la base (expdp)"
asegurar_dir_respaldos
datapump expdp "schemas=$E directory=$DIR_RESPALDOS dumpfile=$DMP.dmp logfile=$DMP.log" > "$DEST/expdp_consola.log" 2>&1 || true
docker cp "${CONTENEDOR:-oracle-xe}:$RUTA_RESPALDOS/$DMP.log" "$DEST/$DMP.log" 2>/dev/null || true
if ! grep -q "successfully completed at" "$DEST/$DMP.log" 2>/dev/null || grep -qE "completed with [0-9]+ error" "$DEST/$DMP.log"; then
    tail -15 "$DEST/expdp_consola.log" >&2
    echo "El respaldo de la base FALLO: no se borro nada. Detalle en $DEST/." >&2; exit 1
fi
docker cp "${CONTENEDOR:-oracle-xe}:$RUTA_RESPALDOS/$DMP.dmp" "$DEST/$DMP.dmp"
huella_dentro=$(docker exec "${CONTENEDOR:-oracle-xe}" sha256sum "$RUTA_RESPALDOS/$DMP.dmp" | cut -d' ' -f1)
[ "$(sha256sum "$DEST/$DMP.dmp" | cut -d' ' -f1)" = "$huella_dentro" ] || { echo "La copia del respaldo no coincide con el original: no se borro nada." >&2; exit 1; }
limpiar_contenedor
filas=$(grep -c '^\. \. exported' "$DEST/$DMP.log" || true)
echo "   $filas tablas exportadas, $(du -h "$DEST/$DMP.dmp" | cut -f1)"

# ---------- 2. Respaldo del disco ----------
echo ">> respaldo del disco"
tar -C "$RAIZ_REPO/empresas" -czf "$DEST/carpeta_empresa.tar.gz" "$E"
[ "$CRED" = "$DIR/credenciales.txt" ] || cp -p "$CRED" "$DEST/credenciales.txt"
[ "$DOCS_FUERA" = 0 ] || tar -C "$(dirname "$DOCS")" -czf "$DEST/docs.tar.gz" "$(basename "$DOCS")"
awk -F'\t' -v e="$E" 'NR == 1 || $1 == e' "$REGISTRO" > "$DEST/registro.tsv"
cat > "$DEST/LEEME.txt" <<FIN
Baja de la empresa $E ($(registro_campo "$E" 2)) el $(date '+%Y-%m-%d %H:%M:%S') por $(id -un).
Version del esquema: $(valor_dueno "SELECT MAX(numero) FROM version_esquema"). Motivo de la suspension: $(printf 'SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 400\nSELECT motivo_estado FROM empresa;\n' | sql_dueno | sed -e 's/^[[:space:]]*//' -e '/^$/d')

Contenido:
  $DMP.dmp / .log        respaldo Data Pump del esquema $E (Oracle 21c, expdp schemas=$E)
  carpeta_empresa.tar.gz  empresas/$E: credenciales.txt, instancia.env, docs (archivos cifrados), logs
$( [ "$CRED" != "$DIR/credenciales.txt" ] && echo "  credenciales.txt        las claves de $E (estaban fuera de su carpeta: $CRED)")
$( [ "$DOCS_FUERA" = 1 ] && echo "  docs.tar.gz             los archivos cifrados (estaban en $DOCS)")
  registro.tsv            su fila de empresas/registro.tsv
  SHA256SUMS              huellas de todo lo anterior

CONTIENE CLAVES: sin ellas los archivos cifrados no se pueden abrir. No lo comparta ni lo suba a git.
Restaurar:  SYSTEM_PWD=... sql/restaurar_empresa.sh $DEST
            (la empresa vuelve SUSPENDIDA; luego: ESQUEMA=$E sql/empresa.sh reactivar)
FIN
( cd "$DEST" && sha256sum -- * | grep -v ' SHA256SUMS$' > SHA256SUMS )
chmod 600 "$DEST"/*
echo "   respaldo completo en $DEST"

# ---------- 3. Borrado ----------
echo ">> borrado de la base"
resto=$(borrar_objetos_globales)
[ "$resto" = "0" ] || echo "AVISO: quedaron $resto objetos globales de $E en la base." >&2
echo ">> borrado del disco"
rm -rf -- "$DIR"
[ "$DOCS_FUERA" = 0 ] || rm -rf -- "$DOCS"
registro_poner "$E" 9 "baja"
echo "Empresa $E dada de BAJA. Respaldo: $DEST"
