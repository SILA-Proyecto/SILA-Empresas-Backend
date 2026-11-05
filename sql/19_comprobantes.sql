-- =====================================================================
-- 19 - Comprobantes: vista unificada de los movimientos de plata (solo lectura, sin tablas nuevas)
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Reejecutable.
-- Origenes: VENTA, ABONO (un recibo agrupa los abonos de un pago), PAGO_LECHERO, COMPRA_INSUMO, GASTO.
-- numero = 'VENTA #123'. No es una factura DIAN: es el documento interno de cada movimiento.
-- sentido: INGRESO (venta, abono) o EGRESO (pago a lechero, compra de insumos, gasto).
-- fecha va sin hora (TRUNC) para que el filtro "hasta" incluya todo el dia.
-- afecta_caja: 0 solo en la venta a credito (la plata entra con los abonos).
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

CREATE OR REPLACE VIEW vw_comprobantes AS
SELECT 'VENTA' AS tipo, v.id_venta AS id_documento, 'VENTA #' || v.id_venta AS numero,
       'INGRESO' AS sentido,
       CASE WHEN v.tipo_venta = 'CONTADO' THEN 1 ELSE 0 END AS afecta_caja,
       TRUNC(v.fecha_venta) AS fecha, v.total_venta AS monto,
       v.id_cliente AS id_tercero, 'CLIENTE' AS tercero_tipo, v.cliente AS tercero,
       'Venta ' || LOWER(v.tipo_venta) AS descripcion,
       (SELECT CASE WHEN COUNT(DISTINCT p.metodo_pago) = 1 THEN MAX(p.metodo_pago)
                    WHEN COUNT(*) > 1 THEN 'VARIOS' END
          FROM vw_ventas_pagos p WHERE p.id_venta = v.id_venta) AS metodo_pago,
       CAST(NULL AS VARCHAR2(100)) AS referencia,
       CASE WHEN v.estado_pago = 'ANULADA' THEN 'ANULADO' ELSE 'VIGENTE' END AS estado,
       v.motivo_anulacion, v.id_periodo, v.usuario_registro
  FROM vw_ventas_completa v
UNION ALL
SELECT 'ABONO', r.id_recibo, 'ABONO #' || r.id_recibo, 'INGRESO', 1,
       TRUNC(r.fecha), r.monto,
       r.id_cliente, 'CLIENTE', r.cliente,
       'Abono a ' || r.ventas || ' venta(s)',
       r.metodo_pago, r.referencia_pago,
       'VIGENTE', CAST(NULL AS VARCHAR2(255)),
       (SELECT MAX(e.id_periodo) FROM vw_estado_periodos e WHERE TRUNC(r.fecha) BETWEEN e.fecha_inicio AND e.fecha_fin),
       r.usuario_registro
  FROM (SELECT a.id_recibo, MIN(a.fecha_abono) AS fecha, SUM(a.monto) AS monto, MAX(a.id_cliente) AS id_cliente,
               MAX(a.cliente) AS cliente, COUNT(*) AS ventas, MAX(a.metodo_pago) AS metodo_pago,
               MAX(a.referencia_pago) AS referencia_pago, MAX(a.usuario_registro) AS usuario_registro
          FROM vw_abonos_cartera a GROUP BY a.id_recibo) r
UNION ALL
SELECT 'PAGO_LECHERO', p.id_pago, 'PAGO_LECHERO #' || p.id_pago, 'EGRESO', 1,
       p.fecha_pago, p.monto,
       p.id_proveedor, 'PROVEEDOR', p.proveedor,
       'Pago de leche, quincena ' || p.quincena || ' / ' || p.mes || ' / ' || p.anio,
       p.metodo_pago, p.referencia_pago,
       CASE WHEN p.estado = 'ANULADO' THEN 'ANULADO' ELSE 'VIGENTE' END, p.motivo_anulacion,
       p.id_periodo, p.usuario_registro
  FROM vw_pagos_proveedor p
UNION ALL
SELECT 'COMPRA_INSUMO', c.id_compra, 'COMPRA_INSUMO #' || c.id_compra, 'EGRESO', 1,
       c.fecha, c.valor_total,
       c.id_proveedor, 'PROVEEDOR', c.proveedor,
       'Compra de ' || RTRIM(TO_CHAR(c.cantidad, 'FM99999999990.999'), '.') || ' ' || c.unidad_medida || ' de ' || c.insumo,
       CAST(NULL AS VARCHAR2(20)), c.referencia,
       CASE WHEN c.estado = 'ANULADA' THEN 'ANULADO' ELSE 'VIGENTE' END, c.motivo_anulacion,
       c.id_periodo, c.usuario_registro
  FROM vw_compras_insumo c
UNION ALL
SELECT 'GASTO', g.id_gasto, 'GASTO #' || g.id_gasto, 'EGRESO', 1,
       g.fecha_gasto, g.monto,
       CAST(NULL AS NUMBER), CAST(NULL AS VARCHAR2(10)), CAST(NULL AS VARCHAR2(100)),
       g.categoria || ': ' || g.concepto,
       CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(100)),
       g.estado, g.motivo_anulacion,
       g.id_periodo, g.usuario_registro
  FROM vw_gastos g
WITH READ ONLY
/

GRANT SELECT ON vw_comprobantes TO __ROL_APP__;
SELECT tipo, COUNT(*) AS filas FROM vw_comprobantes GROUP BY tipo;
