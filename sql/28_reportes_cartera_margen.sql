-- ============================================================================
-- 28_reportes_cartera_margen.sql   (reejecutable; correr como system[__ESQUEMA__]; despues de 26)
--   vw_cartera_edades : lo que cada cliente debe por dias de mora (hoy en Colombia): al_dia (no vencida), mora_leve (1-15), mora_media (16-30), mora_alta (31-60), mora_critica (mas de 60).
--   vw_margen_lineas  : cada linea de venta con su costo (promedio de lo que costo producir ese producto) y su margen.
-- Solo lectura. El margen es APROXIMADO: usa el costo unitario promedio de TODOS los lotes del producto, no el del lote
-- del que salio cada unidad vendida (el sistema no guarda esa relacion).
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE VIEW vw_cartera_edades AS
SELECT c.id_cliente, c.nombre AS cliente, c.telefono,
       SUM(v.saldo_pendiente) AS saldo_total,
       COUNT(*) AS ventas_pendientes,
       SUM(CASE WHEN v.fecha_vencimiento >= TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE))
                THEN v.saldo_pendiente ELSE 0 END) AS al_dia,
       SUM(CASE WHEN TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)) - v.fecha_vencimiento BETWEEN 1 AND 15
                THEN v.saldo_pendiente ELSE 0 END) AS mora_leve,
       SUM(CASE WHEN TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)) - v.fecha_vencimiento BETWEEN 16 AND 30
                THEN v.saldo_pendiente ELSE 0 END) AS mora_media,
       SUM(CASE WHEN TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)) - v.fecha_vencimiento BETWEEN 31 AND 60
                THEN v.saldo_pendiente ELSE 0 END) AS mora_alta,
       SUM(CASE WHEN TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)) - v.fecha_vencimiento > 60
                THEN v.saldo_pendiente ELSE 0 END) AS mora_critica,
       GREATEST(0, MAX(TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)) - v.fecha_vencimiento)) AS dias_mora_max
  FROM ventas v
  JOIN clientes c ON c.id_cliente = v.id_cliente
 WHERE v.estado_pago = 'PENDIENTE'
 GROUP BY c.id_cliente, c.nombre, c.telefono
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_margen_lineas AS
SELECT d.id_detalle, v.id_venta, TRUNC(v.fecha_venta) AS fecha_venta,
       v.id_cliente, c.nombre AS cliente,
       d.id_producto, p.nombre AS producto, p.codigo_sku,
       d.cantidad, d.subtotal AS ingreso,
       k.costo_unitario,
       ROUND(d.cantidad * k.costo_unitario, 2) AS costo,
       d.subtotal - ROUND(d.cantidad * k.costo_unitario, 2) AS margen
  FROM ventas_detalle d
  JOIN ventas v ON v.id_venta = d.id_venta
  JOIN clientes c ON c.id_cliente = v.id_cliente
  JOIN productos p ON p.id_producto = d.id_producto
  LEFT JOIN (SELECT id_producto, SUM(costo_total) / SUM(cantidad_obtenida) AS costo_unitario
               FROM produccion_lotes GROUP BY id_producto) k ON k.id_producto = d.id_producto
 WHERE v.estado_pago <> 'ANULADA'
WITH READ ONLY;

GRANT SELECT ON vw_cartera_edades TO __ROL_APP__;
GRANT SELECT ON vw_margen_lineas  TO __ROL_APP__;
SHOW ERRORS
