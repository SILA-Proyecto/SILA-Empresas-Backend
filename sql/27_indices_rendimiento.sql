-- ============================================================================
-- 27_indices_rendimiento.sql   (reejecutable; correr como system[__ESQUEMA__])
-- Indices por fecha y estado para los filtros y los rangos de quincena que usan las listas, el Tablero y las vistas de
-- cuentas. Con pocos datos no se nota; con meses de movimientos evitan leer las tablas completas. Despues de 26.
-- ============================================================================
SET DEFINE OFF
DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-955, -1408) THEN RAISE; END IF;   -- el indice (o uno igual) ya existe
    END;
BEGIN
    ejecutar('CREATE INDEX ix_ventas_fecha            ON ventas (fecha_venta)');
    ejecutar('CREATE INDEX ix_ventas_estado_venc      ON ventas (estado_pago, fecha_vencimiento)');
    ejecutar('CREATE INDEX ix_gastos_fecha            ON gastos_operativos (fecha_gasto)');
    ejecutar('CREATE INDEX ix_abonos_fecha            ON abonos_cartera (fecha_abono)');
    ejecutar('CREATE INDEX ix_lotes_fecha             ON produccion_lotes (fecha_produccion)');
    ejecutar('CREATE INDEX ix_compras_fecha           ON compras_insumo (fecha)');
    ejecutar('CREATE INDEX ix_pagos_prov_fecha        ON pagos_proveedor (fecha_pago)');
    ejecutar('CREATE INDEX ix_auditoria_fecha         ON auditoria_cambios (fecha)');
    ejecutar('CREATE INDEX ix_auditoria_usuario_fecha ON auditoria_cambios (usuario, fecha)');
    ejecutar('CREATE INDEX ix_documentos_carga_id     ON documentos_repositorio (estado_carga, id_documento)');
    ejecutar('CREATE INDEX ix_idempotencia_creada     ON idempotencia (creada)');
END;
/
