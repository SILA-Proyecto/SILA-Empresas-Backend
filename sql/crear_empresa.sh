#!/usr/bin/env bash
# Crea una EMPRESA nueva con un solo comando: esquema aislado (cuentas, roles, perfil y contexto propios), claves nuevas, directorio
# de archivos propio, datos de la empresa, modulos, primer ADMIN, configuracion de su instancia del backend y registro local.
# Modelo: una instancia del backend por empresa (mismo jar; cada una con su esquema, claves, puerto y directorio de archivos).
#
#   SYSTEM_PWD=<clave de SYSTEM> sql/crear_empresa.sh \
#       --esquema SILA_LACTEOS_EJEMPLO --nombre 'Lacteos Ejemplo SAS' --nombre-corto 'Ejemplo' \
#       --nit '900.123.456-7' --ciudad 'Villavicencio' \
#       --admin-usuario ana.admin --admin-nombre 'Ana Perez' --admin-correo ana@ejemplo.com \
#       --apagar 'CREDITO CALIDAD_LECHE' --puerto 8083
#
#   Obligatorios: --esquema --nombre --nombre-corto --admin-usuario --admin-nombre --admin-correo --puerto
#   Opcionales:   --nit --ciudad --direccion --telefono --correo-contacto   datos de la empresa
#                 --apagar 'COD COD'     modulos que nacen apagados (por defecto todos activos; ver sql/modulos.sh listar)
#                 --origen URL           origen del dashboard de ESA empresa (por defecto http://127.0.0.N:4300, el primer N libre:
#                                        cada empresa necesita su propio host por la cookie sila_refresh, que no distingue puertos)
#                 --prueba               marca la empresa como de PRUEBA (la unica que borrar_empresa_prueba.sh acepta)
#                 --datos-prueba         carga datos ficticios (sql/inicial/25_datos_prueba.sql)
#
# Valida ANTES de tocar nada: esquema valido y que no sea ni contenga LLANOLAT; que el esquema y todos sus nombres derivados no
# existan; que el puerto (8083-8999) este libre y no asignado; que el origen no se repita. Deja:
#   empresas/<ESQUEMA>/credenciales.txt   claves de la base y del backend (600)
#   empresas/<ESQUEMA>/instancia.env      puerto, origen del dashboard, directorio de archivos (600)
#   empresas/<ESQUEMA>/docs/              archivos cifrados de ESA empresa (700)
#   empresas/registro.tsv                 registro local SIN secretos (semilla del futuro panel)
# `empresas/` esta en .gitignore. Arranque: ./arrancar.sh <ESQUEMA>
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
source "$AQUI/lib_sql.sh"

uso() { sed -n '2,27p' "$0"; exit "${1:-1}"; }
ESQUEMA="" NOMBRE="" CORTO="" NIT="" CIUDAD="" DIRECCION="" TELEFONO="" CORREO_CONTACTO=""
ADMIN_USUARIO="" ADMIN_NOMBRE="" ADMIN_EMAIL="" APAGAR="" PUERTO="" ORIGEN="" PRUEBA="no" DATOS_PRUEBA=0
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || [ "$1" = "--prueba" ] || [ "$1" = "--datos-prueba" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || { echo "Falta el valor de $1" >&2; uso; }
    case "$1" in
        --esquema) ESQUEMA="$2"; shift 2 ;;
        --nombre) NOMBRE="$2"; shift 2 ;;
        --nombre-corto) CORTO="$2"; shift 2 ;;
        --nit) NIT="$2"; shift 2 ;;
        --ciudad) CIUDAD="$2"; shift 2 ;;
        --direccion) DIRECCION="$2"; shift 2 ;;
        --telefono) TELEFONO="$2"; shift 2 ;;
        --correo-contacto) CORREO_CONTACTO="$2"; shift 2 ;;
        --admin-usuario) ADMIN_USUARIO="$2"; shift 2 ;;
        --admin-nombre) ADMIN_NOMBRE="$2"; shift 2 ;;
        --admin-correo) ADMIN_EMAIL="$2"; shift 2 ;;
        --apagar) APAGAR="$2"; shift 2 ;;
        --puerto) PUERTO="$2"; shift 2 ;;
        --origen) ORIGEN="$2"; shift 2 ;;
        --prueba) PRUEBA="si"; shift ;;
        --datos-prueba) DATOS_PRUEBA=1; shift ;;
        -h|--help) uso 0 ;;
        *) echo "Opcion desconocida: $1" >&2; uso ;;
    esac
done
for v in ESQUEMA NOMBRE CORTO ADMIN_USUARIO ADMIN_NOMBRE ADMIN_EMAIL PUERTO; do
    [ -n "${!v}" ] || { echo "Falta un dato obligatorio ($v)." >&2; uso; }
done
: "${SYSTEM_PWD:?Falta SYSTEM_PWD (clave de SYSTEM)}"
fallo() { echo "RECHAZADO: $*" >&2; exit 1; }

# ================= 1. VALIDAR (nada se toca hasta pasar todo esto) =================
nombres_derivados || exit 1
conexiones
for v in NOMBRE CORTO NIT CIUDAD DIRECCION TELEFONO CORREO_CONTACTO ADMIN_NOMBRE ADMIN_EMAIL; do
    [[ "${!v}" != *$'\t'* && "${!v}" != *$'\n'* ]] || fallo "$v no puede llevar tabuladores ni saltos de linea."
done
[[ "$ADMIN_USUARIO" =~ ^[A-Za-z0-9_.@-]{3,100}$ ]] || fallo "ADMIN: el usuario admite letras, digitos y . _ @ - (3 a 100)."
[[ "$ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || fallo "ADMIN: correo invalido."
[ -z "$(registro_campo "$ESQUEMA" 1)" ] || fallo "$ESQUEMA ya esta en empresas/registro.tsv."
[ ! -e "$RAIZ_REPO/empresas/$ESQUEMA" ] || fallo "ya existe la carpeta empresas/$ESQUEMA."
EXISTE=$(valor_sys "SELECT (SELECT COUNT(*) FROM dba_users    WHERE username  IN ('$ESQUEMA','$USR_APP','$USR_REPORTES'))
     + (SELECT COUNT(*) FROM dba_roles    WHERE role      IN ('$ROL_APP','$ROL_LECTURA','$ROL_AUDITORIA'))
     + (SELECT COUNT(*) FROM dba_profiles WHERE profile   = '$PERFIL')
     + (SELECT COUNT(*) FROM dba_context  WHERE namespace = '$CTX') FROM dual")
[ "$EXISTE" = "0" ] || fallo "en la base ya existe algo con los nombres de $ESQUEMA (coincidencias: $EXISTE)."
# puerto
[[ "$PUERTO" =~ ^[0-9]+$ ]] && [ "$PUERTO" -ge 8083 ] && [ "$PUERTO" -le 8999 ] || fallo "el puerto debe estar entre 8083 y 8999 (8080/8081 son de Llanolat y 8082 de SILA_EMPRESAS)."
[ -z "$(awk -F'\t' -v p="$PUERTO" 'NR>1 && $4 == p {print $1}' "$REGISTRO" 2>/dev/null)" ] || fallo "el puerto $PUERTO ya esta asignado a otra empresa."
! ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$PUERTO\$" || fallo "el puerto $PUERTO esta ocupado en esta maquina."
# modulos a apagar: deben existir en el catalogo y no ser del nucleo (05 trae los 6 primeros; 32 agrega 3 y los saca del nucleo)
OPCIONALES="$(perl -ne "print \"\$1 \" if /^\s*SELECT '([A-Z0-9_]+)'[^']*'[^']*'[^0-9]*0\b/" "$AQUI/05_empresa_modulos.sql" "$AQUI/32_modulos_auditoria_parametros_resultado.sql")"
for m in $APAGAR; do
    case " $OPCIONALES " in *" $m "*) ;; *) fallo "modulo '$m' desconocido o del nucleo (opcionales: $OPCIONALES).";; esac
done
# origen del dashboard de esta empresa: unico
if [ -z "$ORIGEN" ]; then
    for n in $(seq 1 254); do
        cand="http://127.0.0.$n:4300"
        [ -z "$(awk -F'\t' -v o="$cand" 'NR>1 && $5 == o {print $1}' "$REGISTRO" 2>/dev/null)" ] && { ORIGEN="$cand"; break; }
    done
fi
[[ "$ORIGEN" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || fallo "origen invalido (esquema://host[:puerto], sin barra final)."
[ "$ORIGEN" != "http://localhost:4200" ] || fallo "http://localhost:4200 es el dashboard de Llanolat."
[ -z "$(awk -F'\t' -v o="$ORIGEN" 'NR>1 && $5 == o {print $1}' "$REGISTRO" 2>/dev/null)" ] || fallo "el origen $ORIGEN ya lo usa otra empresa."

# ================= 2. CREAR =================
umask 077
registro_asegurar
EMPRESA_DIR="$RAIZ_REPO/empresas/$ESQUEMA"
mkdir -p "$EMPRESA_DIR/docs" "$EMPRESA_DIR/logs"; chmod 700 "$EMPRESA_DIR" "$EMPRESA_DIR/docs" "$EMPRESA_DIR/logs"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ESQUEMA" "$NOMBRE" "$CORTO" "$PUERTO" "$ORIGEN" "$(date +%F)" "" "$PRUEBA" "creando" >> "$REGISTRO"
echo "Creando $ESQUEMA ($NOMBRE) ... (el detalle queda en empresas/$ESQUEMA/logs/despliegue.out)"
ENV_ARGS=(SYSTEM_PWD="$SYSTEM_PWD" ESQUEMA="$ESQUEMA" DESTINO="$EMPRESA_DIR" LOGS="$EMPRESA_DIR/logs"
          ADMIN_USUARIO="$ADMIN_USUARIO" ADMIN_NOMBRE="$ADMIN_NOMBRE" ADMIN_EMAIL="$ADMIN_EMAIL"
          EMPRESA_NOMBRE="$NOMBRE" EMPRESA_NOMBRE_CORTO="$CORTO" MODULOS_INACTIVOS="$APAGAR" CON_DATOS_PRUEBA="$DATOS_PRUEBA")
# los datos opcionales solo se pasan si vienen (empresa.sh deja en paz lo que no se le pasa)
[ -z "$NIT" ] || ENV_ARGS+=(EMPRESA_NIT="$NIT")
[ -z "$CIUDAD" ] || ENV_ARGS+=(EMPRESA_CIUDAD="$CIUDAD")
[ -z "$DIRECCION" ] || ENV_ARGS+=(EMPRESA_DIRECCION="$DIRECCION")
[ -z "$TELEFONO" ] || ENV_ARGS+=(EMPRESA_TELEFONO="$TELEFONO")
[ -z "$CORREO_CONTACTO" ] || ENV_ARGS+=(EMPRESA_CORREO="$CORREO_CONTACTO")
set +e
env "${ENV_ARGS[@]}" "$AQUI/desplegar_base.sh" > "$EMPRESA_DIR/logs/despliegue.out" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    registro_poner "$ESQUEMA" 9 "fallida"
    echo "FALLO la creacion de $ESQUEMA (codigo $rc). Vea empresas/$ESQUEMA/logs/despliegue.out" >&2
    tail -5 "$EMPRESA_DIR/logs/despliegue.out" >&2
    echo "La empresa quedo en el registro como 'fallida'. Si era de prueba: sql/borrar_empresa_prueba.sh $ESQUEMA" >&2
    exit "$rc"
fi

# configuracion de la instancia (sin secretos: las claves estan en credenciales.txt)
cat > "$EMPRESA_DIR/instancia.env" <<EOF
ESQUEMA=$ESQUEMA
SILA_PUERTO=$PUERTO
SILA_CORS_ORIGENES=$ORIGEN
SILA_DOCS_DIR=$EMPRESA_DIR/docs
CREDENCIALES=$EMPRESA_DIR/credenciales.txt
EOF
# Empresa en la nube: la instancia se conecta con el wallet (arrancar.sh lee SILA_DB_URL). En local no se escribe nada de esto.
if [ "$SILA_BD" = "nube" ]; then
    WALLET_DIR="$(awk -F= '$1=="WALLET"{print $2; exit}' "$NUBE_DIR/nube.env")"
    printf 'SILA_BD=nube\nSILA_DB_URL=jdbc:oracle:thin:@%s?TNS_ADMIN=%s\n' "$SERVICIO_DB" "$WALLET_DIR" >> "$EMPRESA_DIR/instancia.env"
fi
chmod 600 "$EMPRESA_DIR/instancia.env"
export ESQUEMA
VERSION=$(valor_dueno "SELECT NVL(MAX(numero), 0) FROM version_esquema")
registro_poner "$ESQUEMA" 7 "$VERSION"
registro_poner "$ESQUEMA" 9 "activa"

# ================= 3. RESUMEN (sin secretos) =================
cat <<EOF

Empresa creada: $ESQUEMA — $NOMBRE
  Version del esquema : $VERSION ($(ls "$AQUI"/[0-9][0-9]_*.sql | wc -l) scripts aplicados)
  Modulos apagados    : ${APAGAR:-ninguno}
  Puerto del backend  : $PUERTO
  Origen del dashboard: $ORIGEN   (debe abrirse con ese host exacto)
  Primer ADMIN        : $ADMIN_USUARIO  (clave temporal: SILA_ADMIN_TEMP en empresas/$ESQUEMA/credenciales.txt; al entrar debe
                        cambiarla y activar el segundo factor)
  Claves y config     : empresas/$ESQUEMA/credenciales.txt y instancia.env (permisos 600, fuera de git)
  Archivos cifrados   : empresas/$ESQUEMA/docs
  Registro            : empresas/registro.tsv
Arrancar: ./arrancar.sh $ESQUEMA        (o ./arrancar.sh $ESQUEMA jar, tras ./mvnw -DskipTests package)
EOF
