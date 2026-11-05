-- =====================================================================
-- 13 - Precio de la leche por proveedor, pagos a lecheros y cuentas de la quincena
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1, DESPUES de 02 y 09-11. Reejecutable.
--
--  * precios_proveedor: precio por litro pactado con cada lechero, con fecha de vigencia.
--    PRECIO_LECHE_DEFAULT (parametro) se usa si el proveedor no tiene precio.
--  * recepcion_leche.precio_litro / valor_total: el valor QUEDA FIJO al recibir la leche (lo
--    rechazado vale 0). Las recepciones anteriores a este script se valoraron con el precio por
--    defecto (migracion unica).
--  * pagos_proveedor: lo que se le paga al lechero. Cada pago liquida una quincena y no puede
--    superar su saldo. No se borra; un ADMIN lo anula con motivo.
--  * vw_cuentas_quincena: todo el panorama contable de la quincena en una sola fila.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-955, -1430, -2260, -1408, -2261, -2264, -2275) THEN RAISE; END IF;
    END;
BEGIN
    ejecutar('
CREATE TABLE precios_proveedor (
    id_precio         NUMBER GENERATED ALWAYS AS IDENTITY,
    id_proveedor      NUMBER             NOT NULL,
    precio_litro      NUMBER(10,2)       NOT NULL,
    vigente_desde     DATE               NOT NULL,
    usuario_creacion  VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT(''__CTX__'', ''USUARIO''), SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) NOT NULL,
    fecha_creacion    TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    CONSTRAINT pk_precios_proveedor PRIMARY KEY (id_precio),
    CONSTRAINT uk_precios_proveedor UNIQUE (id_proveedor, vigente_desde),
    CONSTRAINT fk_precios_prov_proveedor FOREIGN KEY (id_proveedor) REFERENCES proveedores (id_proveedor),
    CONSTRAINT ck_precios_prov_precio CHECK (precio_litro > 0)
)');

    ejecutar('ALTER TABLE recepcion_leche ADD (precio_litro NUMBER(10,2), valor_total NUMBER(14,2))');

    ejecutar('
CREATE TABLE pagos_proveedor (
    id_pago               NUMBER GENERATED ALWAYS AS IDENTITY,
    id_proveedor          NUMBER             NOT NULL,
    id_periodo            NUMBER             NOT NULL,
    id_periodo_liquidado  NUMBER             NOT NULL,
    fecha_pago            DATE               NOT NULL,
    monto                 NUMBER(14,2)       NOT NULL,
    metodo_pago           VARCHAR2(15 CHAR)  NOT NULL,
    referencia_pago       VARCHAR2(60 CHAR),
    estado                VARCHAR2(8 CHAR)   DEFAULT ''VIGENTE'' NOT NULL,
    motivo_anulacion      VARCHAR2(255 CHAR),
    usuario_registro      VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT(''__CTX__'', ''USUARIO''), SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) NOT NULL,
    fecha_registro        TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    CONSTRAINT pk_pagos_proveedor PRIMARY KEY (id_pago),
    CONSTRAINT fk_pagos_prov_proveedor FOREIGN KEY (id_proveedor) REFERENCES proveedores (id_proveedor),
    CONSTRAINT fk_pagos_prov_periodo FOREIGN KEY (id_periodo) REFERENCES periodos_quincena (id_periodo),
    CONSTRAINT fk_pagos_prov_liquidado FOREIGN KEY (id_periodo_liquidado) REFERENCES periodos_quincena (id_periodo),
    CONSTRAINT ck_pagos_prov_monto CHECK (monto > 0),
    CONSTRAINT ck_pagos_prov_metodo CHECK (metodo_pago IN (''EFECTIVO'', ''TRANSFERENCIA'', ''CHEQUE'', ''OTRO'')),
    CONSTRAINT ck_pagos_prov_estado CHECK (estado IN (''VIGENTE'', ''ANULADO'')),
    CONSTRAINT ck_pagos_prov_motivo CHECK (estado = ''VIGENTE'' OR motivo_anulacion IS NOT NULL)
)');
    ejecutar('CREATE INDEX ix_pagos_prov_liquidado ON pagos_proveedor (id_proveedor, id_periodo_liquidado, estado)');
    ejecutar('CREATE INDEX ix_pagos_prov_periodo ON pagos_proveedor (id_periodo, estado)');
END;
/

-- Parametro: precio por litro cuando el proveedor no tiene uno propio.
MERGE INTO parametros_sistema p
USING (SELECT 'PRECIO_LECHE_DEFAULT' clave, 2000 valor,
              'Precio por litro de leche (COP) que se usa si el proveedor no tiene precio pactado' descripcion FROM dual) s
ON (p.clave = s.clave)
WHEN NOT MATCHED THEN INSERT (clave, valor_numero, descripcion) VALUES (s.clave, s.valor, s.descripcion);
UPDATE parametros_sistema SET valor_minimo = 100, valor_maximo = 20000 WHERE clave = 'PRECIO_LECHE_DEFAULT';
COMMIT;

CREATE OR REPLACE FUNCTION fn_precio_litro(p_id_proveedor IN NUMBER, p_fecha IN DATE) RETURN NUMBER IS
    v_precio NUMBER;
BEGIN
    SELECT precio_litro INTO v_precio
      FROM precios_proveedor
     WHERE id_proveedor = p_id_proveedor
       AND vigente_desde = (SELECT MAX(vigente_desde) FROM precios_proveedor
                             WHERE id_proveedor = p_id_proveedor AND vigente_desde <= TRUNC(p_fecha));
    RETURN v_precio;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN pkg_parametros.fn_numero('PRECIO_LECHE_DEFAULT');
END fn_precio_litro;
/

-- Migracion unica: las recepciones anteriores se valoran con el precio por defecto.
-- El trigger de guarda se apaga solo durante esta carga (hay quincenas cerradas).
DECLARE
    v_pend NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_pend FROM recepcion_leche WHERE precio_litro IS NULL;
    IF v_pend > 0 THEN
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_recepcion_guard DISABLE';
        BEGIN
            UPDATE recepcion_leche
               SET precio_litro = pkg_parametros.fn_numero('PRECIO_LECHE_DEFAULT'),
                   valor_total  = CASE WHEN estado_calidad = 'APROBADO'
                                       THEN ROUND(litros * pkg_parametros.fn_numero('PRECIO_LECHE_DEFAULT'), 2) ELSE 0 END
             WHERE precio_litro IS NULL;
            COMMIT;
        EXCEPTION WHEN OTHERS THEN
            EXECUTE IMMEDIATE 'ALTER TRIGGER trg_recepcion_guard ENABLE';
            RAISE;
        END;
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_recepcion_guard ENABLE';
    END IF;
END;
/
DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-1442, -1451, -2264, -2260) THEN RAISE; END IF;
    END;
BEGIN
    ejecutar('ALTER TABLE recepcion_leche MODIFY (precio_litro NOT NULL, valor_total NOT NULL)');
    ejecutar('ALTER TABLE recepcion_leche ADD CONSTRAINT ck_recepcion_valor CHECK (precio_litro >= 0 AND valor_total >= 0)');
END;
/

-- Los pagos no se editan ni se borran: solo pasan de VIGENTE a ANULADO.
CREATE OR REPLACE TRIGGER trg_pagos_prov_guard
BEFORE UPDATE OR DELETE ON pagos_proveedor
FOR EACH ROW
BEGIN
    IF DELETING THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los pagos a proveedores no pueden eliminarse; se anulan.');
    END IF;
    IF :OLD.estado = 'ANULADO'
       OR :NEW.id_proveedor <> :OLD.id_proveedor OR :NEW.id_periodo <> :OLD.id_periodo
       OR :NEW.id_periodo_liquidado <> :OLD.id_periodo_liquidado OR :NEW.fecha_pago <> :OLD.fecha_pago
       OR :NEW.monto <> :OLD.monto OR :NEW.metodo_pago <> :OLD.metodo_pago THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Un pago a proveedor solo puede anularse.');
    END IF;
END trg_pagos_prov_guard;
/

-- ============ pkg_acopio: ahora fija precio y valor al recibir ============
CREATE OR REPLACE PACKAGE pkg_acopio AUTHID DEFINER AS
    PROCEDURE sp_registrar_recepcion(
        p_id_proveedor   IN  NUMBER,
        p_litros         IN  NUMBER,
        p_temperatura    IN  NUMBER,
        p_acidez         IN  NUMBER,
        p_fecha          IN  DATE,
        p_id_recepcion   OUT NUMBER,
        p_estado_calidad OUT VARCHAR2
    );
END pkg_acopio;
/
CREATE OR REPLACE PACKAGE BODY pkg_acopio AS

    PROCEDURE sp_registrar_recepcion(
        p_id_proveedor   IN  NUMBER,
        p_litros         IN  NUMBER,
        p_temperatura    IN  NUMBER,
        p_acidez         IN  NUMBER,
        p_fecha          IN  DATE,
        p_id_recepcion   OUT NUMBER,
        p_estado_calidad OUT VARCHAR2
    ) IS
        v_fecha      DATE := TRUNC(NVL(p_fecha, SYSDATE));
        v_id_periodo NUMBER;
        v_tipo       VARCHAR2(10);
        v_activo     NUMBER;
        v_motivo     VARCHAR2(200);
        v_temp_max   NUMBER;
        v_acid_max   NUMBER;
        v_precio     NUMBER;
        v_usuario    VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_proveedor IS NULL OR p_litros IS NULL OR p_litros <= 0 OR p_litros <> ROUND(p_litros, 2)
           OR p_temperatura IS NULL OR p_acidez IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Proveedor, litros, temperatura y acidez son obligatorios (litros mayores a cero).');
        END IF;

        BEGIN
            SELECT tipo_proveedor, activo INTO v_tipo, v_activo
              FROM proveedores WHERE id_proveedor = p_id_proveedor;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El proveedor no existe.');
        END;
        IF v_tipo <> 'LECHERO' OR v_activo = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'El proveedor debe estar activo y ser de tipo LECHERO.');
        END IF;

        v_id_periodo := pkg_periodos.fn_id_periodo(v_fecha);
        pkg_periodos.sp_validar_abierto(v_id_periodo, v_fecha);

        v_temp_max := pkg_parametros.fn_numero('TEMP_MAX_LECHE_C');
        v_acid_max := pkg_parametros.fn_numero('ACIDEZ_MAX_DORNIC');
        IF p_temperatura > v_temp_max THEN
            v_motivo := 'Temperatura ' || p_temperatura || ' C supera el maximo de ' || v_temp_max || ' C';
        ELSIF p_acidez > v_acid_max THEN
            v_motivo := 'Acidez ' || p_acidez || ' supera el maximo de ' || v_acid_max;
        END IF;
        p_estado_calidad := CASE WHEN v_motivo IS NULL THEN 'APROBADO' ELSE 'RECHAZADO' END;

        -- El precio vigente el dia de la entrega queda fijo en la recepcion; la leche rechazada no se paga.
        v_precio := fn_precio_litro(p_id_proveedor, v_fecha);

        INSERT INTO recepcion_leche (id_proveedor, id_periodo, fecha, litros, temperatura, acidez,
                                     estado_calidad, motivo_rechazo, usuario_registro, precio_litro, valor_total)
        VALUES (p_id_proveedor, v_id_periodo, v_fecha, p_litros, p_temperatura, p_acidez,
                p_estado_calidad, v_motivo, v_usuario, v_precio,
                CASE WHEN p_estado_calidad = 'APROBADO' THEN ROUND(p_litros * v_precio, 2) ELSE 0 END)
        RETURNING id_recepcion INTO p_id_recepcion;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_recepcion := NULL;
            p_estado_calidad := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_recepcion', 'id_proveedor=' || p_id_proveedor);
    END sp_registrar_recepcion;

END pkg_acopio;
/

-- ============ pkg_pagos_proveedor ============
CREATE OR REPLACE PACKAGE pkg_pagos_proveedor AUTHID DEFINER AS
    -- ADMIN. Fija el precio por litro desde una fecha. Solo afecta recepciones futuras (las ya hechas conservan el suyo).
    PROCEDURE sp_fijar_precio(p_id_proveedor IN NUMBER, p_precio IN NUMBER, p_vigente_desde IN DATE);
    -- ADMIN. Paga (todo o parte) la leche de una quincena. No puede superar el saldo de esa quincena.
    PROCEDURE sp_registrar_pago(
        p_id_proveedor IN NUMBER, p_id_periodo_liquidado IN NUMBER, p_monto IN NUMBER,
        p_metodo_pago IN VARCHAR2, p_referencia IN VARCHAR2, p_fecha IN DATE, p_id_pago OUT NUMBER);
    -- ADMIN. Anula un pago (motivo obligatorio). La quincena del pago debe estar abierta.
    PROCEDURE sp_anular_pago(p_id_pago IN NUMBER, p_motivo IN VARCHAR2);
END pkg_pagos_proveedor;
/
CREATE OR REPLACE PACKAGE BODY pkg_pagos_proveedor AS

    PROCEDURE sp_fijar_precio(p_id_proveedor IN NUMBER, p_precio IN NUMBER, p_vigente_desde IN DATE) IS
        v_tipo     VARCHAR2(10);
        v_fecha    DATE := TRUNC(NVL(p_vigente_desde, SYSDATE));
        v_anterior NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_proveedor IS NULL OR p_precio IS NULL OR p_precio <= 0 OR p_precio > 20000
           OR p_precio <> ROUND(p_precio, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'El precio por litro debe ser mayor a cero, de hasta 20000 y con maximo 2 decimales.');
        END IF;
        BEGIN
            SELECT tipo_proveedor INTO v_tipo FROM proveedores WHERE id_proveedor = p_id_proveedor FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El proveedor no existe.');
        END;
        IF v_tipo <> 'LECHERO' THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'Solo los proveedores LECHERO tienen precio por litro.');
        END IF;
        BEGIN
            SELECT precio_litro INTO v_anterior FROM precios_proveedor
             WHERE id_proveedor = p_id_proveedor AND vigente_desde = v_fecha;
            UPDATE precios_proveedor SET precio_litro = p_precio
             WHERE id_proveedor = p_id_proveedor AND vigente_desde = v_fecha;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                INSERT INTO precios_proveedor (id_proveedor, precio_litro, vigente_desde)
                VALUES (p_id_proveedor, p_precio, v_fecha);
        END;
        pkg_auditoria.sp_registrar('PRECIOS_PROVEEDOR', TO_CHAR(p_id_proveedor), 'PRECIO_LITRO',
            TO_CHAR(v_anterior), p_precio || ' desde ' || TO_CHAR(v_fecha, 'YYYY-MM-DD'));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_fijar_precio', 'id_proveedor=' || p_id_proveedor);
    END sp_fijar_precio;

    PROCEDURE sp_registrar_pago(
        p_id_proveedor IN NUMBER, p_id_periodo_liquidado IN NUMBER, p_monto IN NUMBER,
        p_metodo_pago IN VARCHAR2, p_referencia IN VARCHAR2, p_fecha IN DATE, p_id_pago OUT NUMBER
    ) IS
        v_fecha     DATE := TRUNC(NVL(p_fecha, SYSDATE));
        v_id_per    NUMBER;
        v_inicio    DATE;
        v_valor     NUMBER;
        v_pagado    NUMBER;
        v_dummy     NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_proveedor IS NULL OR p_id_periodo_liquidado IS NULL OR p_monto IS NULL OR p_monto <= 0
           OR p_monto <> ROUND(p_monto, 2) OR p_metodo_pago IS NULL
           OR p_metodo_pago NOT IN ('EFECTIVO', 'TRANSFERENCIA', 'CHEQUE', 'OTRO') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Proveedor, quincena, monto (mayor a cero, 2 decimales) y medio de pago (EFECTIVO, TRANSFERENCIA, CHEQUE u OTRO) son obligatorios.');
        END IF;
        BEGIN
            SELECT id_proveedor INTO v_dummy FROM proveedores WHERE id_proveedor = p_id_proveedor FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El proveedor no existe.');
        END;
        BEGIN
            SELECT fecha_inicio INTO v_inicio FROM periodos_quincena WHERE id_periodo = p_id_periodo_liquidado;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_periodo_no_encontrado, 'La quincena a liquidar no existe.');
        END;
        IF v_inicio > v_fecha THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'No se puede pagar leche de una quincena que aun no empieza.');
        END IF;
        v_id_per := pkg_periodos.fn_id_periodo(v_fecha);
        pkg_periodos.sp_validar_abierto(v_id_per, v_fecha);

        SELECT NVL(SUM(valor_total), 0) INTO v_valor FROM recepcion_leche
         WHERE id_proveedor = p_id_proveedor AND id_periodo = p_id_periodo_liquidado;
        SELECT NVL(SUM(monto), 0) INTO v_pagado FROM pagos_proveedor
         WHERE id_proveedor = p_id_proveedor AND id_periodo_liquidado = p_id_periodo_liquidado AND estado = 'VIGENTE';
        IF p_monto > v_valor - v_pagado THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_abono_invalido,
                'El pago (' || p_monto || ') supera el saldo de esa quincena (' || (v_valor - v_pagado) || ').');
        END IF;

        INSERT INTO pagos_proveedor (id_proveedor, id_periodo, id_periodo_liquidado, fecha_pago, monto, metodo_pago, referencia_pago)
        VALUES (p_id_proveedor, v_id_per, p_id_periodo_liquidado, v_fecha, p_monto, p_metodo_pago, SUBSTR(p_referencia, 1, 60))
        RETURNING id_pago INTO p_id_pago;
        pkg_auditoria.sp_registrar('PAGOS_PROVEEDOR', TO_CHAR(p_id_pago), 'PAGO_REGISTRADO', NULL,
            'proveedor=' || p_id_proveedor || '; quincena=' || p_id_periodo_liquidado || '; monto=' || p_monto);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_pago := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_pago', 'id_proveedor=' || p_id_proveedor || ';monto=' || p_monto);
    END sp_registrar_pago;

    PROCEDURE sp_anular_pago(p_id_pago IN NUMBER, p_motivo IN VARCHAR2) IS
        v_estado  VARCHAR2(8);
        v_periodo NUMBER;
        v_fecha   DATE;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_pago IS NULL OR p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 10 OR LENGTH(p_motivo) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Pago y motivo (10 a 255 caracteres) son obligatorios.');
        END IF;
        BEGIN
            SELECT estado, id_periodo, fecha_pago INTO v_estado, v_periodo, v_fecha
              FROM pagos_proveedor WHERE id_pago = p_id_pago FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El pago no existe.');
        END;
        IF v_estado = 'ANULADO' THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'El pago ya esta anulado.');
        END IF;
        pkg_periodos.sp_validar_abierto(v_periodo, v_fecha);
        UPDATE pagos_proveedor SET estado = 'ANULADO', motivo_anulacion = TRIM(p_motivo) WHERE id_pago = p_id_pago;
        pkg_auditoria.sp_registrar('PAGOS_PROVEEDOR', TO_CHAR(p_id_pago), 'PAGO_ANULADO', 'VIGENTE', TRIM(p_motivo));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_anular_pago', 'id_pago=' || p_id_pago);
    END sp_anular_pago;

END pkg_pagos_proveedor;
/
SHOW ERRORS

-- ============ Vistas ============
CREATE OR REPLACE VIEW vw_recepciones AS
SELECT r.id_recepcion, r.id_proveedor, pr.nombre AS proveedor, r.id_periodo, r.fecha,
       r.litros, r.temperatura, r.acidez, r.estado_calidad, r.motivo_rechazo,
       r.usuario_registro, r.fecha_registro, r.precio_litro, r.valor_total
  FROM recepcion_leche r
  JOIN proveedores pr ON pr.id_proveedor = r.id_proveedor
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_precios_proveedor AS
SELECT p.id_precio, p.id_proveedor, pr.nombre AS proveedor, p.precio_litro, p.vigente_desde,
       CASE WHEN p.vigente_desde = (SELECT MAX(x.vigente_desde) FROM precios_proveedor x
                                     WHERE x.id_proveedor = p.id_proveedor AND x.vigente_desde <= TRUNC(SYSDATE))
            THEN 1 ELSE 0 END AS vigente,
       p.usuario_creacion, p.fecha_creacion
  FROM precios_proveedor p
  JOIN proveedores pr ON pr.id_proveedor = p.id_proveedor
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_pagos_proveedor AS
SELECT g.id_pago, g.id_proveedor, pr.nombre AS proveedor, g.id_periodo, g.id_periodo_liquidado,
       q.anio, q.mes, q.quincena, g.fecha_pago, g.monto, g.metodo_pago, g.referencia_pago,
       g.estado, g.motivo_anulacion, g.usuario_registro, g.fecha_registro
  FROM pagos_proveedor g
  JOIN proveedores pr ON pr.id_proveedor = g.id_proveedor
  JOIN periodos_quincena q ON q.id_periodo = g.id_periodo_liquidado
WITH READ ONLY;

-- Por quincena y lechero: lo que se compro, lo que se pago y lo que se debe.
CREATE OR REPLACE VIEW vw_resumen_pago_lecheros AS
SELECT p.id_periodo, p.anio, p.mes, p.quincena, pr.id_proveedor, pr.nombre AS proveedor,
       SUM(CASE WHEN r.estado_calidad = 'APROBADO'  THEN r.litros ELSE 0 END) AS litros_a_pagar,
       SUM(CASE WHEN r.estado_calidad = 'RECHAZADO' THEN r.litros ELSE 0 END) AS litros_rechazados,
       SUM(r.valor_total) AS valor_leche,
       NVL((SELECT SUM(g.monto) FROM pagos_proveedor g
             WHERE g.id_proveedor = pr.id_proveedor AND g.id_periodo_liquidado = p.id_periodo
               AND g.estado = 'VIGENTE'), 0) AS valor_pagado,
       SUM(r.valor_total) - NVL((SELECT SUM(g.monto) FROM pagos_proveedor g
             WHERE g.id_proveedor = pr.id_proveedor AND g.id_periodo_liquidado = p.id_periodo
               AND g.estado = 'VIGENTE'), 0) AS saldo,
       CASE WHEN SUM(CASE WHEN r.estado_calidad = 'APROBADO' THEN r.litros ELSE 0 END) = 0 THEN NULL
            ELSE ROUND(SUM(r.valor_total) / SUM(CASE WHEN r.estado_calidad = 'APROBADO' THEN r.litros ELSE 0 END), 2)
       END AS precio_promedio
  FROM recepcion_leche r
  JOIN proveedores pr ON pr.id_proveedor = r.id_proveedor
  JOIN periodos_quincena p ON p.id_periodo = r.id_periodo
 GROUP BY p.id_periodo, p.anio, p.mes, p.quincena, pr.id_proveedor, pr.nombre
WITH READ ONLY;

-- Cuanto se le debe a cada lechero en total (todas las quincenas).
CREATE OR REPLACE VIEW vw_saldo_proveedores AS
SELECT pr.id_proveedor, pr.nombre AS proveedor, pr.activo,
       fn_precio_litro(pr.id_proveedor, TRUNC(SYSDATE)) AS precio_vigente,
       NVL(c.litros, 0)   AS litros_aprobados,
       NVL(c.valor, 0)    AS total_comprado,
       NVL(g.pagado, 0)   AS total_pagado,
       NVL(c.valor, 0) - NVL(g.pagado, 0) AS saldo,
       c.ultima_entrega, g.ultimo_pago
  FROM proveedores pr
  LEFT JOIN (SELECT id_proveedor, SUM(CASE WHEN estado_calidad = 'APROBADO' THEN litros ELSE 0 END) AS litros,
                    SUM(valor_total) AS valor, MAX(fecha) AS ultima_entrega
               FROM recepcion_leche GROUP BY id_proveedor) c ON c.id_proveedor = pr.id_proveedor
  LEFT JOIN (SELECT id_proveedor, SUM(monto) AS pagado, MAX(fecha_pago) AS ultimo_pago
               FROM pagos_proveedor WHERE estado = 'VIGENTE' GROUP BY id_proveedor) g ON g.id_proveedor = pr.id_proveedor
 WHERE pr.tipo_proveedor = 'LECHERO'
WITH READ ONLY;

-- El panorama contable completo de la quincena, en una fila.
--   DEVENGADO (lo que se gano o se gasto, se haya cobrado/pagado o no): resultado_estimado
--   CAJA (plata que entro y salio de verdad en la quincena): caja_neta
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
       -- Resultados
       NVL(v.ventas_sin_iva, 0) - NVL(lt.costo, 0) - NVL(g.gastos, 0) - NVL(v.castigos, 0) AS resultado_estimado,
       NVL(c.cobrado_contado, 0) + NVL(a.abonos, 0) - NVL(pp.pagos, 0) - NVL(g.gastos, 0)  AS caja_neta
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
  LEFT JOIN (SELECT id_periodo, SUM(monto) AS gastos FROM gastos_operativos GROUP BY id_periodo) g ON g.id_periodo = p.id_periodo
WITH READ ONLY;

GRANT SELECT ON vw_recepciones         TO __ROL_APP__;
GRANT SELECT ON vw_precios_proveedor   TO __ROL_APP__;
GRANT SELECT ON vw_pagos_proveedor     TO __ROL_APP__;
GRANT SELECT ON vw_resumen_pago_lecheros TO __ROL_APP__;
GRANT SELECT ON vw_saldo_proveedores   TO __ROL_APP__;
GRANT SELECT ON vw_cuentas_quincena    TO __ROL_APP__;
GRANT EXECUTE ON pkg_acopio            TO __ROL_APP__;
GRANT EXECUTE ON pkg_pagos_proveedor   TO __ROL_APP__;
SHOW ERRORS
EXIT
