-- =====================================================================
-- 09 - Vistas de lectura para Acopio y Produccion/Inventario
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Reejecutable.
--
-- Las escrituras ya existian (pkg_acopio.sp_registrar_recepcion, pkg_produccion.sp_registrar_lote y
-- sp_registrar_ajuste). Lo que faltaba era poder LISTAR cada recepcion, lote y ajuste (las vistas
-- anteriores solo traian resumenes). Los dias restantes se calculan con la fecha de Colombia
-- (America/Bogota), no con SYSDATE (UTC): a las 7 p. m. en Colombia ya es "manana" en UTC.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

CREATE OR REPLACE VIEW vw_recepciones AS
SELECT r.id_recepcion, r.id_proveedor, pr.nombre AS proveedor, r.id_periodo, r.fecha,
       r.litros, r.temperatura, r.acidez, r.estado_calidad, r.motivo_rechazo,
       r.usuario_registro, r.fecha_registro
  FROM recepcion_leche r
  JOIN proveedores pr ON pr.id_proveedor = r.id_proveedor
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_lotes AS
SELECT l.id_lote, l.codigo_lote, l.id_producto, p.nombre AS producto, p.codigo_sku, p.unidad_medida,
       l.fecha_produccion, l.litros_leche_usados, l.cantidad_obtenida,
       fn_rendimiento_pct(l.cantidad_obtenida, l.litros_leche_usados) AS porcentaje_rendimiento,
       l.costo_total, ROUND(l.costo_total / l.cantidad_obtenida, 2) AS costo_unitario,
       l.fecha_vencimiento,
       TRUNC(l.fecha_vencimiento) - TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)) AS dias_restantes,
       CASE WHEN TRUNC(l.fecha_vencimiento) - TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)) <= 7
            THEN fn_semaforo_caducidad(TRUNC(l.fecha_vencimiento)
                                     - TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)))
       END AS nivel_alerta,
       l.usuario_registro, l.fecha_registro
  FROM produccion_lotes l
  JOIN productos p ON p.id_producto = l.id_producto
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_ajustes_inventario AS
SELECT a.id_ajuste, a.id_producto, p.nombre AS producto, p.codigo_sku, p.unidad_medida,
       a.tipo_ajuste, a.cantidad_delta, a.observacion, a.usuario_registro, a.fecha_registro
  FROM ajustes_inventario a
  JOIN productos p ON p.id_producto = a.id_producto
WITH READ ONLY;

-- Solo los parametros que las pantallas necesitan mostrar (no toda la tabla).
CREATE OR REPLACE VIEW vw_umbrales_operacion AS
SELECT clave, valor_numero, descripcion
  FROM parametros_sistema
 WHERE clave IN ('TEMP_MAX_LECHE_C', 'ACIDEZ_MAX_DORNIC', 'DIAS_VIDA_UTIL_DEFAULT')
WITH READ ONLY;

GRANT SELECT ON vw_recepciones        TO __ROL_APP__;
GRANT SELECT ON vw_lotes              TO __ROL_APP__;
GRANT SELECT ON vw_ajustes_inventario TO __ROL_APP__;
GRANT SELECT ON vw_umbrales_operacion TO __ROL_APP__;

SHOW ERRORS
