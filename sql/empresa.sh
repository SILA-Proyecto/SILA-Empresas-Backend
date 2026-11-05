#!/usr/bin/env bash
# Operacion del DUENO: ver y fijar los datos de la empresa (una sola fila). Nombre, nombre corto y NIT SOLO los cambia el dueno;
# los datos de contacto, el pie del comprobante (EMPRESA_PIE) y el logo tambien los puede cambiar el ADMIN desde el dashboard.
#
#   SYSTEM_PWD=<clave de SYSTEM> ESQUEMA=SILA_EMPRESAS ./empresa.sh mostrar
#   SYSTEM_PWD=... ESQUEMA=... EMPRESA_NOMBRE='Lacteos Ejemplo SAS' EMPRESA_NOMBRE_CORTO='Ejemplo' \
#       EMPRESA_NIT='900.123.456-7' EMPRESA_DIRECCION='Calle 1 # 2-3' EMPRESA_TELEFONO='300 000 0000' \
#       EMPRESA_CIUDAD='Villavicencio' EMPRESA_CORREO='contacto@ejemplo.com' ./empresa.sh fijar
#
# Al CREAR la fila, EMPRESA_NOMBRE y EMPRESA_NOMBRE_CORTO son obligatorios. Al EDITAR solo cambia lo que se pasa
# (una variable vacia deja el campo en NULL). Cada cambio queda en auditoria_cambios (tabla EMPRESA).
# El backend lo nota en menos de un minuto. Se niega a correr si el esquema es LLANOLAT.
#
# Suspension (reversible; no borra ni cambia datos):
#   SYSTEM_PWD=... ESQUEMA=... EMPRESA_MOTIVO='Falta de pago' ./empresa.sh suspender
#   SYSTEM_PWD=... ESQUEMA=... ./empresa.sh reactivar
# Suspendida: el backend responde 403 / 20021 a todo (salvo nombre y logo del login) en menos de un minuto y la base deja de
# abrir sesiones de aplicacion al instante. Tambien cambia la columna estado de empresas/registro.tsv (suspendida / activa).
# La baja definitiva es otro script: sql/baja_empresa.sh (exige la empresa suspendida).
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/lib_dueno.sh"
dueno_init

mostrar() {
    sql_dueno <<'FIN'
SET PAGESIZE 100 LINESIZE 200 FEEDBACK OFF
COL campo FORMAT A18
COL valor FORMAT A100
SELECT 'nombre' campo, nombre valor FROM empresa UNION ALL SELECT 'nombre_corto', nombre_corto FROM empresa
UNION ALL SELECT 'nit', nit FROM empresa UNION ALL SELECT 'direccion', direccion FROM empresa
UNION ALL SELECT 'telefono', telefono FROM empresa UNION ALL SELECT 'ciudad', ciudad FROM empresa
UNION ALL SELECT 'correo_contacto', correo_contacto FROM empresa
UNION ALL SELECT 'pie_comprobante', pie_comprobante FROM empresa
UNION ALL SELECT 'logo', NVL((SELECT tipo || ', ' || bytes || ' bytes, ' || TO_CHAR(fecha_cambio, 'YYYY-MM-DD HH24:MI') || ' por ' || usuario_cambio
                              FROM empresa_logo), '(sin logo)') FROM empresa
UNION ALL SELECT 'estado', estado || NVL2(fecha_estado, ' desde ' || TO_CHAR(fecha_estado, 'YYYY-MM-DD HH24:MI'), '')
                 || NVL2(motivo_estado, ' (' || motivo_estado || ')', '') FROM empresa
UNION ALL SELECT 'ultimo_cambio', TO_CHAR(fecha_cambio, 'YYYY-MM-DD HH24:MI:SS') || ' por ' || usuario_cambio FROM empresa;
FIN
}

fijar() {
    local cols=() vals=() sets=() par
    # columna : variable
    for par in nombre:EMPRESA_NOMBRE nombre_corto:EMPRESA_NOMBRE_CORTO nit:EMPRESA_NIT direccion:EMPRESA_DIRECCION \
               telefono:EMPRESA_TELEFONO ciudad:EMPRESA_CIUDAD correo_contacto:EMPRESA_CORREO pie_comprobante:EMPRESA_PIE; do
        local col="${par%%:*}" var="${par##*:}"
        if [ -n "${!var+x}" ]; then
            sin_control "$var" "${!var}"
            local v="$(printf '%s' "${!var}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            local lit="NULL"; [ -z "$v" ] || lit="'$(esc "$v")'"
            cols+=("$col"); vals+=("$lit"); sets+=("$col = $lit")
        fi
    done
    [ "${#cols[@]}" -gt 0 ] || { echo "No se paso ningun dato (EMPRESA_NOMBRE, EMPRESA_NOMBRE_CORTO, EMPRESA_NIT, ...)." >&2; exit 1; }
    local hay
    hay=$(printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nSELECT COUNT(*) FROM empresa;\n" | sql_dueno | tr -d '[:space:]')
    if [ "$hay" = "0" ]; then
        [ -n "${EMPRESA_NOMBRE:-}" ] && [ -n "${EMPRESA_NOMBRE_CORTO:-}" ] || { echo "Para crear la fila de la empresa hacen falta EMPRESA_NOMBRE y EMPRESA_NOMBRE_CORTO." >&2; exit 1; }
        local c v; c="$(IFS=,; echo "${cols[*]}")"; v="$(IFS=,; echo "${vals[*]}")"
        printf "INSERT INTO empresa (id_empresa, %s) VALUES (1, %s);\nCOMMIT;\n" "$c" "$v" | sql_dueno
    else
        local s; s="$(IFS=,; echo "${sets[*]}")"
        printf "UPDATE empresa SET %s WHERE id_empresa = 1;\nCOMMIT;\n" "$s" | sql_dueno
    fi
}

# cambiar_estado ACTIVA|SUSPENDIDA "<motivo o vacio>"
cambiar_estado() {
    local nuevo="$1" motivo="$2" actual lit="NULL"
    actual=$(valor_dueno "SELECT estado FROM empresa")
    [ -n "$actual" ] || { echo "La empresa no tiene fila de datos (o falta aplicar 33_estado_empresa.sql con migrar.sh)." >&2; exit 1; }
    if [ "$actual" = "$nuevo" ]; then
        echo "La empresa ya estaba en estado $nuevo: no se cambio nada."
    else
        [ -z "$motivo" ] || lit="'$(esc "$motivo")'"
        printf "UPDATE empresa SET estado = '%s', motivo_estado = %s WHERE id_empresa = 1;\nCOMMIT;\n" "$nuevo" "$lit" | sql_dueno
    fi
    [ -z "$(registro_campo "$ESQUEMA" 1)" ] || registro_poner "$ESQUEMA" 9 "$(printf '%s' "$nuevo" | tr '[:upper:]' '[:lower:]')"
}

accion="${1:-}"
case "$accion" in
    mostrar)    mostrar ;;
    fijar)      fijar; mostrar ;;
    suspender)
        sin_control EMPRESA_MOTIVO "${EMPRESA_MOTIVO:-}"
        motivo="$(printf '%s' "${EMPRESA_MOTIVO:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -n "$motivo" ] || { echo "Falta EMPRESA_MOTIVO (por que se suspende; queda en la auditoria)." >&2; exit 1; }
        [ "${#motivo}" -le 300 ] || { echo "EMPRESA_MOTIVO: maximo 300 caracteres." >&2; exit 1; }
        cambiar_estado SUSPENDIDA "$motivo"; mostrar ;;
    reactivar)  cambiar_estado ACTIVA ""; mostrar ;;
    *) echo "Uso: $0 mostrar | fijar (con EMPRESA_NOMBRE, EMPRESA_NOMBRE_CORTO, EMPRESA_NIT, EMPRESA_DIRECCION, EMPRESA_TELEFONO, EMPRESA_CIUDAD, EMPRESA_CORREO, EMPRESA_PIE) | suspender (con EMPRESA_MOTIVO) | reactivar" >&2; exit 1 ;;
esac
