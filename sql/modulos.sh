#!/usr/bin/env bash
# Operacion del DUENO: ver y cambiar los modulos de una empresa. La app y el ADMIN de la empresa NO pueden hacerlo.
#
#   SYSTEM_PWD=<clave de SYSTEM> ESQUEMA=SILA_EMPRESAS ./modulos.sh listar
#   SYSTEM_PWD=... ESQUEMA=... ./modulos.sh desactivar PRECIOS_CLIENTE MARGEN
#   SYSTEM_PWD=... ESQUEMA=... ./modulos.sh activar PRECIOS_CLIENTE
#   (opcional --forzar al final: apagar CREDITO aunque haya clientes con deuda)
#
# El cambio queda en auditoria_cambios (tabla MODULOS) y en modulos.usuario_cambio/fecha_cambio. El backend lo nota en
# menos de un minuto (cache de 30 s), sin reiniciar. Los modulos del nucleo no se pueden apagar.
# Se niega a correr si el esquema es LLANOLAT.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/lib_dueno.sh"
dueno_init

listar() {
    sql_dueno <<'FIN'
SET PAGESIZE 100 LINESIZE 150 FEEDBACK OFF
COL codigo FORMAT A18
COL nombre FORMAT A32
COL nucleo FORMAT 9
COL activo FORMAT 9
COL ultimo_cambio FORMAT A20
COL por FORMAT A20
SELECT codigo, nombre, nucleo, activo, TO_CHAR(fecha_cambio, 'YYYY-MM-DD HH24:MI:SS') AS ultimo_cambio, usuario_cambio AS por
  FROM modulos ORDER BY orden;
FIN
}

cambiar() {   # cambiar <0|1> CODIGO...
    local valor="$1"; shift
    local forzar=0 codigos=()
    for a in "$@"; do [ "$a" = "--forzar" ] && forzar=1 || codigos+=("$(printf '%s' "$a" | tr '[:lower:]' '[:upper:]')"); done
    [ "${#codigos[@]}" -gt 0 ] || { echo "Falta al menos un CODIGO. Use: $0 listar" >&2; exit 1; }
    for c in "${codigos[@]}"; do
        [[ "$c" =~ ^[A-Z][A-Z0-9_]*$ ]] || { echo "Codigo invalido: $c" >&2; exit 1; }
        local estado
        estado=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nSELECT NVL(MAX(nucleo || ':' || activo), 'NO') FROM modulos WHERE codigo = '%s';\n" "$c" | sql_dueno | tr -d '[:space:]')
        [ "$estado" != "NO" ] || { echo "El modulo $c no existe. Use: $0 listar" >&2; exit 1; }
        [ "${estado%%:*}" = "0" ] || { echo "El modulo $c es del nucleo: no se puede apagar." >&2; exit 1; }
        if [ "$valor" = "0" ] && [ "$c" = "CREDITO" ] && [ "$forzar" = "0" ]; then
            local deuda
            deuda=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nSELECT COUNT(*) || ':' || NVL(SUM(saldo_deudor), 0) FROM clientes WHERE saldo_deudor > 0;\n" | sql_dueno | tr -d '[:space:]')
            if [ "${deuda%%:*}" != "0" ]; then
                echo "RECHAZADO: hay ${deuda%%:*} cliente(s) con deuda pendiente (total ${deuda##*:}). Apagar CREDITO bloquea abonos y castigos:" >&2
                echo "esa deuda quedaria imposible de cobrar. Cobrela o castiguela primero, o repita con --forzar." >&2
                exit 1
            fi
        fi
    done
    for c in "${codigos[@]}"; do
        printf "BEGIN UPDATE modulos SET activo = %s WHERE codigo = '%s'; IF SQL%%ROWCOUNT <> 1 THEN RAISE_APPLICATION_ERROR(-20007, 'Modulo inexistente'); END IF; COMMIT; END;\n/\n" "$valor" "$c" | sql_dueno
        echo "$c -> $([ "$valor" = 1 ] && echo activo || echo inactivo)"
    done
}

accion="${1:-}"; [ $# -gt 0 ] && shift || true
case "$accion" in
    listar)     listar ;;
    activar)    cambiar 1 "$@"; listar ;;
    desactivar) cambiar 0 "$@"; listar ;;
    *) echo "Uso: $0 listar | activar CODIGO... | desactivar CODIGO... [--forzar]" >&2; exit 1 ;;
esac
