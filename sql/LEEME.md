# Base de datos de SILA Empresas: scripts, versión y alta de empresas

Una **base (esquema) por empresa**, con el mismo código. Cada empresa tiene su esquema, sus cuentas, sus roles, su perfil y su contexto
(todos con nombres derivados del esquema), sus claves y su propia instancia del backend. Nada de esto toca `LLANOLAT`: todos los
scripts se niegan si el esquema es o contiene `LLANOLAT`.

## Qué hay aquí

| Qué | Para qué |
|---|---|
| `NN_nombre.sql` (dos dígitos) | **Migraciones**: cada cambio de la base. Se aplican en orden numérico y quedan registradas en `version_esquema`. |
| `inicial/` | Lo que **no** es migración: `01_bootstrap.sql` (objetos globales: dueño, cuentas, roles, perfil, contexto), la semilla y los datos de prueba. Solo los corre `desplegar_base.sh`, una vez. |
| `migrar.sh` | Aplica a **una** empresa lo que le falta (`--plan`, `--linea-base`). |
| `crear_empresa.sh` | Crea una empresa completa con un comando. |
| `desplegar_base.sh` | Construye el esquema (lo llama `crear_empresa.sh`; usa `migrar.sh`). |
| `modulos.sh`, `empresa.sh` | Operación del dueño: módulos activables y datos de la empresa. |
| `legal.sh` | Operación del dueño, **solo lectura**: quién aceptó los términos y la política de privacidad (`resumen`, `listar`, `pendientes`). |
| `empresa.sh suspender`, `empresa.sh reactivar` | Suspender (reversible) y reactivar una empresa. |
| `baja_empresa.sh`, `restaurar_empresa.sh` | Baja definitiva de una empresa (respaldo completo + borrado) y su reversión desde el respaldo. |
| `borrar_empresa_prueba.sh` | Limpia **solo** empresas de prueba (sin respaldo). |
| `lib_sql.sh`, `lib_dueno.sh` | Código común (nombres derivados, marcadores, ejecución). No se ejecutan. |

Los `.sql` no llevan nombres de esquema, roles ni claves: llevan **marcadores** (`__ESQUEMA__`, `__ROL_APP__`, `__CTX__`…) que los scripts
sustituyen en una copia temporal. Un marcador sin valor aborta antes de tocar la base.

## LA REGLA: cómo se agrega un cambio de base

1. **Escriba un script nuevo**, `sql/NN_descripcion.sql`, con un número **mayor** al último existente (hoy el último es 34; el siguiente, 35 o más).
2. Debe ser **reejecutable** (`CREATE OR REPLACE`, `CREATE ... IF NOT EXISTS` vía bloque con captura de errores, `MERGE`, etc.), usar los
   **marcadores** en vez de nombres fijos, y empezar con `SET DEFINE OFF`. Ejemplo de encabezado: `sql/05_empresa_modulos.sql`.
3. **Un script ya aplicado NUNCA se edita.** Si hay que corregir algo que ya se aplicó en alguna empresa, se escribe **otro** script nuevo.
   `migrar.sh` calcula el SHA-256 del archivo y, si el de un script ya aplicado cambió, **se detiene** y lo dice.
4. Pruébelo en una empresa de prueba y luego actualice las demás (abajo).

La numeración es el orden de aplicación. Por eso `05_empresa_modulos.sql` va antes que `10_` y `26_`, que lo usan. Un script pendiente con un
número **menor** al último aplicado en una empresa también detiene a `migrar.sh` (el número debe crecer).

## Usar `migrar.sh`

```bash
export SYSTEM_PWD="$(docker exec oracle-xe printenv ORACLE_PWD)"      # no se imprime ni se guarda

ESQUEMA=SILA_EMPRESAS sql/migrar.sh --plan        # solo muestra qué aplicaría («Nada pendiente.» si está al día)
ESQUEMA=SILA_EMPRESAS sql/migrar.sh               # aplica lo pendiente, en orden
```

- Se detiene en el **primer error de Oracle** y **no registra** el script que falló (se corrige y se vuelve a correr).
- Antes de aplicar compara las huellas de los ya aplicados con los archivos.
- Al final recompila el esquema y exige **0 objetos inválidos y 0 triggers deshabilitados**.
- Deja el log de cada script en `sql/salida/logs/` (fuera de git).
- Huella = SHA-256 del archivo **original** (con marcadores): es igual en todas las empresas, así se pueden comparar versiones entre ellas.
- **`--linea-base`**: para una base que ya existía antes de `version_esquema` (caso de `SILA_EMPRESAS`). Crea la tabla (script 00, lo único que ejecuta) y
  **registra** el resto como aplicado **sin ejecutarlo**. Pide escribir el nombre del esquema (o `CONFIRMO_LINEA_BASE=<ESQUEMA>` sin terminal).
  Úselo solo si la base tiene exactamente esos scripts.

### Actualizar todas las empresas

```bash
for e in $(awk -F'\t' 'NR>1 && $9=="activa" {print $1}' empresas/registro.tsv); do
    ESQUEMA=$e sql/migrar.sh --plan        # revise primero
done
for e in ...; do ESQUEMA=$e sql/migrar.sh; done      # luego aplique, empresa por empresa
```

`GET /api/v1/empresa` devuelve `version_esquema` (el último número aplicado) de cada empresa; `empresas/registro.tsv` también lo guarda.
Una instancia del backend usa el mismo jar para todas: al subir de versión el código, se reinicia cada instancia (y se migra cada base).

## Crear una empresa

```bash
export SYSTEM_PWD="$(docker exec oracle-xe printenv ORACLE_PWD)"
sql/crear_empresa.sh --esquema SILA_LACTEOS_EJEMPLO --nombre 'Lacteos Ejemplo SAS' --nombre-corto 'Ejemplo' \
    --nit '900.123.456-7' --ciudad 'Villavicencio' \
    --admin-usuario ana.admin --admin-nombre 'Ana Perez' --admin-correo ana@ejemplo.com \
    --apagar 'CREDITO CALIDAD_LECHE' --puerto 8083
./arrancar.sh SILA_LACTEOS_EJEMPLO
```

Valida **antes** de tocar nada (esquema válido y sin `LLANOLAT`; que el esquema y sus nombres derivados no existan; puerto 8083–8999 libre y no asignado;
origen del dashboard no repetido). Después genera las claves nuevas, crea el directorio de archivos propio, construye el esquema con `migrar.sh`,
siembra la empresa y los módulos, crea el primer ADMIN con clave temporal y deja todo en `empresas/<ESQUEMA>/` (fuera de git):

- `credenciales.txt` (claves de la base y del backend, 600) e `instancia.env` (puerto, origen del dashboard, directorio de archivos, 600);
- `docs/` (archivos cifrados de esa empresa, 700) y `logs/`;
- una fila en `empresas/registro.tsv` (sin secretos): esquema, nombre, puerto, origen del dashboard, fecha, versión, prueba, estado.

Cada empresa necesita **su propio origen de dashboard** (por defecto `http://127.0.0.N:4300`, el primer N libre), porque la cookie `sila_refresh` no distingue puertos.
`--prueba` la marca como de prueba (la única que `borrar_empresa_prueba.sh` acepta).

## Suspender, dar de baja y restaurar una empresa

```bash
export SYSTEM_PWD="$(docker exec oracle-xe printenv ORACLE_PWD)"
ESQUEMA=SILA_LACTEOS_EJEMPLO EMPRESA_MOTIVO='Falta de pago' sql/empresa.sh suspender
ESQUEMA=SILA_LACTEOS_EJEMPLO sql/empresa.sh reactivar
sql/baja_empresa.sh SILA_LACTEOS_EJEMPLO                                # pide escribir el esquema (o CONFIRMO_BAJA=<E>)
sql/restaurar_empresa.sh empresas/_bajas/SILA_LACTEOS_EJEMPLO_<fecha>   # pide escribir el esquema (o CONFIRMO_RESTAURAR=<E>)
```

| | Suspender | Baja |
|---|---|---|
| Qué es | Pausa reversible: no borra ni cambia datos | Borrado definitivo, **con respaldo** |
| Efecto | El backend responde `403 / 20021` a todo salvo nombre y logo del login (en < 1 min); la base no abre sesiones de aplicación (al instante) | El esquema, sus cuentas, roles, perfil y contexto desaparecen de la base; su carpeta, del disco |
| Requisito | — | Empresa **suspendida**, su backend **parado**, sin sesiones abiertas |
| Registro (`estado`) | `suspendida` / `activa` | `baja` (el puerto y el origen quedan reservados) |
| Se revierte con | `empresa.sh reactivar` | `restaurar_empresa.sh <respaldo>` (vuelve **suspendida**) |

- **Respaldo de la baja** en `empresas/_bajas/<ESQUEMA>_<fecha-hora>/` (o `SILA_BAJAS_DIR`), carpeta 700 y archivos 600, fuera de git:
  el `.dmp` de Data Pump (`expdp schemas=<E>`) y su log, `carpeta_empresa.tar.gz` (claves, `instancia.env`, archivos cifrados, logs),
  su fila del registro, `SHA256SUMS` y un `LEEME.txt`. **Lleva las claves**: sin ellas los archivos cifrados no se abren. Si el
  respaldo de la base no termina sin errores, o la copia no coincide con el original, **no se borra nada**.
- **Data Pump:** en este contenedor `DATA_PUMP_DIR` no funciona (ORA-48189), así que los scripts crean y usan el DIRECTORY
  `SILA_RESPALDOS` (`/opt/oracle/oradata/sila_respaldos`). El `.dmp` solo pasa por ahí: se copia afuera, se compara la huella y se borra.
- **Restaurar** vuelve a crear los objetos globales con `sql/inicial/01_bootstrap.sql` y las **mismas claves** de antes, importa con
  `impdp` (el único error admitido es ORA-31684: el dueño ya existe), recompila y exige 0 inválidos. Probado de ida y vuelta: mismas
  41 tablas con las mismas filas, mismos permisos y la instancia vuelve a funcionar (login, tokens, archivos). Lo que estaba en la
  papelera de reciclaje de Oracle (`BIN$...`) no viaja.
- Las empresas **de prueba** se siguen limpiando con `borrar_empresa_prueba.sh` (sin respaldo).

## Nube (Oracle Autonomous Database) o local

El mismo código y los mismos scripts sirven para el Oracle local (Docker) y para una **Autonomous Database** en Oracle Cloud. El interruptor es
`SILA_BD` (`local` por defecto, `nube`) en `lib_sql.sh`; en la nube, `ADMIN` hace el papel de `SYSTEM` (proxy `admin[ESQUEMA]`, tablespace `data`)
y el cliente SQL*Plus es la imagen de Oracle en un contenedor desechable que monta el wallet (no enciende la base local).

- **Configuración (fuera de git, `empresas/_nube/`):** `wallet/` (el zip descomprimido), `sqlnet_docker.ora` (`DIRECTORY="/wallet"`), `nube.env`
  (`ALIAS=<servicio TNS, p. ej. silaemp_tp>` y `WALLET=<ruta absoluta del wallet>`) y `credenciales.txt` con la línea `OCI_ADMIN <clave de ADMIN>`.
- **Usar la nube:** anteponga `sql/nube.sh` a cualquier script: `sql/nube.sh crear_empresa.sh --esquema SILA_NUBE ... --prueba --datos-prueba`,
  `ESQUEMA=SILA_NUBE sql/nube.sh migrar.sh`, `ESQUEMA=SILA_NUBE sql/nube.sh modulos.sh listar`. Sin `nube.sh` todo sigue yendo al Oracle local.
- **Backend:** `crear_empresa.sh` en modo nube agrega `SILA_DB_URL=jdbc:oracle:thin:@<alias>?TNS_ADMIN=<wallet>` a `instancia.env`; `arrancar.sh` la
  exporta y `application.yml` la usa (sin ella rige `localhost:1521/XEPDB1`). `./arrancar.sh SILA_NUBE jar` -> nube; `./arrancar.sh SILA_EMPRESAS jar` -> local.
- **Solo local:** `baja_empresa.sh`, `restaurar_empresa.sh` y el Data Pump (usan archivos del contenedor): se niegan con `SILA_BD=nube`.
- **Volver a local:** no hay nada que revertir; use las empresas locales sin `nube.sh`. Para quitar la nube: `sql/nube.sh borrar_empresa_prueba.sh SILA_NUBE`.
- Always Free: la ADB se apaga sola tras 7 días sin actividad (se enciende desde la consola) y se retira tras 3 meses apagada.
