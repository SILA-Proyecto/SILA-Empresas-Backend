#!/usr/bin/env bash
# Ejecutor de migraciones: aplica a UNA empresa los scripts de sql/ que aun no tiene, en orden numerico, y los registra
# en su tabla version_esquema. Es el unico camino para cambiar la base (desplegar_base.sh tambien lo usa).
#
#   SYSTEM_PWD=<clave de SYSTEM> ESQUEMA=SILA_EMPRESAS ./migrar.sh --plan          # solo muestra que aplicaria
#   SYSTEM_PWD=... ESQUEMA=SILA_EMPRESAS ./migrar.sh                               # aplica lo pendiente
#   SYSTEM_PWD=... ESQUEMA=SILA_EMPRESAS ./migrar.sh --linea-base                  # base que ya existia: registra sin ejecutar
#
# Los scripts migrables son sql/NN_nombre.sql (dos digitos). Lo que NO es migracion vive en sql/inicial/ (bootstrap de
# objetos globales, semilla y datos de prueba) y lo corre desplegar_base.sh una sola vez.
# Reglas:
#   * un script APLICADO NO SE EDITA: si su huella (SHA-256 del archivo original) cambio, se detiene y lo dice. Los cambios van
#     en un script NUEVO con un numero MAYOR al ultimo aplicado.
#   * se detiene en el primer error de Oracle y NO registra el script que fallo.
#   * al terminar recompila el esquema y exige 0 objetos invalidos y 0 triggers deshabilitados.
#   * --linea-base: para una base construida antes de que existiera version_esquema. Crea la tabla (script 00, lo unico que
#     ejecuta) y REGISTRA el resto como LINEA_BASE sin ejecutarlo. Pide escribir el nombre del esquema (o CONFIRMO_LINEA_BASE=<ESQUEMA>).
#   * se niega con LLANOLAT, como los demas scripts.
set -eo pipefail   # sin -u: bash 5 trata los arreglos asociativos vacios como "sin asignar"
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/lib_sql.sh"

modo=aplicar
for a in "$@"; do
    case "$a" in
        --plan) modo=plan ;;
        --linea-base) modo=base ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        *) echo "Opcion desconocida: $a (use --plan o --linea-base)" >&2; exit 1 ;;
    esac
done

nombres_derivados || exit 1
conexiones
LOGS="${LOGS:-$AQUI/salida/logs}"; mkdir -p "$LOGS"
[ "$(valor_sys "SELECT COUNT(*) FROM dba_users WHERE username = '$ESQUEMA'")" = "1" ] \
    || { echo "El esquema $ESQUEMA no existe en la base (para una empresa nueva use crear_empresa.sh)." >&2; exit 1; }

# --- Scripts migrables, en orden numerico ---
mapfile -t ARCHIVOS < <(cd "$AQUI" && ls [0-9][0-9]_*.sql 2>/dev/null | sort)
[ "${#ARCHIVOS[@]}" -gt 0 ] || { echo "No hay scripts NN_*.sql en $AQUI" >&2; exit 1; }
declare -A HUELLA_ARCHIVO
for f in "${ARCHIVOS[@]}"; do HUELLA_ARCHIVO[$f]="$(sha256sum "$AQUI/$f" | cut -d' ' -f1)"; done
numero_de() { echo $((10#${1:0:2})); }

# --- Lo que la base ya tiene aplicado ---
declare -A APLICADA
MAX_APLICADO=-1
hay_tabla=$(valor_sys "SELECT COUNT(*) FROM dba_tables WHERE owner = '$ESQUEMA' AND table_name = 'VERSION_ESQUEMA'")
if [ "$hay_tabla" = "1" ]; then
    while read -r nombre huella numero; do
        [ -n "${nombre:-}" ] || continue
        APLICADA[$nombre]="$huella"
        [ "$numero" -le "$MAX_APLICADO" ] || MAX_APLICADO="$numero"
    done < <(printf 'SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 400\nSELECT nombre || chr(32) || huella || chr(32) || numero FROM version_esquema ORDER BY numero;\n' | sql_dueno)
fi

# --- Antes de aplicar nada: ningun script aplicado puede haber cambiado ni desaparecido ---
problemas=0
for nombre in "${!APLICADA[@]}"; do
    if [ -z "${HUELLA_ARCHIVO[$nombre]:-}" ]; then
        echo "ERROR: $nombre figura como aplicado en $ESQUEMA pero ya no existe en sql/." >&2; problemas=1
    elif [ "${HUELLA_ARCHIVO[$nombre]}" != "${APLICADA[$nombre]}" ]; then
        echo "ERROR: $nombre YA ESTA APLICADO en $ESQUEMA y fue EDITADO (huella distinta)." >&2
        echo "       un script aplicado no se edita: restaure el original y ponga el cambio en un script nuevo (numero mayor)." >&2; problemas=1
    fi
done
[ "$problemas" = "0" ] || exit 1

PENDIENTES=()
for f in "${ARCHIVOS[@]}"; do
    [ -z "${APLICADA[$f]:-}" ] || continue
    if [ "$(numero_de "$f")" -lt "$MAX_APLICADO" ]; then
        echo "ERROR: $f esta pendiente pero su numero es MENOR que el ultimo aplicado ($MAX_APLICADO) en $ESQUEMA." >&2
        echo "       los cambios nuevos llevan un numero mayor al ultimo aplicado." >&2; exit 1
    fi
    PENDIENTES+=("$f")
done

mostrar_plan() {
    echo "Esquema $ESQUEMA: ${#APLICADA[@]} script(s) aplicado(s)$([ "$MAX_APLICADO" -ge 0 ] && echo ", ultimo numero $MAX_APLICADO")."
    if [ "${#PENDIENTES[@]}" -eq 0 ]; then echo "Nada pendiente."; else
        echo "Pendientes (${#PENDIENTES[@]}), en este orden:"; printf '  %s\n' "${PENDIENTES[@]}"; fi
}

registrar() {   # registrar <archivo> <origen> <duracion_ms>
    printf "SET DEFINE OFF\nINSERT INTO version_esquema (numero, nombre, huella, origen, usuario, duracion_ms) VALUES (%d, '%s', '%s', '%s', '%s', %d);\nCOMMIT;\n" \
        "$(numero_de "$1")" "$(esc "$1")" "${HUELLA_ARCHIVO[$1]}" "$2" "migrar.sh:$(whoami)" "$3" | sql_dueno > /dev/null
}

TMP="$(mktemp -d)"; chmod 700 "$TMP"; trap 'rm -rf "$TMP"' EXIT
ejecutar_script() {   # ejecutar_script <archivo>  -> corre como dueno por proxy; devuelve 1 si Oracle reporta error
    render "$AQUI/$1" "$TMP/$1" || return 1
    sql_con "$PROXY_CONN" < "$TMP/$1" > "$LOGS/${1%.sql}.log"
    sin_errores "$LOGS/${1%.sql}.log"
}
ahora_ms() { date +%s%3N; }
actualizar_registro() {
    local maxn; maxn=$(valor_dueno "SELECT NVL(MAX(numero), 0) FROM version_esquema") || return 0
    [ -z "$(registro_campo "$ESQUEMA" 1)" ] || registro_poner "$ESQUEMA" 7 "$maxn"
}

case "$modo" in
plan)
    mostrar_plan ;;

base)
    tablas=$(valor_sys "SELECT COUNT(*) FROM dba_tables WHERE owner = '$ESQUEMA'")
    [ "$tablas" -gt 0 ] || { echo "El esquema $ESQUEMA esta vacio: no hay nada que registrar como linea base (use desplegar_base.sh)." >&2; exit 1; }
    [ "${#APLICADA[@]}" -eq 0 ] || { echo "version_esquema de $ESQUEMA ya tiene ${#APLICADA[@]} fila(s): la linea base es solo para una base sin registro." >&2; exit 1; }
    echo "LINEA BASE de $ESQUEMA: se registraran como YA APLICADOS ${#PENDIENTES[@]} script(s) SIN ejecutarlos (solo se crea version_esquema con 00)."
    echo "Hagalo unicamente si la base ya tiene exactamente estos scripts. Si no coincide, las migraciones futuras fallaran o se saltaran."
    printf '  %s\n' "${PENDIENTES[@]}"
    if [ "${CONFIRMO_LINEA_BASE:-}" = "$ESQUEMA" ]; then :
    elif [ -t 0 ]; then
        read -r -p "Escriba el nombre del esquema ($ESQUEMA) para confirmar: " resp
        [ "$resp" = "$ESQUEMA" ] || { echo "No coincide: cancelado, no se cambio nada." >&2; exit 1; }
    else
        echo "Sin terminal: confirme con CONFIRMO_LINEA_BASE=$ESQUEMA. Cancelado, no se cambio nada." >&2; exit 1
    fi
    for f in "${PENDIENTES[@]}"; do
        if [ "$f" = "00_version_esquema.sql" ]; then
            t0=$(ahora_ms); ejecutar_script "$f" || { echo "Error en $f ($LOGS/${f%.sql}.log): no se registro nada." >&2; exit 1; }
            registrar "$f" EJECUTADO $(( $(ahora_ms) - t0 ))
        else
            registrar "$f" LINEA_BASE 0
        fi
        echo "  registrado: $f"
    done
    verificar_esquema || { echo "ADVERTENCIA: la base tiene objetos invalidos o triggers deshabilitados (no es culpa de la linea base)." >&2; }
    actualizar_registro
    echo "Linea base lista: $(valor_dueno 'SELECT COUNT(*) FROM version_esquema') script(s) registrado(s)." ;;

aplicar)
    mostrar_plan
    [ "${#PENDIENTES[@]}" -gt 0 ] || { actualizar_registro; exit 0; }
    for f in "${PENDIENTES[@]}"; do
        echo ">> $f"
        t0=$(ahora_ms)
        ejecutar_script "$f" || { echo "ERROR en $f: Oracle reporto errores (vea $LOGS/${f%.sql}.log). Me detengo; $f NO se registro." >&2; exit 1; }
        registrar "$f" EJECUTADO $(( $(ahora_ms) - t0 ))
    done
    verificar_esquema || { echo "ERROR: el esquema quedo con objetos invalidos o triggers deshabilitados." >&2; exit 1; }
    actualizar_registro
    echo "Listo: ${#PENDIENTES[@]} script(s) aplicado(s) a $ESQUEMA." ;;
esac
