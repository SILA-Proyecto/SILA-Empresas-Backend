#!/usr/bin/env bash
# Operacion del DUENO, SOLO LECTURA: ver quien acepto los terminos y la politica de privacidad (Ley 1581). Las aceptaciones las
# escribe unicamente el backend (pkg_legal.sp_aceptar, cuando la persona acepta ella misma): este script no puede escribir nada
# (la sesion se abre con SET TRANSACTION READ ONLY: cualquier INSERT/UPDATE/DELETE falla con ORA-01456) y el ADMIN de la empresa
# no tiene como verlas. Se niega a correr si el esquema es LLANOLAT.
#
#   SYSTEM_PWD=<clave de SYSTEM> ESQUEMA=SILA_EMPRESAS ./legal.sh resumen
#   SYSTEM_PWD=... ESQUEMA=... ./legal.sh listar [--usuario ana.admin] [--limite 200]
#   SYSTEM_PWD=... ESQUEMA=... ./legal.sh pendientes
#
# "Vigente" = la version que rige en la instancia de ESA empresa: SILA_LEGAL_TERMINOS_VERSION / SILA_LEGAL_PRIVACIDAD_VERSION del
# entorno, o de empresas/<ESQUEMA>/instancia.env, o 1.0 (el mismo valor por defecto de application.yml).
#
# SALIDA: una linea por registro, campos separados por "|" (los "|" y saltos de linea de los datos se cambian por "/" y " "),
# la primera palabra dice que es. Las lineas que empiezan por "#" son comentarios.
#   resumen   VIGENTE|<DOCUMENTO>|<version>
#             USUARIOS_ACTIVOS|<n>            AL_DIA|<n>            PENDIENTES|<n>
#             ACEPTADO|<DOCUMENTO>|<version>|<personas>|<ultima aceptacion AAAA-MM-DD HH:MM:SS>     (todas las versiones)
#   listar    ACEPTACION|<id>|<fecha>|<usuario>|<nombre>|<rol>|<DOCUMENTO>|<version>|<ip>|<navegador>   (mas recientes primero)
#   pendientes PENDIENTE|<usuario>|<nombre>|<rol>|<falta: TERMINOS, PRIVACIDAD o TERMINOS+PRIVACIDAD>    (solo usuarios activos)
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/lib_dueno.sh"
dueno_init

# Existe la tabla de aceptaciones (script 34)?
hay=$(valor_sys "SELECT COUNT(*) FROM dba_tables WHERE owner = '$ESQUEMA' AND table_name = 'ACEPTACIONES_LEGALES'")
[ "$hay" = "1" ] || { echo "El esquema $ESQUEMA no tiene la tabla ACEPTACIONES_LEGALES (falta aplicar 34_aceptaciones_legales.sql con migrar.sh)." >&2; exit 1; }

# version_vigente TERMINOS|PRIVACIDAD
version_vigente() {
    local var="SILA_LEGAL_${1}_VERSION" v
    v="${!var:-}"
    [ -n "$v" ] || v="$(awk -F= -v k="$var" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$RAIZ_REPO/empresas/$ESQUEMA/instancia.env" 2>/dev/null || true)"
    v="${v:-1.0}"
    [[ "$v" =~ ^[0-9A-Za-z._-]{1,30}$ ]] || { echo "Version de $1 invalida: '$v' (letras, digitos, . _ - ; maximo 30)." >&2; exit 1; }
    printf '%s' "$v"
}

# Texto de un dato para una linea "a|b|c": sin "|" ni saltos de linea.
limpio() { printf "REPLACE(REPLACE(REPLACE(REPLACE(%s, '|', '/'), CHR(10), ' '), CHR(13), ' '), CHR(9), ' ')" "$1"; }

# Predicados SQL: la persona u tiene aceptada la version vigente del documento.
acepto() { printf "EXISTS (SELECT 1 FROM aceptaciones_legales a WHERE a.id_usuario = u.id_usuario AND a.documento = '%s' AND a.version = '%s')" "$1" "$2"; }

resumen() {
    local vt vp; vt="$(version_vigente TERMINOS)"; vp="$(version_vigente PRIVACIDAD)"
    sql_dueno <<FIN
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 1500 TRIMOUT ON TAB OFF
SET TRANSACTION READ ONLY;
SELECT '# resumen de aceptaciones legales de $ESQUEMA' FROM dual;
SELECT 'VIGENTE|TERMINOS|$vt' FROM dual;
SELECT 'VIGENTE|PRIVACIDAD|$vp' FROM dual;
SELECT 'USUARIOS_ACTIVOS|' || COUNT(*) FROM usuarios_app u WHERE u.activo = 1;
SELECT 'AL_DIA|' || COUNT(*) FROM usuarios_app u WHERE u.activo = 1 AND $(acepto TERMINOS "$vt") AND $(acepto PRIVACIDAD "$vp");
SELECT 'PENDIENTES|' || COUNT(*) FROM usuarios_app u WHERE u.activo = 1 AND NOT ($(acepto TERMINOS "$vt") AND $(acepto PRIVACIDAD "$vp"));
SELECT 'ACEPTADO|' || documento || '|' || version || '|' || COUNT(DISTINCT id_usuario) || '|' || TO_CHAR(MAX(fecha), 'YYYY-MM-DD HH24:MI:SS')
  FROM aceptaciones_legales GROUP BY documento, version ORDER BY documento, MAX(fecha) DESC;
FIN
}

listar() {
    local usuario="" limite=200
    while [ $# -gt 0 ]; do
        case "$1" in
            --usuario) [ $# -ge 2 ] || { echo "Falta el valor de --usuario" >&2; exit 1; }; usuario="$2"; shift 2 ;;
            --limite)  [ $# -ge 2 ] || { echo "Falta el valor de --limite" >&2; exit 1; }; limite="$2"; shift 2 ;;
            *) echo "Opcion desconocida: $1" >&2; exit 1 ;;
        esac
    done
    [[ "$limite" =~ ^[0-9]{1,5}$ ]] && [ "$limite" -ge 1 ] || { echo "--limite debe ser un numero de 1 a 99999." >&2; exit 1; }
    local filtro="1 = 1"
    if [ -n "$usuario" ]; then
        [[ "$usuario" =~ ^[A-Za-z0-9_.@-]{3,100}$ ]] || { echo "--usuario invalido (letras, digitos y . _ @ -)." >&2; exit 1; }
        filtro="usuario = '$usuario'"
    fi
    sql_dueno <<FIN
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 1500 TRIMOUT ON TAB OFF
SET TRANSACTION READ ONLY;
SELECT '# aceptaciones legales de $ESQUEMA (las $limite mas recientes)' FROM dual;
SELECT 'ACEPTACION|' || id_aceptacion || '|' || TO_CHAR(fecha, 'YYYY-MM-DD HH24:MI:SS') || '|' || $(limpio usuario) || '|' || $(limpio nombre)
       || '|' || rol || '|' || documento || '|' || version || '|' || $(limpio "NVL(ip, '')") || '|' || $(limpio "NVL(user_agent, '')")
  FROM (SELECT * FROM vw_aceptaciones_legales WHERE $filtro ORDER BY fecha DESC, id_aceptacion DESC)
 WHERE ROWNUM <= $limite;
FIN
}

pendientes() {
    local vt vp; vt="$(version_vigente TERMINOS)"; vp="$(version_vigente PRIVACIDAD)"
    sql_dueno <<FIN
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 1500 TRIMOUT ON TAB OFF
SET TRANSACTION READ ONLY;
SELECT '# usuarios activos sin aceptar TERMINOS $vt y PRIVACIDAD $vp en $ESQUEMA' FROM dual;
SELECT 'PENDIENTE|' || $(limpio "u.usuario") || '|' || $(limpio "u.nombre") || '|' || u.rol || '|'
       || CASE WHEN NOT $(acepto TERMINOS "$vt") AND NOT $(acepto PRIVACIDAD "$vp") THEN 'TERMINOS+PRIVACIDAD'
               WHEN NOT $(acepto TERMINOS "$vt") THEN 'TERMINOS' ELSE 'PRIVACIDAD' END
  FROM usuarios_app u
 WHERE u.activo = 1 AND NOT ($(acepto TERMINOS "$vt") AND $(acepto PRIVACIDAD "$vp"))
 ORDER BY u.usuario;
FIN
}

accion="${1:-}"; [ $# -gt 0 ] && shift || true
case "$accion" in
    resumen)    resumen ;;
    listar)     listar "$@" ;;
    pendientes) pendientes ;;
    *) echo "Uso: $0 resumen | listar [--usuario U] [--limite N] | pendientes   (con SYSTEM_PWD y ESQUEMA)" >&2; exit 1 ;;
esac
