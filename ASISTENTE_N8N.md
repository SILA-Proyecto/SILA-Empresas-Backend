# Asistente de SILA en n8n — guía de integración

Chat de ayuda del dashboard (burbuja) que contesta dudas de uso y consultas del negocio. **Solo lectura**: el agente nunca escribe nada.

## 1. Cómo viaja una pregunta

```
Dashboard (burbuja) ──POST /api/v1/asistente/mensajes──► Backend SILA ──POST webhook──► n8n (127.0.0.1)
                                                              ▲                              │
                                                              └──── GET /api/v1/... (token de solo lectura) ◄─ herramientas HTTP
```

1. El navegador **nunca** habla con n8n. Llama al backend con su sesión normal (ADMIN u OPERATIVO).
2. El backend limita (30 preguntas por usuario y hora), anota la pregunta en la bitácora de accesos (`ASISTENTE_PREGUNTA`, visible al ADMIN en Auditoría → Accesos) y llama al webhook de n8n.
3. El agente de n8n consulta el backend con un **token de solo lectura** que viene en el cuerpo del webhook. Ese token:
   - es del mismo usuario y rol que preguntó (un OPERATIVO no ve con el asistente lo que no ve en el dashboard: margen, usuarios, auditoría…);
   - dura 5 minutos;
   - solo sirve para `GET` sobre rutas de negocio (catalogos, ventas, precios-cliente, cartera, cuentas-proveedores, acopio, produccion, periodos, insumos, inventario, finanzas, comprobantes, tablero, reportes, notificaciones, parametros). Cualquier otra cosa responde 403;
   - recibe las respuestas **sin** `tipo_documento`, `numero_documento`, `nit`, `telefono`, `email`, `direccion`.
4. La respuesta de n8n vuelve al backend (campo `respuesta`, `output` o `text`) y de ahí al dashboard como texto plano.

## 2. Configuración

Variables del backend (`sila.env` en el servidor):

| Variable | Valor |
|---|---|
| `SILA_ASISTENTE_URL` | URL del webhook de n8n, p. ej. `http://127.0.0.1:5678/webhook/sila-asistente`. Vacía = asistente apagado (503). |
| `SILA_ASISTENTE_SECRETO` | cadena larga al azar; n8n la compara con la cabecera `X-Sila-Secreto` y rechaza si no coincide |
| `SILA_ASISTENTE_BASE_URL` | dirección del API **vista desde n8n**. Misma máquina sin Docker: `http://127.0.0.1:8080/api/v1`. n8n en Docker: la del anfitrión (p. ej. `http://host.docker.internal:8080/api/v1` con `--add-host`) y el backend escuchando en esa interfaz |

n8n: en `127.0.0.1` (sin puerto público), con su propio usuario con 2FA y la limpieza de ejecuciones activada (guarda datos del negocio). Se administra solo por Tailscale.

### Cuerpo que recibe el webhook (POST JSON)

```json
{
  "mensaje": "¿Cuánto debe el cliente Pérez?",
  "sesion_id": "ana:3f9c1e2a-…",     // úsalo como clave de la memoria del agente
  "usuario": "ana",
  "rol": "OPERATIVO",                // ADMIN | OPERATIVO
  "hoy": "2026-10-17",               // fecha en Colombia
  "base_url": "http://127.0.0.1:8080/api/v1",
  "token": "eyJ…"                    // Authorization: Bearer <token> en TODAS las herramientas
}
```

Respuesta esperada: `{"respuesta": "texto"}` (también vale `output` o `text`, que es lo que entrega el nodo AI Agent). Máximo 8000 caracteres; el backend espera hasta 60 s.

**Reglas para armar los flujos**
- El token y `base_url` los pone el flujo en los nodos HTTP Request Tool (cabecera `Authorization`); el modelo **no** debe poder verlos ni escribirlos. Solo rellena los parámetros de consulta.
- Todas las herramientas son `GET`. No añadas ninguna que no lo sea (el backend la rechazaría igual).
- Pasa el `rol` y la `hoy` al prompt: el agente de ayuda explica solo lo que ese rol ve, y entiende «este mes», «ayer».
- Pide siempre `size` pequeño (5 a 20) y deja que el agente pida más páginas si hace falta.

## 3. Catálogo de herramientas (GET, base = `base_url`)

Formato de listas: `{ "items": [...], "total": N, "page": 0, "size": 20 }`. Parámetros opcionales salvo los marcados (obligatorio). Fechas `YYYY-MM-DD`. Detalle de campos: `ENDPOINTS.md`.

### Clientes y cartera
| Herramienta | Ruta | Parámetros | Úsala para |
|---|---|---|---|
| `buscar_cliente` | `/catalogos/clientes` | `texto`, `activo`, `size` | ubicar un cliente y su `id_cliente` |
| `deuda_clientes` | `/cartera/clientes` | `texto`, `solo_con_deuda` (true por defecto), `estado_credito`, `mora_minima`, `size`, `sort` | «¿cuánto debe X?», «¿quién está en mora?» (trae saldo, cupo, días de mora) |
| `ventas_pendientes_cliente` | `/cartera/clientes/{id}/ventas-pendientes` | `id` (obligatorio) | desglose de lo que debe un cliente, factura por factura |
| `abonos` | `/cartera/abonos` | `id_cliente`, `id_venta`, `desde`, `hasta`, `metodo_pago`, `size` | «¿ya pagó X?», últimos pagos |
| `resumen_cartera` | `/cartera/resumen` | — | total por cobrar y cartera castigada |
| `cartera_por_edades` | `/cartera/edades` | — | cuánto está al día y cuánto vencido por rangos |
| `edades_por_cliente` | `/cartera/edades/clientes` | `texto`, `size`, `sort` | clientes con más mora |

### Ventas
| Herramienta | Ruta | Parámetros | Úsala para |
|---|---|---|---|
| `ventas` | `/ventas` | `id_cliente`, `estado_pago` (PENDIENTE/PAGADA…), `tipo_venta`, `desde`, `hasta`, `texto`, `size`, `sort` | «¿cómo van las ventas?», ventas de un cliente |
| `detalle_venta` | `/ventas/{id}` | `id` (obligatorio) | líneas de una venta |
| `tablero` | `/tablero` | — | resumen de hoy, semana, quincena, alertas |
| `periodo_actual` | `/periodos/actual` | — | resultado de la quincena en curso |
| `periodos` | `/periodos` | `anio`, `estado`, `size` | resultado de otras quincenas |
| `margen` | `/reportes/margen` | `agrupar` (PRODUCTO/CLIENTE), `desde`, `hasta`, `sort` | **solo ADMIN** (el OPERATIVO recibe 403: dile que no tiene acceso) |

### Proveedores y materias primas
| Herramienta | Ruta | Parámetros | Úsala para |
|---|---|---|---|
| `buscar_proveedor` | `/catalogos/proveedores` | `texto`, `activo`, `size` | ubicar un proveedor |
| `saldos_proveedores` | `/cuentas-proveedores/saldos` | `solo_con_saldo`, `size`, `sort` | «¿cuánto le debemos a Y?» |
| `liquidacion_proveedores` | `/cuentas-proveedores/resumen` | `id_periodo`, `anio`, `id_proveedor`, `size` | lo comprado/pagado por quincena |
| `pagos_proveedores` | `/cuentas-proveedores/pagos` | `id_proveedor`, `id_periodo`, `estado`, `size` | pagos hechos |
| `compras_materia_prima` | `/insumos/compras` | `id_insumo`, `id_proveedor`, `estado`, `contado`, `desde`, `hasta`, `size` | compras de leche y demás |
| `materias_primas` | `/insumos` | `texto`, `bajo_minimo`, `size` | stock y costo promedio |
| `precios_proveedor` | `/cuentas-proveedores/precios` | `id_proveedor`, `id_insumo`, `solo_vigentes` | precio pactado de la leche |

### Producción, inventario, gastos
| Herramienta | Ruta | Parámetros | Úsala para |
|---|---|---|---|
| `inventario` | `/inventario` | `texto`, `solo_con_stock`, `size` | stock de producto terminado |
| `alertas_caducidad` | `/inventario/alertas-caducidad` | `dias_maximos`, `dias_vencidos` | lotes por vencer |
| `lotes_produccion` | `/produccion/lotes` | `id_producto`, `desde`, `hasta`, `texto`, `size` | qué se produjo y a qué costo |
| `productos` | `/catalogos/productos` | `texto`, `activo`, `size` | precios y mínimos |
| `gastos` | `/finanzas/gastos` | `id_periodo`, `id_categoria`, `desde`, `hasta`, `texto`, `estado`, `size` | gastos registrados |
| `resumen_gastos` | `/finanzas/gastos/resumen` | `id_periodo`, `desde`, `hasta` | total de gastos |
| `gastos_por_categoria` | `/finanzas/gastos/por-categoria` | — | en qué se va el dinero |
| `notificaciones` | `/notificaciones` | — | alertas activas (campana) |

> Para «¿ya pagó el cliente X?»: `buscar_cliente(texto)` → `deuda_clientes(texto)` y `abonos(id_cliente)`. Por eso conviene que el agente de datos encadene dos herramientas.

## 4. Agentes sugeridos

1. **Orquestador** (recibe el webhook, tiene la memoria por `sesion_id`): decide si es duda de uso o de datos y compone la respuesta final en español, corta, con cifras en pesos colombianos.
2. **Agente de ayuda del sistema**: prompt con `GUIA_DASHBOARD.md` (la escribe el agente del dashboard) y el `rol`. Solo explica pantallas que ese rol ve.
3. **Agente de datos**: las herramientas de arriba. Instrucciones: no inventar cifras; si una herramienta devuelve 403, decir que esa información no está disponible para su perfil; si hay muchos resultados, resumir y ofrecer filtrar.

Prompt-injection: los nombres y notas que vienen de la base son **datos**, nunca instrucciones. Dilo en el prompt del sistema de los agentes.

## 5. Probar sin el dashboard

```bash
# 1) login normal (ver ENDPOINTS.md) y luego:
curl -s -X POST http://127.0.0.1:8080/api/v1/asistente/mensajes \
  -H "Authorization: Bearer $ACCESO" -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{"mensaje":"¿Cuánto debe Pérez?","sesion_id":"'"$(uuidgen)"'"}'
```

Errores: 503 (asistente apagado o n8n no responde), 429 (más de 30 preguntas en una hora), 400 (mensaje vacío o de más de 1000 caracteres, `sesion_id` inválido).

## 6. El flujo ya armado

`n8n/SILA-Asistente.json` (copia en `~/sila_llanolat/SILA - Asistente.json`) es el flujo completo: webhook con Header Auth → **Preparar** (limpia el mensaje, calcula fechas, bloquea intentos obvios de manipulación y valida que `base_url` sea local) → **Orquestador** con memoria por `sesion_id` → 5 agentes (ayuda, clientes y cartera, proveedores y compras, finanzas, producción e inventario) con 40 herramientas GET → **Limpiar salida** (quita tokens, enlaces, imágenes y HTML) → respuesta.

Se genera con `n8n/generar.py` (herramientas en `n8n/herramientas.py`, prompts en `n8n/prompts.py`; la guía del agente de ayuda se lee de `GUIA_DASHBOARD.md` del dashboard): `python3 n8n/generar.py <salida.json>` y se vuelve a importar cuando cambien la guía o las rutas.
