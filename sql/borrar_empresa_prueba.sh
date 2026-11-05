#!/usr/bin/env bash
# Borra UNA empresa de PRUEBA (solo para limpiar las de esta fase; no es la baja de empresas reales).
#
#   SYSTEM_PWD=<clave de SYSTEM> sql/borrar_empresa_prueba.sh SILA_PRUEBA_DOS
#
# Protecciones:
#   * se NIEGA con LLANOLAT (cualquier nombre que lo contenga) y con SILA_EMPRESAS;
#   * solo acepta esquemas que esten en empresas/registro.tsv MARCADOS COMO PRUEBA (--prueba al crearlos);
#   * se niega si su backend sigue escuchando en su puerto (pare la instancia primero);
#   * muestra que va a eliminar y pide ESCRIBIR el nombre del esquema (o CONFIRMO_BORRADO=<ESQUEMA> si no hay terminal).
# Elimina: el esquema (dueno, con todo su contenido), las cuentas <E>_APP y <E>_REPORTES, los 3 roles, el perfil, el contexto,
# la carpeta empresas/<E> (claves, configuracion, archivos cifrados y logs) y su fila del registro.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/lib_sql.sh"

E="${1:-}"; [ -n "$E" ] || { sed -n '2,15p' "$0"; exit 1; }
ESQUEMA="$E"
nombres_derivados || exit 1
E="$ESQUEMA"
[ "$E" != "SILA_EMPRESAS" ] || { echo "RECHAZADO: SILA_EMPRESAS no se borra con este script." >&2; exit 1; }
conexiones
[ -n "$(registro_campo "$E" 1)" ] || { echo "RECHAZADO: $E no esta en empresas/registro.tsv." >&2; exit 1; }
[ "$(registro_campo "$E" 8)" = "si" ] || { echo "RECHAZADO: $E no esta marcada como PRUEBA en el registro; este script solo borra empresas de prueba." >&2; exit 1; }
PUERTO="$(registro_campo "$E" 4)"
! ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$PUERTO\$" || { echo "RECHAZADO: algo escucha en el puerto $PUERTO (la instancia de $E sigue en marcha). Paresela primero." >&2; exit 1; }
DIR="$RAIZ_REPO/empresas/$E"
[ "$DIR" = "$RAIZ_REPO/empresas/$E" ] && [[ "$E" =~ ^SILA_[A-Z0-9_]+$ ]] || { echo "RECHAZADO: ruta inesperada." >&2; exit 1; }

echo "Se va a ELIMINAR la empresa de prueba $E ($(registro_campo "$E" 2)):"
echo "  base   : esquema $E, cuentas $USR_APP y $USR_REPORTES, roles $ROL_APP/$ROL_LECTURA/$ROL_AUDITORIA, perfil $PERFIL, contexto $CTX"
echo "  disco  : $DIR (claves, configuracion, archivos cifrados, logs)"
echo "  registro: su fila en empresas/registro.tsv"
if [ "${CONFIRMO_BORRADO:-}" = "$E" ]; then :
elif [ -t 0 ]; then
    read -r -p "Escriba el nombre del esquema ($E) para confirmar: " resp
    [ "$resp" = "$E" ] || { echo "No coincide: cancelado, no se borro nada." >&2; exit 1; }
else
    echo "Sin terminal: confirme con CONFIRMO_BORRADO=$E. Cancelado, no se borro nada." >&2; exit 1
fi

# DROP USER ... CASCADE falla si hay sesiones abiertas: se avisa en vez de matarlas.
resto=$(borrar_objetos_globales)
rm -rf -- "$DIR"
tmp="$(mktemp)"; awk -F'\t' -v e="$E" '$1 != e' "$REGISTRO" > "$tmp" && cat "$tmp" > "$REGISTRO"; rm -f "$tmp"
echo "Empresa de prueba $E eliminada (restos en la base: $resto)."
