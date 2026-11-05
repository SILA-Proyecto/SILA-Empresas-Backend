# SILA Empresas — Backend y base de datos

Backend de **SILA**, un sistema de gestión para empresas de productos lácteos: acopio de leche, producción y lotes, insumos y recetas, ventas, cartera, pagos a proveedores, gastos, quincenas y reportes.
El sistema es **multiempresa con una base por empresa**: cada empresa tiene su propio esquema Oracle, sus cuentas, sus roles y su propia instancia del backend, todos con el mismo código.

El dashboard (Angular) está en su propio repositorio: **SILA-Empresas-Dashboard**. El panel que crea y opera las empresas está en **SILA-Panel-Backend** y **SILA-Panel-Dashboard**.

## Qué hay aquí

| Carpeta | Contenido |
|---|---|
| `src/` | API REST con Spring Boot 4.1.1 y Java 25 (`com.llanolat.sila`), acceso a datos con JDBC y procedimientos PL/SQL. |
| `sql/` | Esquema de la base por empresa: migraciones numeradas (`NN_*.sql`), scripts de alta, migración, módulos, suspensión, baja y restauración de empresas. Ver `sql/LEEME.md`. |
| `arrancar.sh` | Arranca la instancia de una empresa con sus claves locales (que no se versionan). |

Módulos del backend (`src/main/java/com/llanolat/sila`): `acopio`, `produccion`, `insumos`, `ventas`, `cartera`, `finanzas`, `periodos`, `catalogos`, `comprobantes`, `reportes`, `tablero`, `documentos`, `archivos`, `fotos`, `legal`, `parametros`, `notificaciones`, `auditoria`, `empresa`, `asistente`, `seguridad`.

## Diseño

- **Una base por empresa**, mismo código y migraciones; la versión del esquema queda registrada y las empresas se migran de forma independiente.
- **La lógica vive en la base**: paquetes PL/SQL con `AUTHID DEFINER`; la cuenta de la aplicación solo tiene `EXECUTE` sobre paquetes y `SELECT` sobre vistas, nunca sobre tablas.
- **Módulos activables por empresa**: cada empresa enciende solo lo que usa.
- **Seguridad**: login con JWT de vida corta y sesión renovable con rotación, segundo factor TOTP, códigos de respaldo y passkeys, roles por operación, bloqueo y límites de frecuencia, auditoría de solo inserción.
- **Aceptación legal** de términos y políticas antes de usar el sistema.
- Las claves **no viven en el repositorio**: `credenciales.txt` y los datos de cada empresa están en `.gitignore`.

## Arrancar y probar

```bash
./mvnw test                         # pruebas unitarias
./arrancar.sh SILA_EMPRESAS jar     # instancia de una empresa (necesita su esquema, su instancia.env y su credenciales.txt locales)
```

Crear una empresa nueva (necesita la clave de `SYSTEM` de Oracle, que no se guarda):

```bash
SYSTEM_PWD=... sql/crear_empresa.sh --help
```

Requisitos: Java 25 y Oracle (XE local o Autonomous Database).
