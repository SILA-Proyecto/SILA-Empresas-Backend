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

Siguen el contrato del dashboard (sección «Acopio de leche» y «Producción e inventario» de `docs/CONTRATO_BACKEND.md`):
`/api/v1/acopio/{recepciones,umbrales,calidad,pago-lecheros}`, `/api/v1/produccion/{lotes,ajustes}` e
`/api/v1/inventario{,/resumen,/alertas-caducidad}`. Las escrituras exigen `Idempotency-Key`.

## Respuestas de error

    { "codigo": 20003, "mensaje": "La venta excede el cupo...", "referencia": null }

| codigo | HTTP | |
|---|---|---|
| 20001, 20005 | 400 | parametro o abono invalido |
| 20008 | 403 | rol insuficiente o sin sesion |
| 20007 | 404 | no existe |
| 20002,20003,20004,20006,20009,20010,20011,20012 | 409 | conflicto de estado |
| 20999 | 500 | fallo interno; el detalle esta en log_errores |

`referencia` apunta a `log_errores.id_log` cuando la base registro el detalle.
Aparece tambien en algunos errores de negocio: cuando la base traduce un
ORA-00001 o ORA-02291 a un mensaje limpio, el nombre real de la restriccion
solo queda en esa tabla.

## Pendiente

- Modulos de escritura de ventas, cartera, facturacion, acopio, produccion,
  finanzas (gastos) y documentos.
- Spring Security + JWT, reemplazando `IdentidadDesdeCabecera`, que hoy es un
  hueco: cualquiera puede mandar `X-Rol: ADMIN`.
- Paginacion en los GET que pueden crecer (ventas, abonos, facturas).

## Cuentas con los lecheros (acopio)
| Método | Ruta | Rol | Qué hace |
|---|---|---|---|
| GET | `/api/v1/acopio/precios` | cualquiera | historial de precios por litro |
| POST | `/api/v1/acopio/precios` | ADMIN | fija el precio por litro de un lechero (rige hacia adelante) |
| GET | `/api/v1/acopio/saldos` | cualquiera | cuánto se le debe a cada lechero |
| GET | `/api/v1/acopio/pagos` | cualquiera | pagos a lecheros |
| POST | `/api/v1/acopio/pagos` | ADMIN | paga (todo o parte) la leche de una quincena |
| POST | `/api/v1/acopio/pagos/{id}/anular` | ADMIN | anula un pago con motivo |
`GET /periodos` ahora incluye las cuentas de la quincena (leche comprada/pagada/por pagar, cobros, caja neta).

## Insumos y recetas

Contrato completo en `docs/CONTRATO_BACKEND.md` del dashboard («Insumos, recetas y costo del lote»).

| Metodo | Ruta | Rol | Procedimiento |
|---|---|---|---|
| GET | `/api/v1/insumos` · `/resumen` · `/{id}` · `/compras` · `/ajustes` · `/consumos?id_lote=` | todos | vistas `vw_insumos`, `vw_compras_insumo`, `vw_ajustes_insumo`, `vw_consumos_lote` |
| POST · PUT · PATCH | `/api/v1/insumos` · `/{id}` · `/{id}/estado` | ADMIN | sp_crear_insumo / sp_actualizar_insumo / sp_cambiar_estado |
| POST | `/api/v1/insumos/compras` · `/compras/{id}/anular` | ADMIN | sp_registrar_compra / sp_anular_compra |
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
| GET | `/api/v1/tablero` | todos | resumen de inicio en un solo JSON: hoy, quincena actual, cartera, inventario, lecheros, alertas y ventas de 7 días (lee vistas existentes, sin SQL nuevo) |

## Passkeys (Face ID / huella)

| Método | Ruta | Rol | Qué hace |
|---|---|---|---|
| POST | `/api/v1/auth/passkey/opciones` · `/passkey/verificar` | token temporal `mfa` | segundo factor con passkey (Yubico webauthn-server-core; pkg_passkeys.sp_usar) |
| GET · DELETE | `/api/v1/auth/passkeys` · `/{id}` | todos | mis dispositivos (vw_passkeys) / pkg_passkeys.sp_quitar |
| POST | `/api/v1/auth/passkeys/opciones` · `/passkeys` | todos (con segundo factor activo) | registrar un dispositivo: pide el código de la app; pkg_passkeys.sp_registrar |
