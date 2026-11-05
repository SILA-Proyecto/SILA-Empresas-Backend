#!/usr/bin/env bash
# Deshace una BAJA: vuelve a crear la empresa a partir del respaldo que dejo sql/baja_empresa.sh.
#
#   SYSTEM_PWD=<clave de SYSTEM> sql/restaurar_empresa.sh empresas/_bajas/SILA_LACTEOS_EJEMPLO_20261027-120000
#
# Requisitos (si falta uno, no se toca nada):
#   * las huellas del respaldo coinciden (SHA256SUMS);
#   * el esquema NO existe en la base (ni sus cuentas, roles, perfil o contexto) y empresas/<E> no existe;
#   * en empresas/registro.tsv la empresa esta en estado «baja» (o no esta: se agrega la fila del respaldo);
#   * su puerto esta libre;
#   * se ESCRIBE el nombre del esquema para confirmar (o CONFIRMO_RESTAURAR=<ESQUEMA> si no hay terminal).
# Pasos: restaura la carpeta empresas/<E> (claves, configuracion, archivos cifrados, logs); vuelve a crear los objetos globales
# (sql/inicial/01_bootstrap.sql) con las MISMAS claves de antes; importa el esquema con Data Pump (impdp); recompila y exige
# 0 invalidos; deja la fila del registro en «suspendida». La empresa vuelve SUSPENDIDA, igual que cuando se dio de baja:
# para que la usen otra vez, ESQUEMA=<E> sql/empresa.sh reactivar y arrancar su instancia.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/lib_sql.sh"
solo_local   # Data Pump y archivos del contenedor: solo con la base local

fallo() { echo "RECHAZADO: $*" >&2; exit 1; }

ORIGEN="${1:-}"; [ -n "$ORIGEN" ] || { sed -n '2,17p' "$0"; exit 1; }
ORIGEN="$(cd "$ORIGEN" 2>/dev/null && pwd)" || fallo "no existe la carpeta del respaldo."
[ -f "$ORIGEN/SHA256SUMS" ] && [ -f "$ORIGEN/registro.tsv" ] && [ -f "$ORIGEN/carpeta_empresa.tar.gz" ] || fallo "$ORIGEN no parece un respaldo de baja_empresa.sh."

# ---------- 0. Validaciones (no tocan nada) ----------
( cd "$ORIGEN" && sha256sum --quiet -c SHA256SUMS ) || fallo "las huellas del respaldo NO coinciden: esta incompleto o fue modificado."
ESQUEMA="$(awk -F'\t' 'NR == 2 {print $1}' "$ORIGEN/registro.tsv")"
nombres_derivados || exit 1
E="$ESQUEMA"
conexiones
DMP="$(cd "$ORIGEN" && ls baja_"${E}"_*.dmp 2>/dev/null | head -1)"
[ -n "$DMP" ] || fallo "el respaldo no tiene el .dmp de $E."
DMP="${DMP%.dmp}"

existen=$(valor_sys "SELECT (SELECT COUNT(*) FROM dba_users WHERE username IN ('$E','$USR_APP','$USR_REPORTES')) + (SELECT COUNT(*) FROM dba_roles WHERE role IN ('$ROL_APP','$ROL_LECTURA','$ROL_AUDITORIA')) + (SELECT COUNT(*) FROM dba_context WHERE namespace = '$CTX') + (SELECT COUNT(DISTINCT profile) FROM dba_profiles WHERE profile = '$PERFIL') FROM dual")
[ "$existen" = "0" ] || fallo "en la base ya existen $existen objetos globales de $E: no se pisa una empresa viva."
DIR="$RAIZ_REPO/empresas/$E"
[ ! -e "$DIR" ] || fallo "ya existe $DIR."
en_registro="$(registro_campo "$E" 1)"
[ -z "$en_registro" ] || [ "$(registro_campo "$E" 9)" = "baja" ] || fallo "$E esta en el registro con estado «$(registro_campo "$E" 9)», no «baja»."
PUERTO="$(awk -F'\t' 'NR == 2 {print $4}' "$ORIGEN/registro.tsv")"
! ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$PUERTO\$" || fallo "el puerto $PUERTO esta ocupado."

echo "Se va a RESTAURAR la empresa $E desde $ORIGEN:"
echo "  disco: $DIR (y, si estaban fuera, sus credenciales y archivos)"
echo "  base : esquema $E, cuentas $USR_APP y $USR_REPORTES, roles, perfil y contexto (con las claves de antes) e importacion del esquema"
if [ "${CONFIRMO_RESTAURAR:-}" = "$E" ]; then :
elif [ -t 0 ]; then
    read -r -p "Escriba el nombre del esquema ($E) para confirmar: " resp
    [ "$resp" = "$E" ] || { echo "No coincide: cancelado, no se toco nada." >&2; exit 1; }
else
    echo "Sin terminal: confirme con CONFIRMO_RESTAURAR=$E. Cancelado, no se toco nada." >&2; exit 1
fi

umask 077
TMP="$(mktemp -d)"
limpiar() { rm -rf "$TMP"; docker exec "${CONTENEDOR:-oracle-xe}" rm -f "$RUTA_RESPALDOS/$DMP.dmp" "$RUTA_RESPALDOS/imp_$DMP.log" || true; }
trap limpiar EXIT

# ---------- 1. Disco ----------
echo ">> disco"
tar -C "$RAIZ_REPO/empresas" -xzf "$ORIGEN/carpeta_empresa.tar.gz"
inst() { sed -n "s/^$1=//p" "$DIR/instancia.env" | tail -1 | sed -e "s/^[\"']//" -e "s/[\"']\$//"; }
CRED="$(inst CREDENCIALES)"; CRED="${CRED:-$DIR/credenciales.txt}"
case "$CRED" in /*) ;; *) CRED="$RAIZ_REPO/$CRED" ;; esac
if [ -f "$ORIGEN/credenciales.txt" ]; then
    if [ -f "$CRED" ]; then
        cmp -s "$ORIGEN/credenciales.txt" "$CRED" || fallo "$CRED existe y es distinto al del respaldo: revise a mano (se restauro $DIR, nada en la base)."
    else
        cp -p "$ORIGEN/credenciales.txt" "$CRED"; chmod 600 "$CRED"
    fi
fi
if [ -f "$ORIGEN/docs.tar.gz" ]; then
    DOCS="$(inst SILA_DOCS_DIR)"
    [ -n "$DOCS" ] && [ ! -e "$DOCS" ] || fallo "no se puede restaurar la carpeta de archivos en «$DOCS»."
    mkdir -p "$(dirname "$DOCS")"; tar -C "$(dirname "$DOCS")" -xzf "$ORIGEN/docs.tar.gz"
fi
clave_de() { awk -v k="$1" '$1 == k {print $2; exit}' "$CRED"; }
PWD_APP="$(clave_de SILA_DB_CLAVE)"; PWD_REP="$(clave_de "${E}_REPORTES")"
[ -n "$PWD_APP" ] && [ -n "$PWD_REP" ] || fallo "faltan las claves de las cuentas en $CRED."
export PWD_APP PWD_REP

# ---------- 2. Objetos globales con las claves de antes ----------
echo ">> objetos globales (bootstrap)"
render "$AQUI/inicial/01_bootstrap.sql" "$TMP/01_bootstrap.sql"
sql_con "$SYS_CONN" < "$TMP/01_bootstrap.sql" > "$TMP/bootstrap.log" 2>&1 || true
sin_errores "$TMP/bootstrap.log" > /dev/null || { grep -nE "ORA-|SP2-" "$TMP/bootstrap.log" >&2; echo "Fallo el bootstrap: revise y borre lo creado con sql/borrar_empresa_prueba.sh si hace falta." >&2; exit 1; }

# ---------- 3. Importacion ----------
echo ">> importacion del esquema (impdp)"
asegurar_dir_respaldos
docker cp "$ORIGEN/$DMP.dmp" "${CONTENEDOR:-oracle-xe}:$RUTA_RESPALDOS/$DMP.dmp"
docker exec -u 0 "${CONTENEDOR:-oracle-xe}" chown oracle:oinstall "$RUTA_RESPALDOS/$DMP.dmp"
datapump impdp "schemas=$E directory=$DIR_RESPALDOS dumpfile=$DMP.dmp logfile=imp_$DMP.log" > "$TMP/impdp.log" 2>&1 || true
docker cp "${CONTENEDOR:-oracle-xe}:$RUTA_RESPALDOS/imp_$DMP.log" "$DIR/logs/restauracion_$DMP.log" 2>/dev/null || cp "$TMP/impdp.log" "$DIR/logs/restauracion_$DMP.log"
# El unico error admitido: ORA-31684 (el usuario dueno ya existe: lo creo el bootstrap).
grep -q "completed" "$TMP/impdp.log" || { tail -15 "$TMP/impdp.log" >&2; echo "impdp no termino." >&2; exit 1; }
otros=$(grep -E "^ORA-[0-9]+" "$TMP/impdp.log" | grep -v "^ORA-31684" || true)
[ -z "$otros" ] || { printf '%s\n' "$otros" | head -15 >&2; echo "impdp reporto errores (detalle en $DIR/logs/restauracion_$DMP.log)." >&2; exit 1; }

# ---------- 4. Verificacion ----------
verificar_esquema || { echo "El esquema restaurado tiene objetos invalidos o triggers deshabilitados." >&2; exit 1; }
estado=$(valor_dueno "SELECT estado FROM empresa")
if [ -n "$en_registro" ]; then
    registro_poner "$E" 9 "$(printf '%s' "$estado" | tr '[:upper:]' '[:lower:]')"
else
    registro_asegurar
    awk -F'\t' -v OFS='\t' -v s="$(printf '%s' "$estado" | tr '[:upper:]' '[:lower:]')" 'NR == 2 {$9 = s; print}' "$ORIGEN/registro.tsv" >> "$REGISTRO"
fi
echo "Empresa $E restaurada (estado $estado, version $(valor_dueno "SELECT MAX(numero) FROM version_esquema"))."
[ "$estado" != "SUSPENDIDA" ] || echo "Para volver a usarla: ESQUEMA=$E sql/empresa.sh reactivar && ./arrancar.sh $E jar"
