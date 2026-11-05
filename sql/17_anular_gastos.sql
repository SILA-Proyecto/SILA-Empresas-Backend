-- =====================================================================
-- 17 - Anulacion de gastos
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Reejecutable.
-- Un gasto no se edita ni se borra; ahora puede ANULARSE (solo ADMIN, con motivo, en quincena abierta).
-- Un gasto anulado deja de sumar en vw_gastos_por_categoria, vw_resultado_periodo y vw_cuentas_quincena.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    PROCEDURE agregar(p_col VARCHAR2, p_def VARCHAR2) IS
        v NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v FROM user_tab_columns WHERE table_name = 'GASTOS_OPERATIVOS' AND column_name = p_col;
        IF v = 0 THEN
            EXECUTE IMMEDIATE 'ALTER TABLE gastos_operativos ADD (' || p_col || ' ' || p_def || ')';
        END IF;
    END;
BEGIN
    agregar('ESTADO', 'VARCHAR2(8 CHAR) DEFAULT ''VIGENTE'' NOT NULL');
    agregar('MOTIVO_ANULACION', 'VARCHAR2(255 CHAR)');
    agregar('USUARIO_ANULACION', 'VARCHAR2(100 CHAR)');
    agregar('FECHA_ANULACION', 'TIMESTAMP');
END;
/
DECLARE
    v NUMBER;
BEGIN
    SELECT COUNT(*) INTO v FROM user_constraints WHERE constraint_name = 'CK_GASTOS_ESTADO';
    IF v = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE gastos_operativos ADD CONSTRAINT ck_gastos_estado CHECK (estado IN (''VIGENTE'', ''ANULADO'') AND (estado = ''VIGENTE'' OR motivo_anulacion IS NOT NULL))';
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_gastos_guard
BEFORE INSERT OR UPDATE OR DELETE ON gastos_operativos
FOR EACH ROW
BEGIN
    IF DELETING THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los gastos no pueden eliminarse; se anulan.');
    END IF;
    pkg_periodos.sp_validar_abierto(:NEW.id_periodo, :NEW.fecha_gasto);
    IF UPDATING THEN
        -- Solo se permite pasar de VIGENTE a ANULADO; nada mas cambia.
        IF :OLD.estado = 'ANULADO'
           OR :NEW.id_periodo <> :OLD.id_periodo OR :NEW.id_categoria <> :OLD.id_categoria
           OR :NEW.fecha_gasto <> :OLD.fecha_gasto OR :NEW.concepto <> :OLD.concepto OR :NEW.monto <> :OLD.monto THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Un gasto solo puede anularse.');
        END IF;
    END IF;
END trg_gastos_guard;
/

CREATE OR REPLACE PACKAGE pkg_finanzas AUTHID DEFINER AS
    PROCEDURE sp_crear_categoria_gasto(p_nombre IN VARCHAR2, p_id_categoria OUT NUMBER);
    PROCEDURE sp_registrar_gasto(
        p_id_categoria IN  NUMBER,
        p_concepto     IN  VARCHAR2,
        p_monto        IN  NUMBER,
        p_fecha_gasto  IN  DATE,
        p_id_gasto     OUT NUMBER
    );
    PROCEDURE sp_anular_gasto(p_id_gasto IN NUMBER, p_motivo IN VARCHAR2);
END pkg_finanzas;
/
CREATE OR REPLACE PACKAGE BODY pkg_finanzas AS

    PROCEDURE sp_crear_categoria_gasto(p_nombre IN VARCHAR2, p_id_categoria OUT NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_nombre IS NULL OR LENGTH(TRIM(p_nombre)) < 3 OR LENGTH(p_nombre) > 80 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Nombre de categoria invalido (3 a 80 caracteres).');
        END IF;
        INSERT INTO categorias_gasto (nombre) VALUES (UPPER(TRIM(p_nombre)))
        RETURNING id_categoria INTO p_id_categoria;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_categoria := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_categoria_gasto', 'nombre=' || p_nombre);
    END sp_crear_categoria_gasto;

    PROCEDURE sp_registrar_gasto(
        p_id_categoria IN  NUMBER,
        p_concepto     IN  VARCHAR2,
        p_monto        IN  NUMBER,
        p_fecha_gasto  IN  DATE,
        p_id_gasto     OUT NUMBER
    ) IS
        v_fecha   DATE := TRUNC(NVL(p_fecha_gasto, SYSDATE));
        v_activa  NUMBER;
        v_periodo NUMBER;
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_categoria IS NULL OR p_concepto IS NULL OR LENGTH(TRIM(p_concepto)) < 3 OR LENGTH(p_concepto) > 255
           OR p_monto IS NULL OR p_monto <= 0 OR p_monto <> ROUND(p_monto, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Categoria, concepto (3 a 255 caracteres) y monto positivo son obligatorios.');
        END IF;
        BEGIN
            SELECT activo INTO v_activa FROM categorias_gasto WHERE id_categoria = p_id_categoria;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La categoria no existe.');
        END;
        IF v_activa = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'La categoria esta inactiva.');
        END IF;

        v_periodo := pkg_periodos.fn_id_periodo(v_fecha);
        pkg_periodos.sp_validar_abierto(v_periodo, v_fecha);

        INSERT INTO gastos_operativos (id_periodo, id_categoria, fecha_gasto, concepto, monto, usuario_registro)
        VALUES (v_periodo, p_id_categoria, v_fecha, TRIM(p_concepto), p_monto, v_usuario)
        RETURNING id_gasto INTO p_id_gasto;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_gasto := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_gasto', 'id_categoria=' || p_id_categoria);
    END sp_registrar_gasto;

    PROCEDURE sp_anular_gasto(p_id_gasto IN NUMBER, p_motivo IN VARCHAR2) IS
        v_estado VARCHAR2(8);
        v_monto  NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_gasto IS NULL OR p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 10 OR LENGTH(p_motivo) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Gasto y motivo (10 a 255 caracteres) son obligatorios.');
        END IF;
        BEGIN
            SELECT estado, monto INTO v_estado, v_monto FROM gastos_operativos WHERE id_gasto = p_id_gasto FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El gasto no existe.');
        END;
        IF v_estado = 'ANULADO' THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'El gasto ya esta anulado.');
        END IF;
        -- El trigger trg_gastos_guard exige que la quincena del gasto este abierta.
        UPDATE gastos_operativos
           SET estado = 'ANULADO', motivo_anulacion = TRIM(p_motivo),
               usuario_anulacion = pkg_seguridad.fn_usuario_actual, fecha_anulacion = SYSTIMESTAMP
         WHERE id_gasto = p_id_gasto;
        pkg_auditoria.sp_registrar('GASTOS_OPERATIVOS', TO_CHAR(p_id_gasto), 'GASTO_ANULADO', TO_CHAR(v_monto), TRIM(p_motivo));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_anular_gasto', 'id_gasto=' || p_id_gasto);
    END sp_anular_gasto;

END pkg_finanzas;
/
SHOW ERRORS

CREATE OR REPLACE VIEW vw_gastos_por_categoria AS
SELECT p.id_periodo, p.anio, p.mes, p.quincena, c.nombre AS categoria, SUM(g.monto) AS total_gastos
  FROM gastos_operativos g
  JOIN periodos_quincena p ON p.id_periodo = g.id_periodo
  JOIN categorias_gasto c ON c.id_categoria = g.id_categoria
 WHERE g.estado = 'VIGENTE'
 GROUP BY p.id_periodo, p.anio, p.mes, p.quincena, c.nombre
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_resultado_periodo AS
SELECT p.id_periodo, p.anio, p.mes, p.quincena, p.estado,
       NVL(v.ingresos, 0)   AS ingresos_ventas,
       NVL(l.costo, 0)      AS costo_produccion,
       NVL(g.gastos, 0)     AS gastos_operativos,
       NVL(v.castigos, 0)   AS cartera_castigada,
       NVL(v.ingresos, 0) - NVL(l.costo, 0) - NVL(g.gastos, 0) - NVL(v.castigos, 0) AS resultado_estimado
  FROM periodos_quincena p
  LEFT JOIN (SELECT id_periodo, SUM(subtotal_venta) AS ingresos, SUM(monto_castigado) AS castigos
               FROM ventas
              WHERE estado_pago <> 'ANULADA'
              GROUP BY id_periodo) v ON v.id_periodo = p.id_periodo
  LEFT JOIN (SELECT q.id_periodo, SUM(lt.costo_total) AS costo
               FROM produccion_lotes lt
               JOIN periodos_quincena q ON lt.fecha_produccion BETWEEN q.fecha_inicio AND q.fecha_fin
              GROUP BY q.id_periodo) l ON l.id_periodo = p.id_periodo
  LEFT JOIN (SELECT id_periodo, SUM(monto) AS gastos
               FROM gastos_operativos
              WHERE estado = 'VIGENTE'
              GROUP BY id_periodo) g ON g.id_periodo = p.id_periodo
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_cuentas_quincena AS
SELECT p.id_periodo, p.anio, p.mes, p.quincena, p.fecha_inicio, p.fecha_fin, p.estado,
       -- Ventas
       NVL(v.ventas_sin_iva, 0)  AS ingresos_ventas,
       NVL(v.iva, 0)             AS iva_ventas,
       NVL(v.total, 0)           AS total_vendido,
       NVL(v.contado, 0)         AS ventas_contado,
       NVL(v.credito, 0)         AS ventas_credito,
       -- Cobros
       NVL(c.cobrado_contado, 0) AS cobrado_contado,
       NVL(a.abonos, 0)          AS cobrado_abonos,
       NVL(c.cobrado_contado, 0) + NVL(a.abonos, 0) AS total_cobrado,
       NVL(v.pendiente, 0)       AS cartera_pendiente,
       NVL(v.castigos, 0)        AS cartera_castigada,
       -- Leche comprada a los lecheros
       NVL(l.litros, 0)          AS leche_litros,
       NVL(l.litros_rechazados, 0) AS leche_litros_rechazados,
       NVL(l.valor, 0)           AS leche_comprada,
       NVL(l.pagado, 0)          AS leche_pagada,
       NVL(l.valor, 0) - NVL(l.pagado, 0) AS leche_por_pagar,
       NVL(pp.pagos, 0)          AS pagos_proveedores_caja,
       -- Costos y gastos
       NVL(lt.costo, 0)          AS costo_produccion,
       NVL(g.gastos, 0)          AS gastos_operativos,
       NVL(ci.compras, 0)        AS compras_insumos,
       -- Resultados
       NVL(v.ventas_sin_iva, 0) - NVL(lt.costo, 0) - NVL(g.gastos, 0) - NVL(v.castigos, 0) AS resultado_estimado,
       NVL(c.cobrado_contado, 0) + NVL(a.abonos, 0) - NVL(pp.pagos, 0) - NVL(g.gastos, 0) - NVL(ci.compras, 0) AS caja_neta
  FROM periodos_quincena p
  LEFT JOIN (SELECT id_periodo, SUM(subtotal_venta) AS ventas_sin_iva, SUM(total_iva) AS iva, SUM(total_venta) AS total,
                    SUM(CASE WHEN tipo_venta = 'CONTADO' THEN total_venta ELSE 0 END) AS contado,
                    SUM(CASE WHEN tipo_venta = 'CREDITO' THEN total_venta ELSE 0 END) AS credito,
                    SUM(saldo_pendiente) AS pendiente, SUM(monto_castigado) AS castigos
               FROM ventas WHERE estado_pago <> 'ANULADA' GROUP BY id_periodo) v ON v.id_periodo = p.id_periodo
  LEFT JOIN (SELECT vt.id_periodo, SUM(vp.monto) AS cobrado_contado
               FROM ventas_pagos vp JOIN ventas vt ON vt.id_venta = vp.id_venta
              WHERE vt.estado_pago <> 'ANULADA' GROUP BY vt.id_periodo) c ON c.id_periodo = p.id_periodo
  LEFT JOIN (SELECT q.id_periodo, SUM(ab.monto) AS abonos
               FROM abonos_cartera ab JOIN periodos_quincena q ON ab.fecha_abono BETWEEN q.fecha_inicio AND q.fecha_fin
              GROUP BY q.id_periodo) a ON a.id_periodo = p.id_periodo
  LEFT JOIN (SELECT r.id_periodo, SUM(CASE WHEN r.estado_calidad = 'APROBADO' THEN r.litros ELSE 0 END) AS litros,
                    SUM(CASE WHEN r.estado_calidad = 'RECHAZADO' THEN r.litros ELSE 0 END) AS litros_rechazados,
                    SUM(r.valor_total) AS valor,
                    (SELECT SUM(x.monto) FROM pagos_proveedor x WHERE x.id_periodo_liquidado = r.id_periodo AND x.estado = 'VIGENTE') AS pagado
               FROM recepcion_leche r GROUP BY r.id_periodo) l ON l.id_periodo = p.id_periodo
  LEFT JOIN (SELECT id_periodo, SUM(monto) AS pagos FROM pagos_proveedor WHERE estado = 'VIGENTE'
              GROUP BY id_periodo) pp ON pp.id_periodo = p.id_periodo
  LEFT JOIN (SELECT q.id_periodo, SUM(lt2.costo_total) AS costo
               FROM produccion_lotes lt2 JOIN periodos_quincena q ON lt2.fecha_produccion BETWEEN q.fecha_inicio AND q.fecha_fin
              GROUP BY q.id_periodo) lt ON lt.id_periodo = p.id_periodo
  LEFT JOIN (SELECT id_periodo, SUM(monto) AS gastos FROM gastos_operativos WHERE estado = 'VIGENTE' GROUP BY id_periodo) g ON g.id_periodo = p.id_periodo
  LEFT JOIN (SELECT id_periodo, SUM(valor_total) AS compras FROM compras_insumo WHERE estado = 'VIGENTE' GROUP BY id_periodo) ci ON ci.id_periodo = p.id_periodo
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_gastos AS
SELECT g.id_gasto, g.id_periodo, p.anio, p.mes, p.quincena, g.id_categoria, c.nombre AS categoria,
       g.fecha_gasto, g.concepto, g.monto, g.usuario_registro, g.fecha_registro,
       g.estado, g.motivo_anulacion, g.usuario_anulacion, g.fecha_anulacion
  FROM gastos_operativos g
  JOIN periodos_quincena p ON p.id_periodo = g.id_periodo
  JOIN categorias_gasto c ON c.id_categoria = g.id_categoria
WITH READ ONLY;

GRANT SELECT ON vw_gastos_por_categoria TO __ROL_APP__;
GRANT SELECT ON vw_resultado_periodo    TO __ROL_APP__;
GRANT SELECT ON vw_cuentas_quincena     TO __ROL_APP__;
GRANT SELECT ON vw_gastos               TO __ROL_APP__;

SHOW ERRORS
