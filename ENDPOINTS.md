# API SILA — endpoints implementados

> Toda la API vive bajo `/api/v1`. **Catálogos (clientes, proveedores, productos)** sigue el contrato del
> dashboard: ver `~/Documentos/dashboard/dashboard-app/docs/CONTRATO_BACKEND.md` (única fuente de verdad); sus rutas
> son `/api/v1/catalogos/...`. y **Períodos** (`/api/v1/periodos`) también lo sigue. Las rutas antiguas sobre clientes/proveedores/productos **ya no existen**.
> En todo el API el JSON es `snake_case`, `activo` es booleano y los errores son `{code, message, support_ref}`.

Arrancar:

    export LLANOLAT_APP_PWD=$(awk '/^LLANOLAT_APP/{print $2}' ~/sila_llanolat/credenciales.txt)
    ./mvnw spring-boot:run

## Autenticación (modo `jwt`)

`./arrancar.sh` arranca por defecto con el login real (modo `jwt`): todo el API exige `Authorization: Bearer <token>` salvo
`/api/v1/auth/login`, `/refresh`, `/logout` y `/actuator/health`. Las cabeceras `X-Usuario`/`X-Rol` se
ignoran. Contrato completo (login con pasos, MFA, renovación, usuarios): `docs/CONTRATO_BACKEND.md`
del dashboard, secciones «Autenticación» y «Usuarios».

`./arrancar.sh desarrollo` = modo `desarrollo`: la identidad va en cabeceras `X-Usuario` y
`X-Rol: ADMIN|OPERATIVO`, **cualquiera puede ser ADMIN**. Solo por excepción explícita; el arranque se niega a usarlo con un perfil de producción.

| Método | Ruta | Acceso | Qué hace |
|---|---|---|---|
| POST | `/api/v1/auth/login` | público | usuario + clave → `AuthResponse` (estado y token) |
| POST | `/api/v1/auth/cambiar-clave` | temporal / acceso | cambia la clave (pide la actual; con sesión abierta también el código MFA) |
| POST | `/api/v1/auth/mfa/configurar` · `/activar` | temporal / acceso | alta del segundo factor TOTP |
| POST | `/api/v1/auth/mfa/verificar` | temporal | código TOTP → entra |
| POST | `/api/v1/auth/refresh` · `/logout` | cookie | renueva (rota) / cierra la sesión |
| GET | `/api/v1/auth/yo` | acceso | datos de la sesión |
| PUT | `/api/v1/auth/yo` | acceso | edita mi nombre y correo (exige código MFA) |
| GET/POST/PUT/PATCH | `/api/v1/usuarios…` | ADMIN | administración de usuarios |

## Lectura — GET sobre las vistas

Ninguno exige rol: las vistas estan otorgadas a `rol_sila_app` y no verifican
rol. Las cifras calculadas (dias de mora, valor del inventario, rendimiento,
resultado del periodo) las resuelve la vista, no el backend.

| Metodo | Ruta | Parametros | Vista |
|---|---|---|---|
| GET | `/api/v1/ventas` | `idCliente`, `estadoPago`, `desde`, `hasta` | vw_ventas_consolidadas |
| GET | `/api/v1/ventas/{id}/detalle` | | vw_detalle_ticket_venta |
| GET | `/api/v1/cartera` | `soloConDeuda`, `moraMinima` | vw_dashboard_cartera |
| GET | `/api/v1/cartera/abonos` | `idCliente`, `idVenta`, `idRecibo` | vw_abonos_cartera |
| GET | `/api/v1/facturas` | `estadoDian`, `idVenta` | vw_facturas |
| GET | `/api/v1/facturacion/resoluciones` | `soloActivas` | vw_resoluciones_facturacion |
| GET | `/api/v1/finanzas/categorias` | `soloActivas` | vw_categorias_gasto |
| GET | `/api/v1/finanzas/gastos/por-categoria` | `idPeriodo` | vw_gastos_por_categoria |
| GET | `/api/v1/documentos/pendientes` | `estado` | vw_documentos_pendientes_carga |

Las busquedas `?q=` son insensibles a mayusculas, tildes y enes: `?q=ordeno`
encuentra "Ordeño", `?q=dona` encuentra "Doña".

## Escritura — por packages, nunca DML directo

| Metodo | Ruta | Rol | Procedimiento |
|---|---|---|---|
| POST | `/api/v1/periodos/anio/{anio}` | ADMIN | sp_crear_periodos_anio |
| PATCH | `/api/v1/periodos/{id}/estado` | ADMIN | sp_cerrar_periodo / sp_reabrir_periodo (exige motivo) |
| POST | `/api/v1/finanzas/categorias` | ADMIN | sp_crear_categoria_gasto |
| DELETE | `/api/v1/finanzas/categorias/{id}` | ADMIN | sp_cambiar_estado |

**Ningun DELETE borra.** Todos desactivan (`activo = 0`) y el historial queda
intacto. Las ventas, facturas y abonos no tienen DELETE ni siquiera asi: se
anulan con su propio procedimiento.

## Acopio, producción e inventario

Siguen el contrato del dashboard (sección «Producción e inventario» del contrato del dashboard):
`/api/v1/acopio/{umbrales,calidad}` (solo lectura; la entrega de leche es una compra de la materia prima LECHE, ver «Materias primas»), `/api/v1/produccion/{lotes,ajustes}` e
`/api/v1/inventario{,/resumen,/alertas-caducidad}`. Las escrituras exigen `Idempotency-Key`.

## Respuestas de error

    { "code": 20003, "message": "La venta excede el cupo...", "support_ref": "123", "fields": { "campo": "motivo" } }

`support_ref` y `fields` aparecen solo cuando aplican. `support_ref` apunta a `log_errores.id_log` cuando la base
registró el detalle (por ejemplo, cuando traduce un ORA-00001 o ORA-02291 a un mensaje limpio, el nombre real de la
restricción solo queda en esa tabla). Un valor que no cabe en la columna (ORA-12899 / ORA-01438) responde 400 / 20001.

| code | HTTP | |
|---|---|---|
| 20001, 20005 | 400 | parámetro o abono inválido |
| 20013 | 401 | sin sesión o sesión vencida |
| 20008 | 403 | rol insuficiente |
| 20007 | 404 | no existe |
| 20002, 20003, 20004, 20006, 20009, 20010, 20011, 20012, 20016 | 409 | conflicto de estado |
| 20017, 20018 | 422 | dato no admitido (20018 también 413: archivo demasiado grande) |
| 20014 | 423 | cuenta bloqueada |
| 20015 | 429 | demasiados intentos |
| 20019 | 503 | servicio no disponible (antivirus) |
| 20999 | 500 | fallo interno; el detalle está en log_errores |

## Rutas

La lista completa y vigente de rutas, campos y reglas por rol está en el contrato del dashboard:
`~/Documentos/dashboard/dashboard-app/docs/CONTRATO_BACKEND.md` (la sección nueva al inicio prevalece). Esta tabla solo
resume lo esencial; no la uses para saber qué existe.

## Cuentas con los proveedores (`/api/v1/cuentas-proveedores`)
Se paga por quincena, a TODOS los proveedores, lo comprado a crédito (las compras de contado y la leche rechazada no suman). Escrituras: ADMIN + `Idempotency-Key`.
| Método | Ruta | Rol | Qué hace |
|---|---|---|---|
| GET | `/api/v1/cuentas-proveedores/precios` | cualquiera | precios pactados por proveedor + materia prima (filtros `id_proveedor`, `id_insumo`, `solo_vigentes`) |
| POST | `/api/v1/cuentas-proveedores/precios` | ADMIN | fija el precio pactado (referencia; rige hacia adelante) |
| GET | `/api/v1/cuentas-proveedores/saldos` | cualquiera | cuánto se le debe a cada proveedor (compras a crédito − pagos) |
| GET | `/api/v1/cuentas-proveedores/resumen` | cualquiera | por quincena y proveedor: compras a crédito, pagado, saldo |
| GET | `/api/v1/cuentas-proveedores/pagos` | cualquiera | pagos a proveedores |
| POST | `/api/v1/cuentas-proveedores/pagos` | ADMIN | paga (todo o parte) lo comprado a crédito en una quincena |
| POST | `/api/v1/cuentas-proveedores/pagos/{id}/anular` | ADMIN | anula un pago con motivo |
`GET /periodos` incluye las cuentas de la quincena (compras de contado/crédito, pagado y por pagar a proveedores, cobros, caja neta).

## Materias primas (insumos y leche) y recetas

La LECHE es la materia prima con control de calidad (`requiere_calidad`). Una sola entrada para todo: `POST /insumos/compras`.

Contrato completo en `docs/CONTRATO_BACKEND.md` del dashboard («Insumos, recetas y costo del lote»).

| Metodo | Ruta | Rol | Procedimiento |
|---|---|---|---|
| GET | `/api/v1/insumos` · `/resumen` · `/{id}` · `/compras` · `/ajustes` · `/consumos?id_lote=` | todos | vistas `vw_insumos`, `vw_compras_insumo`, `vw_ajustes_insumo`, `vw_consumos_lote` |
| POST · PUT · PATCH | `/api/v1/insumos` · `/{id}` · `/{id}/estado` | ADMIN | sp_crear_insumo / sp_actualizar_insumo / sp_cambiar_estado |
| POST | `/api/v1/insumos/compras` | OPERATIVO si es la LECHE (con temperatura y acidez; rechazada = 201 con estado_calidad RECHAZADO), ADMIN para las demás | sp_registrar_compra: proveedor opcional, `valor_total` opcional (precio pactado), `contado`, `comprado_en` |
| POST | `/api/v1/insumos/compras/{id}/anular` | ADMIN | sp_anular_compra (409 si ya se gastó o si la quincena quedaría pagada de más) |
| POST | `/api/v1/insumos/ajustes` | OPERATIVO (restas) / ADMIN (correcciones) | sp_registrar_ajuste |
| GET · PUT | `/api/v1/catalogos/productos/{id}/receta` | todos · ADMIN | `vw_recetas` / sp_definir_receta |

## Gastos y documentos
Contrato en el dashboard (`docs/CONTRATO_BACKEND.md`, «Gastos operativos y documentos»).
| Método | Ruta | Rol | Qué hace |
|---|---|---|---|
| GET | `/api/v1/finanzas/gastos`, `/resumen`, `/{id}` | todos | lista paginada (vw_gastos), total filtrado y detalle |
| POST | `/api/v1/finanzas/gastos` | OPERATIVO | pkg_finanzas.sp_registrar_gasto; Idempotency-Key obligatoria |
| GET | `/api/v1/documentos`, `/{id}` | todos | lista paginada (vw_documentos) |
| POST | `/api/v1/finanzas/gastos/{id}/anular` | ADMIN | pkg_finanzas.sp_anular_gasto (motivo 10+) |
| POST | `/api/v1/documentos` | OPERATIVO | encola un documento PENDIENTE (pkg_documentos) |
| POST | `/api/v1/documentos/{id}/subido` · `/error` | OPERATIVO | reporta el resultado de la subida a Drive |

## Tablero

| Método | Ruta | Rol | Qué hace |
|---|---|---|---|
| GET | `/api/v1/tablero` | todos | resumen de inicio en un solo JSON: hoy, quincena actual, cartera, inventario, proveedores, alertas y ventas de 7 días (lee vistas existentes, sin SQL nuevo) |

## Passkeys (Face ID / huella)

| Método | Ruta | Rol | Qué hace |
|---|---|---|---|
| POST | `/api/v1/auth/passkey/opciones` · `/passkey/verificar` | token temporal `mfa` | segundo factor con passkey (Yubico webauthn-server-core; pkg_passkeys.sp_usar) |
| GET · DELETE | `/api/v1/auth/passkeys` · `/{id}` | todos | mis dispositivos (vw_passkeys) / pkg_passkeys.sp_quitar. **DELETE pide el código del segundo factor** en el cuerpo `{codigo}` (6 dígitos o respaldo): 400 sin código, 401 si es malo |
| POST | `/api/v1/auth/passkeys/opciones` · `/passkeys` | todos (con segundo factor activo) | registrar un dispositivo: pide el código de la app; pkg_passkeys.sp_registrar |

## Archivos (PDF de comprobantes, archivos del ADMIN, carpetas, Drive)
Contrato en el dashboard (`docs/CONTRATO_BACKEND.md`, «Archivos»). SQL: `~/sila_llanolat/22_archivos.sql` (`pkg_archivos`, `carpetas_archivos`, `accesos_documentos`, vistas `vw_archivos*`). Código: `com.llanolat.sila.archivos`. **Sin Idempotency-Key** en estas rutas. Archivos cifrados AES-256-GCM en `SILA_DOCS_DIR`; copia cifrada en Drive; ClamAV antes de aceptar una subida (falla cerrado).

| Método | Ruta | Rol | Qué hace |
|---|---|---|---|
| GET | `/api/v1/archivos` | todos | lista paginada plana (vw_archivos): `origen`, `tipo`, `version`, `archivado`, `estado_drive`, `id_carpeta`, `texto`, `desde`, `hasta` |
| GET | `/api/v1/archivos/explorador` | todos | carpetas virtuales (TIPO, CLIENTE, PROVEEDOR; vw_archivos_ubicaciones) y manuales (MANUAL): `arbol` + `ruta` repetida |
| GET | `/api/v1/archivos/comprobante/{tipo}/{id}` | todos | los PDF de un comprobante (`[]`, original, original + anulado) |
| GET | `/api/v1/archivos/{id}` · `/opciones-descarga` | todos | detalle · qué claves admite (documento de identidad, escrita, aleatoria) |
| GET | `/api/v1/archivos/{id}/contenido` | todos | ver el archivo (bitácora VER) |
| POST | `/api/v1/archivos/{id}/descarga` | todos | copia PDF protegida con clave (AES-256); clave aleatoria en `X-Clave-Generada` (bitácora DESCARGAR + tipo de clave) |
| POST | `/api/v1/archivos/descifrar` | todos | multipart `archivo`: descifra un `.sila` bajado de Drive («Ver documento») |
| GET | `/api/v1/archivos/carpetas` | todos | carpetas manuales hijas de `id_padre` |
| POST | `/api/v1/archivos` | ADMIN | multipart `archivo` + `id_carpeta`: tipo real, ≤ 10 MB, ClamAV, revisión de PDF / re-codificado de imagen, cifrado; pkg_archivos.sp_registrar_subida |
| POST | `/api/v1/archivos/{id}/archivar` | ADMIN | pkg_archivos.sp_archivar_documento (motivo 5–255); nunca borra; no aplica a comprobantes |
| POST | `/api/v1/archivos/carpetas` · `/carpetas/{id}/archivar` | ADMIN | pkg_archivos.sp_crear_carpeta / sp_archivar_carpeta |
| GET | `/api/v1/archivos/accesos` | ADMIN | bitácora de accesos (vw_accesos_documentos) |
| GET | `/api/v1/archivos/drive/estado` · `/autorizar` | ADMIN | estado de la copia en Drive · URL de Google para conectar (OAuth `drive.file`) |
| GET | `/api/v1/archivos/drive/callback` | público (state firmado, un solo uso) | vuelta de Google; redirige a `SILA_DRIVE_RETORNO?drive=ok\|error` |
| POST | `/api/v1/archivos/drive/sincronizar` · `/desconectar` | ADMIN | envía lo pendiente ahora · borra el acceso guardado |

Los PDF de comprobantes NO tienen endpoint de escritura: `ComprobanteArchivos` los genera dentro de la propia petición de registro/anulación de VENTA, ABONO, PAGO_PROVEEDOR, COMPRA y GASTO (si falla, el movimiento ya está guardado y un reintento cada 2 min lo repone, con espera creciente si vuelve a fallar; desde `SILA_DOCS_FECHA_CORTE` o, si está vacía, desde el movimiento más antiguo que ya tiene PDF o desde el día de arranque). Errores nuevos: `20018` (422 contenido no admitido / 413 tamaño) y `20019` (503 antivirus o Drive no disponibles).

## Reportes (agregado 2026-10-17)
| Método | Ruta | Rol | Qué |
|---|---|---|---|
| GET | `/api/v1/cartera/edades` | todos | cartera pendiente por días de mora (al día, 1-15, 16-30, 31-60, más de 60): total y clientes por rango |
| GET | `/api/v1/cartera/edades/clientes` | todos | lo mismo por cliente (paginado; `sort`: cliente, saldo_total, dias_mora_max, mora_*) |
| GET | `/api/v1/reportes/margen` | ADMIN | margen por `agrupar=PRODUCTO\|CLIENTE` entre `desde` y `hasta` (por defecto el mes en curso); costo = promedio de los lotes del producto (aproximado) |

Detalle de campos en `~/Documentos/dashboard/dashboard-app/docs/PROMPT_REPORTES.md`.
