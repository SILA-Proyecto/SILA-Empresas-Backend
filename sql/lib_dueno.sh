# Biblioteca de los scripts del DUENO del sistema (modulos.sh, empresa.sh). Se usa con `source`, no se ejecuta.
# Entran a Oracle como DUENO del esquema por proxy (system[ESQUEMA]); la cuenta de la aplicacion NO puede hacer esto.
# Variables: SYSTEM_PWD (clave de SYSTEM) y ESQUEMA (sin valor por defecto). Opcional: CONTENEDOR (oracle-xe).
# SE NIEGA a correr si el esquema es LLANOLAT o lo nombra (lo hace nombres_derivados, de lib_sql.sh).
source "$(dirname "${BASH_SOURCE[0]}")/lib_sql.sh"

dueno_init() {
    nombres_derivados || exit 1
    conexiones
    # El esquema debe existir y ser de SILA Empresas (tener la tabla de modulos).
    local hay
    hay=$(valor_sys "SELECT COUNT(*) FROM dba_tables WHERE owner = '$ESQUEMA' AND table_name = 'MODULOS'")
    [ "$hay" = "1" ] || { echo "El esquema $ESQUEMA no existe o no tiene la tabla MODULOS (falta aplicar 05_empresa_modulos.sql con migrar.sh)." >&2; exit 1; }
}
