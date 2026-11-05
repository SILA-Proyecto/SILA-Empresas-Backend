-- =====================================================================
-- 18 - Stock minimo de productos, notificaciones y categoria INSUMOS fuera de gastos
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Reejecutable.
--  * productos.stock_minimo (los insumos ya lo tenian) + pkg_alertas.sp_fijar_stock_minimo_producto (ADMIN)
--  * vw_productos y vw_inventario... solo se amplia vw_productos (columnas stock_minimo, bajo_minimo al final)
--  * vw_notificaciones: alertas calculadas al vuelo (no se guardan: desaparecen solas al resolverse)
--  * La categoria de gasto INSUMOS se desactiva: las compras de ingredientes y empaques van por Insumos
--    (si no, la misma compra se cuenta dos veces en la caja y en el resultado).
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    v NUMBER;
BEGIN
    SELECT COUNT(*) INTO v FROM user_tab_columns WHERE table_name = 'PRODUCTOS' AND column_name = 'STOCK_MINIMO';
    IF v = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE productos ADD (stock_minimo NUMBER(14,3) DEFAULT 0 NOT NULL)';
        EXECUTE IMMEDIATE 'ALTER TABLE productos ADD CONSTRAINT ck_productos_minimo CHECK (stock_minimo >= 0)';
    END IF;
END;
/

CREATE OR REPLACE VIEW vw_productos AS
SELECT id_producto, codigo_sku, nombre, unidad_medida, precio_base, tarifa_iva, stock_actual, activo,
       fecha_creacion, usuario_creacion, stock_minimo,
       CASE WHEN stock_minimo > 0 AND stock_actual <= stock_minimo THEN 1 ELSE 0 END AS bajo_minimo
  FROM productos
WITH READ ONLY
/

CREATE OR REPLACE PACKAGE pkg_alertas AS
    -- Rol ADMIN (igual que el stock minimo de los insumos). Queda en auditoria_cambios.
    PROCEDURE sp_fijar_stock_minimo_producto(p_id_producto IN NUMBER, p_stock_minimo IN NUMBER);
END pkg_alertas;
/

CREATE OR REPLACE PACKAGE BODY pkg_alertas AS
    PROCEDURE sp_fijar_stock_minimo_producto(p_id_producto IN NUMBER, p_stock_minimo IN NUMBER) IS
        v_anterior productos.stock_minimo%TYPE;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_stock_minimo IS NULL OR p_stock_minimo < 0 OR p_stock_minimo > 99999999 OR p_stock_minimo <> ROUND(p_stock_minimo, 3) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El stock minimo no puede ser negativo (maximo 3 decimales).');
        END IF;
        BEGIN
            SELECT stock_minimo INTO v_anterior FROM productos WHERE id_producto = p_id_producto FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe.');
        END;
        IF v_anterior <> p_stock_minimo THEN
            UPDATE productos SET stock_minimo = p_stock_minimo WHERE id_producto = p_id_producto;
            pkg_auditoria.sp_registrar('PRODUCTOS', TO_CHAR(p_id_producto), 'STOCK_MINIMO', TO_CHAR(v_anterior), TO_CHAR(p_stock_minimo));
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_fijar_stock_minimo_producto', 'id_producto=' || p_id_producto);
    END sp_fijar_stock_minimo_producto;
END pkg_alertas;
/

GRANT EXECUTE ON pkg_alertas TO __ROL_APP__;

-- Severidad: CRITICA (actuar hoy), ADVERTENCIA (actuar pronto). Ventana de "por vencer" de cartera: 3 dias; de caducidad: 7.
CREATE OR REPLACE VIEW vw_notificaciones AS
WITH hoy AS (SELECT TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)) AS d FROM dual)
-- Insumos
SELECT 'INSUMO:' || i.id_insumo AS clave,
       CASE WHEN i.stock_actual = 0 THEN 'INSUMO_AGOTADO' ELSE 'INSUMO_BAJO' END AS tipo,
       CASE WHEN i.stock_actual = 0 THEN 'CRITICA' ELSE 'ADVERTENCIA' END AS severidad,
       CASE WHEN i.stock_actual = 0 THEN 'Insumo agotado: ' ELSE 'Insumo bajo el minimo: ' END || i.nombre AS titulo,
       'Quedan ' || RTRIM(TO_CHAR(i.stock_actual, 'FM99999999990.999'), '.') || ' ' || i.unidad_medida
         || ' (minimo ' || RTRIM(TO_CHAR(i.stock_minimo, 'FM99999999990.999'), '.') || ').' AS detalle,
       'INSUMO' AS entidad, i.id_insumo AS id_entidad, CAST(NULL AS DATE) AS fecha
  FROM insumos i
 WHERE i.activo = 1 AND i.stock_minimo > 0 AND i.stock_actual <= i.stock_minimo
UNION ALL
-- Productos terminados
SELECT 'PRODUCTO:' || p.id_producto,
       CASE WHEN p.stock_actual = 0 THEN 'PRODUCTO_AGOTADO' ELSE 'PRODUCTO_BAJO' END,
       CASE WHEN p.stock_actual = 0 THEN 'CRITICA' ELSE 'ADVERTENCIA' END,
       CASE WHEN p.stock_actual = 0 THEN 'Producto agotado: ' ELSE 'Producto bajo el minimo: ' END || p.nombre,
       'Quedan ' || RTRIM(TO_CHAR(p.stock_actual, 'FM99999999990.999'), '.') || ' ' || p.unidad_medida
         || ' (minimo ' || RTRIM(TO_CHAR(p.stock_minimo, 'FM99999999990.999'), '.') || ').',
       'PRODUCTO', p.id_producto, NULL
  FROM productos p
 WHERE p.activo = 1 AND p.stock_minimo > 0 AND p.stock_actual <= p.stock_minimo
UNION ALL
-- Lotes por vencer o vencidos que aun tienen existencias del producto (el stock es por producto, no por lote)
SELECT 'LOTE:' || l.id_lote,
       CASE WHEN l.dias_restantes < 0 THEN 'LOTE_VENCIDO' ELSE 'LOTE_POR_VENCER' END,
       CASE WHEN l.dias_restantes <= 2 THEN 'CRITICA' ELSE 'ADVERTENCIA' END,
       CASE WHEN l.dias_restantes < 0 THEN 'Lote vencido: ' ELSE 'Lote por vencer: ' END || l.producto || ' (' || l.codigo_lote || ')',
       CASE WHEN l.dias_restantes < 0 THEN 'Vencio hace ' || (-l.dias_restantes) || ' dia(s).'
            WHEN l.dias_restantes = 0 THEN 'Vence hoy.'
            ELSE 'Vence en ' || l.dias_restantes || ' dia(s).' END,
       'LOTE', l.id_lote, l.fecha_vencimiento
  FROM vw_lotes l JOIN productos p ON p.id_producto = l.id_producto
 WHERE p.stock_actual > 0 AND l.dias_restantes BETWEEN -30 AND 7
UNION ALL
-- Cartera vencida, por cliente
SELECT 'CARTERA_VENCIDA:' || v.id_cliente, 'CARTERA_VENCIDA',
       CASE WHEN MAX(h.d - v.fecha_vencimiento) > 30 THEN 'CRITICA' ELSE 'ADVERTENCIA' END,
       'Cartera vencida: ' || MAX(v.cliente),
       COUNT(*) || ' venta(s) por $' || TO_CHAR(SUM(v.saldo_pendiente), 'FM999G999G999G990', 'NLS_NUMERIC_CHARACTERS='',.''')
         || ', mora maxima ' || MAX(h.d - v.fecha_vencimiento) || ' dia(s).',
       'CLIENTE', v.id_cliente, MIN(v.fecha_vencimiento)
  FROM vw_ventas_consolidadas v CROSS JOIN hoy h
 WHERE v.estado_pago = 'PENDIENTE' AND v.fecha_vencimiento < h.d
 GROUP BY v.id_cliente
UNION ALL
-- Cartera que vence en los proximos 3 dias, por cliente
SELECT 'CARTERA_POR_VENCER:' || v.id_cliente, 'CARTERA_POR_VENCER', 'ADVERTENCIA',
       'Cartera por vencer: ' || MAX(v.cliente),
       COUNT(*) || ' venta(s) por $' || TO_CHAR(SUM(v.saldo_pendiente), 'FM999G999G999G990', 'NLS_NUMERIC_CHARACTERS='',.''')
         || ' vencen entre hoy y ' || TO_CHAR(MAX(v.fecha_vencimiento), 'DD/MM/YYYY') || '.',
       'CLIENTE', v.id_cliente, MIN(v.fecha_vencimiento)
  FROM vw_ventas_consolidadas v CROSS JOIN hoy h
 WHERE v.estado_pago = 'PENDIENTE' AND v.fecha_vencimiento BETWEEN h.d AND h.d + 3
 GROUP BY v.id_cliente
UNION ALL
-- Quincena terminada y todavia abierta
SELECT 'PERIODO_SIN_CERRAR:' || e.id_periodo, 'PERIODO_SIN_CERRAR', 'ADVERTENCIA',
       'Quincena sin cerrar: ' || e.quincena || ' / ' || e.mes || ' / ' || e.anio,
       'Termino el ' || TO_CHAR(e.fecha_fin, 'DD/MM/YYYY') || ' y sigue abierta.',
       'PERIODO', e.id_periodo, e.fecha_fin
  FROM vw_estado_periodos e CROSS JOIN hoy h
 WHERE e.estado = 'ABIERTA' AND e.fecha_fin < h.d
UNION ALL
-- Leche de quincenas ya terminadas que no se ha pagado completa
SELECT 'LECHE_POR_PAGAR:' || c.id_periodo, 'LECHE_POR_PAGAR', 'ADVERTENCIA',
       'Leche por pagar: quincena ' || c.quincena || ' / ' || c.mes || ' / ' || c.anio,
       'Faltan $' || TO_CHAR(c.leche_por_pagar, 'FM999G999G999G990', 'NLS_NUMERIC_CHARACTERS='',.''') || ' a los lecheros.',
       'PERIODO', c.id_periodo, c.fecha_fin
  FROM vw_cuentas_quincena c CROSS JOIN hoy h
 WHERE c.fecha_fin < h.d AND c.leche_por_pagar > 0
UNION ALL
-- Documentos que fallaron al subir
SELECT 'DOCUMENTOS_ERROR', 'DOCUMENTOS_ERROR', 'ADVERTENCIA',
       'Documentos con error de carga',
       COUNT(*) || ' documento(s) no se pudieron subir.',
       'DOCUMENTO', CAST(NULL AS NUMBER), MIN(fecha_registro)
  FROM vw_documentos WHERE estado_carga = 'ERROR'
HAVING COUNT(*) > 0
WITH READ ONLY
/

GRANT SELECT ON vw_productos       TO __ROL_APP__;
GRANT SELECT ON vw_notificaciones  TO __ROL_APP__;

-- La categoria INSUMOS deja de aceptar gastos (la compra se registra en Insumos).
BEGIN
    pkg_seguridad.sp_iniciar_sesion('migracion.18', 'ADMIN');
    FOR c IN (SELECT id_categoria FROM vw_categorias_gasto WHERE nombre = 'INSUMOS' AND activo = 1) LOOP
        pkg_catalogos.sp_cambiar_estado('CATEGORIA_GASTO', c.id_categoria, 0);
    END LOOP;
END;
/
SELECT nombre, activo FROM vw_categorias_gasto WHERE nombre = 'INSUMOS';
SELECT COUNT(*) AS notificaciones FROM vw_notificaciones;
