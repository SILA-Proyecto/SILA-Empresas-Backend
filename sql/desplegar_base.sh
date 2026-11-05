#!/usr/bin/env bash
# Construye un esquema SILA LIMPIO (y sus cuentas, roles, perfil y contexto) dentro de un contenedor Oracle XE.
# Para crear una EMPRESA completa (claves, directorio de archivos, configuracion de la instancia, registro) use crear_empresa.sh,
# que llama a este script.
#
#   SYSTEM_PWD=<clave de SYSTEM> ESQUEMA=SILA_EMPRESAS \
#   ADMIN_USUARIO=<usuario> ADMIN_NOMBRE='<nombre>' ADMIN_EMAIL='<correo>' \
#   EMPRESA_NOMBRE='<nombre completo>' EMPRESA_NOMBRE_CORTO='<nombre corto>' ./desplegar_base.sh
#   (opcionales: CONTENEDOR=oracle-xe, DESTINO=<carpeta de credenciales.txt, por defecto la raiz del repo>, LOGS=<carpeta de logs>,
#    CON_DATOS_PRUEBA=1, EMPRESA_NIT, EMPRESA_DIRECCION, EMPRESA_TELEFONO, EMPRESA_CIUDAD, EMPRESA_CORREO,
#    MODULOS_INACTIVOS='CODIGO CODIGO' = modulos que nacen apagados; por defecto TODOS activos)
#
# Hace, en orden: (1) verifica nombres y que nada de lo derivado exista; (2) prepara todos los scripts antes de tocar la base;
# (3) genera las claves; (4) bootstrap de los objetos GLOBALES (sql/inicial/01_bootstrap.sql: dueno, cuentas, roles, perfil,
# contexto) y migrar.sh aplica TODOS los scripts sql/NN_*.sql (es el unico camino de cambio de la base y deja el registro en
# version_esquema); (5) datos de la empresa y modulos; (6) primer ADMIN con clave temporal; (7) semilla (y datos de prueba si se
# pide); (8) verificacion.
# Los datos de la empresa (EMPRESA_*) son la UNICA fuente del nombre, NIT, etc.: se siembran aqui y despues solo se cambian con empresa.sh.
#
# SE NIEGA A CORRER si el esquema es LLANOLAT, si algun nombre derivado coincide con un nombre de Llanolat, o si en la base ya existe
# cualquiera de los usuarios, roles, perfil o contexto derivados. NO corre pruebas de humo, limpiezas ni purgas.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/lib_sql.sh"
: "${SYSTEM_PWD:?Falta SYSTEM_PWD (clave de SYSTEM)}"
: "${ADMIN_USUARIO:?Falta ADMIN_USUARIO}"
: "${ADMIN_NOMBRE:?Falta ADMIN_NOMBRE}"
: "${ADMIN_EMAIL:?Falta ADMIN_EMAIL}"
: "${EMPRESA_NOMBRE:?Falta EMPRESA_NOMBRE (nombre completo de la empresa)}"
: "${EMPRESA_NOMBRE_CORTO:?Falta EMPRESA_NOMBRE_CORTO (p. ej. el que va en «SILA <corto>»)}"

nombres_derivados || exit 1
conexiones
export CONTENEDOR="${CONTENEDOR:-oracle-xe}"
DESTINO="${DESTINO:-$RAIZ_REPO}"
LOGS="${LOGS:-$AQUI/salida/logs}"
umask 077
mkdir -p "$DESTINO" "$LOGS"
CRED="$DESTINO/credenciales.txt"
[ ! -e "$CRED" ] || { echo "Ya existe $CRED: no lo piso. Muevelo o borralo a proposito." >&2; exit 1; }

# --- 1. Que sea un esquema nuevo: nada de lo derivado puede existir ---
EXISTE=$(valor_sys "SELECT (SELECT COUNT(*) FROM dba_users    WHERE username  IN ('$ESQUEMA','$USR_APP','$USR_REPORTES'))
     + (SELECT COUNT(*) FROM dba_roles    WHERE role      IN ('$ROL_APP','$ROL_LECTURA','$ROL_AUDITORIA'))
     + (SELECT COUNT(*) FROM dba_profiles WHERE profile   = '$PERFIL')
     + (SELECT COUNT(*) FROM dba_context  WHERE namespace = '$CTX') FROM dual")
[ "$EXISTE" = "0" ] || { echo "Ya existe algo con los nombres de $ESQUEMA en la base (coincidencias: $EXISTE): esto es solo para un esquema nuevo." >&2; exit 1; }

# --- 2. Todos los scripts deben poder prepararse ANTES de tocar la base (marcadores completos) ---
PWD_APP="A$(clave)"; PWD_REP="R$(clave)"; ADMIN_TEMP="$(clave)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for f in "$AQUI"/inicial/*.sql "$AQUI"/[0-9][0-9]_*.sql; do
    render "$f" "$TMP/$(basename "$f")" || { echo "Fallo al preparar $(basename "$f"); la base no se toco." >&2; exit 1; }
done
grep -c 'IDENTIFIED BY "' "$TMP/01_bootstrap.sql" | grep -qx 2 || { echo "El bootstrap no tiene las 2 cuentas esperadas" >&2; exit 1; }

# --- 3. Claves nuevas (solo quedan en credenciales.txt) ---
JWT="$(openssl rand -base64 48 | tr -d '\n')"; MFA="$(openssl rand -base64 32 | tr -d '\n')"; DOCS="$(head -c 32 /dev/urandom | base64 -w0)"
{
  echo "# SILA Empresas - claves de $ESQUEMA. Generadas $(date -u +%FT%TZ). chmod 600. NO subir a git."
  echo "SILA_DB_ESQUEMA $ESQUEMA"
  echo "SILA_DB_USUARIO $USR_APP"
  echo "SILA_DB_CLAVE $PWD_APP"
  echo "$USR_REPORTES $PWD_REP"
  echo "SILA_JWT_SECRET $JWT"
  echo "SILA_MFA_KEY $MFA"
  echo "SILA_DOCS_KEY $DOCS"
  echo "SILA_ADMIN_TEMP $ADMIN_TEMP"
} > "$CRED"
chmod 600 "$CRED"

# --- 4. Bootstrap de los objetos globales (como SYSTEM) y migraciones (como dueno, por proxy) ---
echo ">> bootstrap"
sql_con "$SYS_CONN" < "$TMP/01_bootstrap.sql" > "$LOGS/01_bootstrap.log"
sin_errores "$LOGS/01_bootstrap.log" || { echo "Error en el bootstrap: reviso $LOGS/01_bootstrap.log y me detengo." >&2; exit 1; }
unset PWD_APP PWD_REP   # las claves de las cuentas no se pasan a los scripts siguientes
SYSTEM_PWD="$SYSTEM_PWD" ESQUEMA="$ESQUEMA" LOGS="$LOGS" "$AQUI/migrar.sh"

# --- 5. Datos de la empresa y modulos de partida, como DUENO (la app no puede escribirlos) ---
echo ">> empresa y modulos"
export SYSTEM_PWD ESQUEMA EMPRESA_NOMBRE EMPRESA_NOMBRE_CORTO
"$AQUI/empresa.sh" fijar > "$LOGS/empresa.log"
if [ -n "${MODULOS_INACTIVOS:-}" ]; then
    # shellcheck disable=SC2086
    "$AQUI/modulos.sh" desactivar $MODULOS_INACTIVOS > "$LOGS/modulos.log"
fi

# --- 6. Primer ADMIN (clave temporal; el backend le exige cambiarla y activar MFA) ---
PWD_APP_CRED="$(awk '$1=="SILA_DB_CLAVE"{print $2}' "$CRED")"
HASH=$(PW="$ADMIN_TEMP" python3 -c "import os,bcrypt;print(bcrypt.hashpw(os.environ['PW'].encode(),bcrypt.gensalt(12)).decode())")
CONN_APP="$USR_APP/\"$PWD_APP_CRED\"@$SERVICIO_DB"
sin_control ADMIN_USUARIO "$ADMIN_USUARIO"; sin_control ADMIN_NOMBRE "$ADMIN_NOMBRE"; sin_control ADMIN_EMAIL "$ADMIN_EMAIL"
printf "SET DEFINE OFF\nSET SQLBLANKLINES ON\nALTER SESSION SET CURRENT_SCHEMA = %s;\nBEGIN pkg_autenticacion.sp_crear_admin_inicial('%s','%s','%s','%s'); END;\n/\n" \
  "$ESQUEMA" "$(esc "$ADMIN_USUARIO")" "$(esc "$ADMIN_NOMBRE")" "$(esc "$ADMIN_EMAIL")" "$HASH" | sql_con "$CONN_APP" > "$LOGS/admin_inicial.log"

# --- 7. Semilla (y datos de prueba si se pide) ---
sql_con "$CONN_APP" < "$TMP/21_semilla_servidor.sql" > "$LOGS/21_semilla.log"
if [ "${CON_DATOS_PRUEBA:-0}" = "1" ]; then
    sql_con "$PROXY_CONN" < "$TMP/25_datos_prueba.sql" > "$LOGS/25_datos_prueba.log"   # como dueno: la cuenta de la app no ve tablas
fi

# --- 8. Verificacion ---
echo; echo "== Errores en los logs (debe quedar vacio) =="
grep -nE "ORA-[0-9]+|PLS-[0-9]+|SP2-[0-9]+|Warning: .*(created|compiled) with (compilation )?errors" "$LOGS"/*.log || echo "(ninguno)"
echo; echo "== Objetos del esquema $ESQUEMA =="
sql_sys <<FIN
SET PAGESIZE 100 FEEDBACK OFF
SELECT object_type, COUNT(*) AS total FROM dba_objects WHERE owner = '$ESQUEMA' AND object_type IN ('TABLE','VIEW','PACKAGE','TRIGGER','FUNCTION','INDEX') GROUP BY object_type ORDER BY 1;
SELECT 'invalidos' AS que, COUNT(*) AS total FROM dba_objects WHERE owner = '$ESQUEMA' AND status <> 'VALID'
UNION ALL SELECT 'triggers_no_habilitados', COUNT(*) FROM dba_triggers WHERE owner = '$ESQUEMA' AND status <> 'ENABLED';
FIN
cat "$LOGS/21_semilla.log"
echo; echo "Claves nuevas en $CRED. Primer ADMIN: $ADMIN_USUARIO (clave temporal = SILA_ADMIN_TEMP en ese archivo)."
