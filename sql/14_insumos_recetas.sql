-- =====================================================================
-- 14 - Insumos (azucar, envases...), recetas por producto, compras con stock y consumo por lote
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1, DESPUES de 02 y 09-13. Reejecutable.
--
--  * insumos: catalogo con stock y COSTO PROMEDIO PONDERADO (se recalcula en cada compra).
--  * recetas_producto: cuanto de cada insumo gasta UNA unidad del producto (en la unidad del insumo).
--  * compras_insumo: entradas de stock con su valor. Se anulan (ADMIN, con motivo); no se borran.
--  * ajustes_insumo: mermas, danos, vencimientos y correcciones.
--  * consumos_insumo: lo que gasto cada lote, con el costo CONGELADO al producirlo.
--  * pkg_produccion.sp_registrar_lote ahora descuenta los insumos de la receta (error si falta
--    stock) y suma su costo al del lote: costo_total = leche + insumos.
--  * vw_cuentas_quincena: columna nueva compras_insumos, que tambien resta de la caja.
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
CREATE TABLE insumos (
    id_insumo         NUMBER GENERATED ALWAYS AS IDENTITY,
    codigo            VARCHAR2(20 CHAR)  NOT NULL,
    nombre            VARCHAR2(100 CHAR) NOT NULL,
    unidad_medida     VARCHAR2(10 CHAR)  NOT NULL,
    costo_promedio    NUMBER(14,4)       DEFAULT 0 NOT NULL,
    stock_actual      NUMBER(14,3)       DEFAULT 0 NOT NULL,
    stock_minimo      NUMBER(14,3)       DEFAULT 0 NOT NULL,
    activo            NUMBER(1)          DEFAULT 1 NOT NULL,
    fecha_creacion    TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    usuario_creacion  VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT(''__CTX__'', ''USUARIO''), SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) NOT NULL,
    CONSTRAINT pk_insumos PRIMARY KEY (id_insumo),
    CONSTRAINT uk_insumos_codigo UNIQUE (codigo),
    CONSTRAINT ck_insumos_codigo CHECK (codigo = UPPER(codigo)),
    CONSTRAINT ck_insumos_unidad CHECK (unidad_medida IN (''KG'', ''GR'', ''LT'', ''ML'', ''UND'', ''PAQ'')),
    CONSTRAINT ck_insumos_costo CHECK (costo_promedio >= 0),
    CONSTRAINT ck_insumos_stock CHECK (stock_actual >= 0),
    CONSTRAINT ck_insumos_minimo CHECK (stock_minimo >= 0),
    CONSTRAINT ck_insumos_activo CHECK (activo IN (0, 1))
)');

    ejecutar('
CREATE TABLE recetas_producto (
    id_producto         NUMBER         NOT NULL,
    id_insumo           NUMBER         NOT NULL,
    cantidad_por_unidad NUMBER(14,4)   NOT NULL,
    CONSTRAINT pk_recetas_producto PRIMARY KEY (id_producto, id_insumo),
    CONSTRAINT fk_recetas_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto),
    CONSTRAINT fk_recetas_insumo FOREIGN KEY (id_insumo) REFERENCES insumos (id_insumo),
    CONSTRAINT ck_recetas_cantidad CHECK (cantidad_por_unidad > 0)
)');
    ejecutar('CREATE INDEX ix_recetas_insumo ON recetas_producto (id_insumo)');

    ejecutar('
CREATE TABLE compras_insumo (
    id_compra         NUMBER GENERATED ALWAYS AS IDENTITY,
    id_insumo         NUMBER             NOT NULL,
    id_proveedor      NUMBER,
    id_periodo        NUMBER             NOT NULL,
    fecha             DATE               NOT NULL,
    cantidad          NUMBER(14,3)       NOT NULL,
    valor_total       NUMBER(14,2)       NOT NULL,
    costo_unitario    NUMBER(14,4)       NOT NULL,
    referencia        VARCHAR2(60 CHAR),
    estado            VARCHAR2(8 CHAR)   DEFAULT ''VIGENTE'' NOT NULL,
    motivo_anulacion  VARCHAR2(255 CHAR),
    usuario_registro  VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT(''__CTX__'', ''USUARIO''), SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) NOT NULL,
    fecha_registro    TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    CONSTRAINT pk_compras_insumo PRIMARY KEY (id_compra),
    CONSTRAINT fk_compras_ins_insumo FOREIGN KEY (id_insumo) REFERENCES insumos (id_insumo),
    CONSTRAINT fk_compras_ins_proveedor FOREIGN KEY (id_proveedor) REFERENCES proveedores (id_proveedor),
    CONSTRAINT fk_compras_ins_periodo FOREIGN KEY (id_periodo) REFERENCES periodos_quincena (id_periodo),
    CONSTRAINT ck_compras_ins_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_compras_ins_valor CHECK (valor_total > 0),
    CONSTRAINT ck_compras_ins_estado CHECK (estado IN (''VIGENTE'', ''ANULADA'')),
    CONSTRAINT ck_compras_ins_motivo CHECK (estado = ''VIGENTE'' OR motivo_anulacion IS NOT NULL)
)');
    ejecutar('CREATE INDEX ix_compras_ins_insumo ON compras_insumo (id_insumo, fecha)');
    ejecutar('CREATE INDEX ix_compras_ins_periodo ON compras_insumo (id_periodo, estado)');

    ejecutar('
CREATE TABLE ajustes_insumo (
    id_ajuste         NUMBER GENERATED ALWAYS AS IDENTITY,
    id_insumo         NUMBER             NOT NULL,
    tipo_ajuste       VARCHAR2(20 CHAR)  NOT NULL,
    cantidad_delta    NUMBER(14,3)       NOT NULL,
    valor_delta       NUMBER(14,2)       NOT NULL,
    observacion       VARCHAR2(255 CHAR) NOT NULL,
    usuario_registro  VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT(''__CTX__'', ''USUARIO''), SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) NOT NULL,
    fecha_registro    TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    CONSTRAINT pk_ajustes_insumo PRIMARY KEY (id_ajuste),
    CONSTRAINT fk_ajustes_ins_insumo FOREIGN KEY (id_insumo) REFERENCES insumos (id_insumo),
    CONSTRAINT ck_ajustes_ins_tipo CHECK (tipo_ajuste IN (''MERMA'', ''DANO'', ''VENCIMIENTO'', ''CORRECCION_MAS'', ''CORRECCION_MENOS'')),
    CONSTRAINT ck_ajustes_ins_delta CHECK (cantidad_delta <> 0)
)');
    ejecutar('CREATE INDEX ix_ajustes_ins_insumo ON ajustes_insumo (id_insumo, fecha_registro)');

    ejecutar('
CREATE TABLE consumos_insumo (
    id_consumo        NUMBER GENERATED ALWAYS AS IDENTITY,
    id_lote           NUMBER             NOT NULL,
    id_insumo         NUMBER             NOT NULL,
    cantidad          NUMBER(14,3)       NOT NULL,
    costo_unitario    NUMBER(14,4)       NOT NULL,
    valor             NUMBER(14,2)       NOT NULL,
    CONSTRAINT pk_consumos_insumo PRIMARY KEY (id_consumo),
    CONSTRAINT uk_consumos_lote_insumo UNIQUE (id_lote, id_insumo),
    CONSTRAINT fk_consumos_lote FOREIGN KEY (id_lote) REFERENCES produccion_lotes (id_lote),
    CONSTRAINT fk_consumos_insumo FOREIGN KEY (id_insumo) REFERENCES insumos (id_insumo),
    CONSTRAINT ck_consumos_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_consumos_valor CHECK (valor >= 0)
)');
    ejecutar('CREATE INDEX ix_consumos_insumo ON consumos_insumo (id_insumo)');

    -- Costo de los insumos dentro del costo del lote (costo_total = leche + insumos). Lotes anteriores: 0.
    ejecutar('ALTER TABLE produccion_lotes ADD (costo_insumos NUMBER(12,2) DEFAULT 0 NOT NULL)');
    ejecutar('ALTER TABLE produccion_lotes ADD CONSTRAINT ck_lotes_costo_insumos CHECK (costo_insumos >= 0 AND costo_insumos <= costo_total)');
END;
/

-- ============ Triggers ============
CREATE OR REPLACE TRIGGER trg_insumos_nodelete
BEFORE DELETE ON insumos
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los insumos no pueden eliminarse; se desactivan.');
END trg_insumos_nodelete;
/
CREATE OR REPLACE TRIGGER trg_aud_insumos
AFTER UPDATE OF nombre, unidad_medida, stock_minimo, activo ON insumos
FOR EACH ROW
BEGIN
    IF :OLD.nombre <> :NEW.nombre THEN
        pkg_auditoria.sp_registrar('INSUMOS', TO_CHAR(:NEW.id_insumo), 'NOMBRE', :OLD.nombre, :NEW.nombre);
    END IF;
    IF :OLD.unidad_medida <> :NEW.unidad_medida THEN
        pkg_auditoria.sp_registrar('INSUMOS', TO_CHAR(:NEW.id_insumo), 'UNIDAD_MEDIDA', :OLD.unidad_medida, :NEW.unidad_medida);
    END IF;
    IF :OLD.stock_minimo <> :NEW.stock_minimo THEN
        pkg_auditoria.sp_registrar('INSUMOS', TO_CHAR(:NEW.id_insumo), 'STOCK_MINIMO', TO_CHAR(:OLD.stock_minimo), TO_CHAR(:NEW.stock_minimo));
    END IF;
    IF :OLD.activo <> :NEW.activo THEN
        pkg_auditoria.sp_registrar('INSUMOS', TO_CHAR(:NEW.id_insumo), 'ACTIVO', TO_CHAR(:OLD.activo), TO_CHAR(:NEW.activo));
    END IF;
END trg_aud_insumos;
/
-- Una compra solo puede pasar de VIGENTE a ANULADA.
CREATE OR REPLACE TRIGGER trg_compras_ins_guard
BEFORE UPDATE OR DELETE ON compras_insumo
FOR EACH ROW
BEGIN
    IF DELETING THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Las compras de insumos no pueden eliminarse; se anulan.');
    END IF;
    IF :OLD.estado = 'ANULADA'
       OR :NEW.id_insumo <> :OLD.id_insumo OR :NEW.id_periodo <> :OLD.id_periodo OR :NEW.fecha <> :OLD.fecha
       OR :NEW.cantidad <> :OLD.cantidad OR :NEW.valor_total <> :OLD.valor_total
       OR :NEW.costo_unitario <> :OLD.costo_unitario THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Una compra de insumos solo puede anularse.');
    END IF;
END trg_compras_ins_guard;
/
CREATE OR REPLACE TRIGGER trg_ro_ajustes_insumo
BEFORE UPDATE OR DELETE ON ajustes_insumo
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los ajustes de insumos son de solo insercion.');
END trg_ro_ajustes_insumo;
/
CREATE OR REPLACE TRIGGER trg_ro_consumos_insumo
BEFORE UPDATE OR DELETE ON consumos_insumo
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los consumos de insumos son de solo insercion.');
END trg_ro_consumos_insumo;
/

-- ============ pkg_insumos ============
CREATE OR REPLACE PACKAGE pkg_insumos AUTHID DEFINER AS
    -- ADMIN. El costo promedio y el stock nacen en cero: se llenan con compras.
    PROCEDURE sp_crear_insumo(
        p_codigo IN VARCHAR2, p_nombre IN VARCHAR2, p_unidad_medida IN VARCHAR2,
        p_stock_minimo IN NUMBER, p_id_insumo OUT NUMBER);
    -- ADMIN. La unidad solo cambia si el insumo no tiene movimientos ni esta en recetas.
    PROCEDURE sp_actualizar_insumo(
        p_id_insumo IN NUMBER, p_nombre IN VARCHAR2, p_unidad_medida IN VARCHAR2, p_stock_minimo IN NUMBER);
    -- ADMIN. No se desactiva un insumo que esta en la receta de un producto activo.
    PROCEDURE sp_cambiar_estado(p_id_insumo IN NUMBER, p_activo IN NUMBER);
    -- ADMIN. Entra stock y se recalcula el costo promedio ponderado. p_id_proveedor es opcional (tipo INSUMOS).
    PROCEDURE sp_registrar_compra(
        p_id_insumo IN NUMBER, p_id_proveedor IN NUMBER, p_cantidad IN NUMBER, p_valor_total IN NUMBER,
        p_referencia IN VARCHAR2, p_fecha IN DATE, p_id_compra OUT NUMBER);
    -- ADMIN. Revierte el stock y el costo; solo si el stock alcanza para devolver lo comprado.
    PROCEDURE sp_anular_compra(p_id_compra IN NUMBER, p_motivo IN VARCHAR2);
    -- MERMA, DANO, VENCIMIENTO: OPERATIVO. CORRECCION_MAS y CORRECCION_MENOS: ADMIN. p_cantidad siempre positiva.
    PROCEDURE sp_registrar_ajuste(
        p_id_insumo IN NUMBER, p_tipo_ajuste IN VARCHAR2, p_cantidad IN NUMBER,
        p_observacion IN VARCHAR2, p_id_ajuste OUT NUMBER);
    -- ADMIN. Reemplaza la receta completa del producto. p_lineas_json: [{"id_insumo":1,"cantidad":0.25}, ...]. [] la deja vacia.
    PROCEDURE sp_definir_receta(p_id_producto IN NUMBER, p_lineas_json IN CLOB);
END pkg_insumos;
/
CREATE OR REPLACE PACKAGE BODY pkg_insumos AS

    c_max_lineas CONSTANT PLS_INTEGER := 30;

    PROCEDURE sp_crear_insumo(
        p_codigo IN VARCHAR2, p_nombre IN VARCHAR2, p_unidad_medida IN VARCHAR2,
        p_stock_minimo IN NUMBER, p_id_insumo OUT NUMBER
    ) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_codigo IS NULL OR NOT REGEXP_LIKE(p_codigo, '^[A-Z0-9-]{3,20}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'El codigo debe tener de 3 a 20 caracteres: letras mayusculas, numeros o guion.');
        END IF;
        IF p_nombre IS NULL OR LENGTH(TRIM(p_nombre)) < 2 OR LENGTH(p_nombre) > 100 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El nombre es obligatorio (2 a 100 caracteres).');
        END IF;
        IF p_unidad_medida IS NULL OR p_unidad_medida NOT IN ('KG', 'GR', 'LT', 'ML', 'UND', 'PAQ') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Unidad de medida invalida.');
        END IF;
        IF p_stock_minimo IS NULL OR p_stock_minimo < 0 OR p_stock_minimo <> ROUND(p_stock_minimo, 3) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El stock minimo no puede ser negativo (maximo 3 decimales).');
        END IF;
        INSERT INTO insumos (codigo, nombre, unidad_medida, stock_minimo)
        VALUES (p_codigo, TRIM(p_nombre), p_unidad_medida, p_stock_minimo)
        RETURNING id_insumo INTO p_id_insumo;
        pkg_auditoria.sp_registrar('INSUMOS', TO_CHAR(p_id_insumo), 'CREADO', NULL, p_codigo || ' - ' || TRIM(p_nombre));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_insumo := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_insumo', 'codigo=' || p_codigo);
    END sp_crear_insumo;

    PROCEDURE sp_actualizar_insumo(
        p_id_insumo IN NUMBER, p_nombre IN VARCHAR2, p_unidad_medida IN VARCHAR2, p_stock_minimo IN NUMBER
    ) IS
        v_unidad insumos.unidad_medida%TYPE;
        v_n      NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_nombre IS NULL OR LENGTH(TRIM(p_nombre)) < 2 OR LENGTH(p_nombre) > 100 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El nombre es obligatorio (2 a 100 caracteres).');
        END IF;
        IF p_unidad_medida IS NULL OR p_unidad_medida NOT IN ('KG', 'GR', 'LT', 'ML', 'UND', 'PAQ') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Unidad de medida invalida.');
        END IF;
        IF p_stock_minimo IS NULL OR p_stock_minimo < 0 OR p_stock_minimo <> ROUND(p_stock_minimo, 3) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El stock minimo no puede ser negativo (maximo 3 decimales).');
        END IF;
        BEGIN
            SELECT unidad_medida INTO v_unidad FROM insumos WHERE id_insumo = p_id_insumo FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El insumo no existe.');
        END;
        IF v_unidad <> p_unidad_medida THEN
            SELECT (SELECT COUNT(*) FROM compras_insumo WHERE id_insumo = p_id_insumo)
                 + (SELECT COUNT(*) FROM ajustes_insumo WHERE id_insumo = p_id_insumo)
                 + (SELECT COUNT(*) FROM consumos_insumo WHERE id_insumo = p_id_insumo)
                 + (SELECT COUNT(*) FROM recetas_producto WHERE id_insumo = p_id_insumo)
              INTO v_n FROM dual;
            IF v_n > 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                    'La unidad no puede cambiar: el insumo ya tiene movimientos o esta en recetas.');
            END IF;
        END IF;
        UPDATE insumos SET nombre = TRIM(p_nombre), unidad_medida = p_unidad_medida, stock_minimo = p_stock_minimo
         WHERE id_insumo = p_id_insumo;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_insumo', 'id_insumo=' || p_id_insumo);
    END sp_actualizar_insumo;

    PROCEDURE sp_cambiar_estado(p_id_insumo IN NUMBER, p_activo IN NUMBER) IS
        v_activo NUMBER;
        v_n      NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_activo IS NULL OR p_activo NOT IN (0, 1) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El estado debe ser 0 o 1.');
        END IF;
        BEGIN
            SELECT activo INTO v_activo FROM insumos WHERE id_insumo = p_id_insumo FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El insumo no existe.');
        END;
        IF p_activo = 0 AND v_activo = 1 THEN
            SELECT COUNT(*) INTO v_n FROM recetas_producto r JOIN productos p ON p.id_producto = r.id_producto
             WHERE r.id_insumo = p_id_insumo AND p.activo = 1;
            IF v_n > 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                    'El insumo esta en la receta de ' || v_n || ' producto(s) activo(s); quitelo de las recetas antes de desactivarlo.');
            END IF;
        END IF;
        UPDATE insumos SET activo = p_activo WHERE id_insumo = p_id_insumo;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_cambiar_estado', 'id_insumo=' || p_id_insumo);
    END sp_cambiar_estado;

    PROCEDURE sp_registrar_compra(
        p_id_insumo IN NUMBER, p_id_proveedor IN NUMBER, p_cantidad IN NUMBER, p_valor_total IN NUMBER,
        p_referencia IN VARCHAR2, p_fecha IN DATE, p_id_compra OUT NUMBER
    ) IS
        v_fecha   DATE := TRUNC(NVL(p_fecha, SYSDATE));
        v_periodo NUMBER;
        v_activo  NUMBER;
        v_stock   NUMBER;
        v_costo   NUMBER;
        v_tipo    VARCHAR2(10);
        v_prov_ok NUMBER;
        v_unitario NUMBER;
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_insumo IS NULL OR p_cantidad IS NULL OR p_cantidad <= 0 OR p_cantidad <> ROUND(p_cantidad, 3)
           OR p_valor_total IS NULL OR p_valor_total <= 0 OR p_valor_total <> ROUND(p_valor_total, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Insumo, cantidad (hasta 3 decimales) y valor total (2 decimales) son obligatorios y mayores a cero.');
        END IF;
        v_periodo := pkg_periodos.fn_id_periodo(v_fecha);
        pkg_periodos.sp_validar_abierto(v_periodo, v_fecha);

        IF p_id_proveedor IS NOT NULL THEN
            BEGIN
                SELECT tipo_proveedor, activo INTO v_tipo, v_prov_ok FROM proveedores WHERE id_proveedor = p_id_proveedor;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El proveedor no existe.');
            END;
            IF v_tipo <> 'INSUMOS' OR v_prov_ok = 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                    'El proveedor debe estar activo y ser de tipo INSUMOS.');
            END IF;
        END IF;

        BEGIN
            SELECT activo, stock_actual, costo_promedio INTO v_activo, v_stock, v_costo
              FROM insumos WHERE id_insumo = p_id_insumo FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El insumo no existe.');
        END;
        IF v_activo = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'El insumo esta inactivo.');
        END IF;

        v_unitario := ROUND(p_valor_total / p_cantidad, 4);
        INSERT INTO compras_insumo (id_insumo, id_proveedor, id_periodo, fecha, cantidad, valor_total,
                                    costo_unitario, referencia, usuario_registro)
        VALUES (p_id_insumo, p_id_proveedor, v_periodo, v_fecha, p_cantidad, p_valor_total,
                v_unitario, SUBSTR(TRIM(p_referencia), 1, 60), v_usuario)
        RETURNING id_compra INTO p_id_compra;

        -- Costo promedio ponderado: (valor que habia + valor que entra) / (stock que habia + stock que entra).
        UPDATE insumos
           SET stock_actual   = v_stock + p_cantidad,
               costo_promedio = ROUND((v_stock * v_costo + p_valor_total) / (v_stock + p_cantidad), 4)
         WHERE id_insumo = p_id_insumo;
        pkg_auditoria.sp_registrar('COMPRAS_INSUMO', TO_CHAR(p_id_compra), 'COMPRA_REGISTRADA', NULL,
            'insumo=' || p_id_insumo || '; cantidad=' || p_cantidad || '; valor=' || p_valor_total);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_compra := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_compra', 'id_insumo=' || p_id_insumo);
    END sp_registrar_compra;

    PROCEDURE sp_anular_compra(p_id_compra IN NUMBER, p_motivo IN VARCHAR2) IS
        v_estado   compras_insumo.estado%TYPE;
        v_insumo   NUMBER;
        v_periodo  NUMBER;
        v_fecha    DATE;
        v_cantidad NUMBER;
        v_valor    NUMBER;
        v_stock    NUMBER;
        v_costo    NUMBER;
        v_nuevo    NUMBER;
        v_valor_inv NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_compra IS NULL OR p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 10 OR LENGTH(p_motivo) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Compra y motivo (10 a 255 caracteres) son obligatorios.');
        END IF;
        BEGIN
            SELECT estado, id_insumo, id_periodo, fecha, cantidad, valor_total
              INTO v_estado, v_insumo, v_periodo, v_fecha, v_cantidad, v_valor
              FROM compras_insumo WHERE id_compra = p_id_compra;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La compra no existe.');
        END;
        -- Se bloquea el insumo y se relee la compra: dos anulaciones simultaneas no deben restar dos veces.
        SELECT stock_actual, costo_promedio INTO v_stock, v_costo FROM insumos WHERE id_insumo = v_insumo FOR UPDATE WAIT 10;
        SELECT estado INTO v_estado FROM compras_insumo WHERE id_compra = p_id_compra FOR UPDATE;
        IF v_estado = 'ANULADA' THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La compra ya esta anulada.');
        END IF;
        pkg_periodos.sp_validar_abierto(v_periodo, v_fecha);
        IF v_stock < v_cantidad THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_stock_insuficiente,
                'No se puede anular: ya se gasto parte de lo comprado (stock actual ' || v_stock || ', compra ' || v_cantidad || '). Use un ajuste.');
        END IF;

        v_nuevo := v_stock - v_cantidad;
        v_valor_inv := v_stock * v_costo - v_valor;
        UPDATE insumos
           SET stock_actual   = v_nuevo,
               costo_promedio = CASE WHEN v_nuevo > 0 AND v_valor_inv > 0 THEN ROUND(v_valor_inv / v_nuevo, 4) ELSE costo_promedio END
         WHERE id_insumo = v_insumo;
        UPDATE compras_insumo SET estado = 'ANULADA', motivo_anulacion = TRIM(p_motivo) WHERE id_compra = p_id_compra;
        pkg_auditoria.sp_registrar('COMPRAS_INSUMO', TO_CHAR(p_id_compra), 'COMPRA_ANULADA', 'VIGENTE', TRIM(p_motivo));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_anular_compra', 'id_compra=' || p_id_compra);
    END sp_anular_compra;

    PROCEDURE sp_registrar_ajuste(
        p_id_insumo IN NUMBER, p_tipo_ajuste IN VARCHAR2, p_cantidad IN NUMBER,
        p_observacion IN VARCHAR2, p_id_ajuste OUT NUMBER
    ) IS
        v_stock   NUMBER;
        v_costo   NUMBER;
        v_delta   NUMBER;
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_tipo_ajuste IS NULL OR p_tipo_ajuste NOT IN ('MERMA', 'DANO', 'VENCIMIENTO', 'CORRECCION_MAS', 'CORRECCION_MENOS') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Tipo de ajuste invalido.');
        END IF;
        IF p_id_insumo IS NULL OR p_cantidad IS NULL OR p_cantidad <= 0 OR p_cantidad <> ROUND(p_cantidad, 3) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Insumo y cantidad (mayor a cero, 3 decimales) son obligatorios.');
        END IF;
        IF p_observacion IS NULL OR LENGTH(TRIM(p_observacion)) < 5 OR LENGTH(p_observacion) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La observacion es obligatoria (5 a 255 caracteres).');
        END IF;
        IF p_tipo_ajuste IN ('CORRECCION_MAS', 'CORRECCION_MENOS') THEN
            pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        END IF;
        v_delta := CASE WHEN p_tipo_ajuste = 'CORRECCION_MAS' THEN p_cantidad ELSE -p_cantidad END;

        BEGIN
            SELECT stock_actual, costo_promedio INTO v_stock, v_costo
              FROM insumos WHERE id_insumo = p_id_insumo FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El insumo no existe.');
        END;
        IF v_stock + v_delta < 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_stock_insuficiente,
                'El ajuste dejaria el stock negativo (stock actual ' || v_stock || ').');
        END IF;
        -- El ajuste mueve unidades al costo promedio vigente: no cambia el costo promedio.
        UPDATE insumos SET stock_actual = stock_actual + v_delta WHERE id_insumo = p_id_insumo;
        INSERT INTO ajustes_insumo (id_insumo, tipo_ajuste, cantidad_delta, valor_delta, observacion, usuario_registro)
        VALUES (p_id_insumo, p_tipo_ajuste, v_delta, ROUND(v_delta * v_costo, 2), TRIM(p_observacion), v_usuario)
        RETURNING id_ajuste INTO p_id_ajuste;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_ajuste := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_ajuste', 'id_insumo=' || p_id_insumo || ';tipo=' || p_tipo_ajuste);
    END sp_registrar_ajuste;

    PROCEDURE sp_definir_receta(p_id_producto IN NUMBER, p_lineas_json IN CLOB) IS
        v_dummy   NUMBER;
        v_total   NUMBER;
        v_distint NUMBER;
        v_validas NUMBER;
        v_antes   VARCHAR2(4000);
        v_despues VARCHAR2(4000);
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_producto IS NULL OR p_lineas_json IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Producto y lineas de receta son obligatorios.');
        END IF;
        BEGIN
            SELECT id_producto INTO v_dummy FROM productos WHERE id_producto = p_id_producto FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe.');
        END;

        BEGIN
            SELECT COUNT(*), COUNT(DISTINCT id_insumo),
                   SUM(CASE WHEN id_insumo IS NOT NULL AND cantidad > 0 AND cantidad = ROUND(cantidad, 4) AND cantidad <= 100000 THEN 1 ELSE 0 END)
              INTO v_total, v_distint, v_validas
              FROM JSON_TABLE(p_lineas_json, '$[*]' COLUMNS (id_insumo NUMBER PATH '$.id_insumo', cantidad NUMBER PATH '$.cantidad'));
        EXCEPTION
            WHEN OTHERS THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Las lineas de la receta no son un JSON valido.');
        END;
        IF v_total > c_max_lineas THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Una receta admite como maximo ' || c_max_lineas || ' insumos.');
        END IF;
        IF v_total <> v_distint THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Un insumo no puede repetirse en la receta.');
        END IF;
        IF NVL(v_validas, 0) <> v_total THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Cada linea necesita insumo y una cantidad mayor a cero con hasta 4 decimales.');
        END IF;

        -- Todos los insumos deben existir y estar activos.
        SELECT COUNT(*) INTO v_dummy
          FROM JSON_TABLE(p_lineas_json, '$[*]' COLUMNS (id_insumo NUMBER PATH '$.id_insumo')) j
         WHERE NOT EXISTS (SELECT 1 FROM insumos i WHERE i.id_insumo = j.id_insumo AND i.activo = 1);
        IF v_dummy > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'Hay insumos que no existen o estan inactivos.');
        END IF;

        SELECT LISTAGG(i.codigo || '=' || TO_CHAR(r.cantidad_por_unidad), '; ') WITHIN GROUP (ORDER BY i.codigo)
          INTO v_antes
          FROM recetas_producto r JOIN insumos i ON i.id_insumo = r.id_insumo
         WHERE r.id_producto = p_id_producto;

        DELETE FROM recetas_producto WHERE id_producto = p_id_producto;
        INSERT INTO recetas_producto (id_producto, id_insumo, cantidad_por_unidad)
        SELECT p_id_producto, id_insumo, cantidad
          FROM JSON_TABLE(p_lineas_json, '$[*]' COLUMNS (id_insumo NUMBER PATH '$.id_insumo', cantidad NUMBER PATH '$.cantidad'));

        SELECT LISTAGG(i.codigo || '=' || TO_CHAR(r.cantidad_por_unidad), '; ') WITHIN GROUP (ORDER BY i.codigo)
          INTO v_despues
          FROM recetas_producto r JOIN insumos i ON i.id_insumo = r.id_insumo
         WHERE r.id_producto = p_id_producto;
        pkg_auditoria.sp_registrar('RECETAS_PRODUCTO', TO_CHAR(p_id_producto), 'RECETA', SUBSTR(v_antes, 1, 1000), SUBSTR(v_despues, 1, 1000));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_definir_receta', 'id_producto=' || p_id_producto);
    END sp_definir_receta;

END pkg_insumos;
/
SHOW ERRORS

-- ============ pkg_produccion: el lote descuenta los insumos de la receta ============
CREATE OR REPLACE PACKAGE pkg_produccion AUTHID DEFINER AS
    PROCEDURE sp_registrar_lote(
        p_id_producto       IN  NUMBER,
        p_litros_usados     IN  NUMBER,
        p_cantidad_obtenida IN  NUMBER,
        p_costo_por_litro   IN  NUMBER,
        p_fecha_produccion  IN  DATE,
        p_fecha_vencimiento IN  DATE,
        p_id_lote           OUT NUMBER,
        p_codigo_lote       OUT VARCHAR2
    );

    -- p_tipo_ajuste: MERMA, DANO, VENCIMIENTO, MUESTRA (restan); INGRESO_INICIAL, CORRECCION_MAS (suman);
    -- CORRECCION_MENOS (resta). p_cantidad es siempre positiva.
    PROCEDURE sp_registrar_ajuste(
        p_id_producto IN  NUMBER,
        p_tipo_ajuste IN  VARCHAR2,
        p_cantidad    IN  NUMBER,
        p_observacion IN  VARCHAR2,
        p_id_ajuste   OUT NUMBER
    );
END pkg_produccion;
/
CREATE OR REPLACE PACKAGE BODY pkg_produccion AS

    TYPE t_consumo IS RECORD (
        id_insumo NUMBER, cantidad NUMBER, costo_unitario NUMBER, valor NUMBER);
    TYPE t_consumos IS TABLE OF t_consumo INDEX BY PLS_INTEGER;

    PROCEDURE sp_registrar_lote(
        p_id_producto       IN  NUMBER,
        p_litros_usados     IN  NUMBER,
        p_cantidad_obtenida IN  NUMBER,
        p_costo_por_litro   IN  NUMBER,
        p_fecha_produccion  IN  DATE,
        p_fecha_vencimiento IN  DATE,
        p_id_lote           OUT NUMBER,
        p_codigo_lote       OUT VARCHAR2
    ) IS
        v_sku        VARCHAR2(20);
        v_activo     NUMBER;
        v_fecha      DATE := TRUNC(NVL(p_fecha_produccion, SYSDATE));
        v_vence      DATE;
        v_secuencia  NUMBER;
        v_costo_leche NUMBER;
        v_costo_ins  NUMBER := 0;
        v_consumos   t_consumos;
        v_req        NUMBER;
        v_usuario    VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_producto IS NULL OR p_litros_usados IS NULL OR p_litros_usados <= 0
           OR p_cantidad_obtenida IS NULL OR p_cantidad_obtenida <= 0
           OR p_costo_por_litro IS NULL OR p_costo_por_litro < 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Producto, litros y cantidad son obligatorios y mayores a cero; el costo por litro no puede ser negativo.');
        END IF;
        pkg_periodos.sp_validar_abierto(pkg_periodos.fn_id_periodo(v_fecha), v_fecha);

        -- Se bloquea el producto: serializa la generacion del codigo y el ingreso de stock.
        BEGIN
            SELECT codigo_sku, activo INTO v_sku, v_activo
              FROM productos WHERE id_producto = p_id_producto FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe.');
        END;
        IF v_activo = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'El producto esta inactivo.');
        END IF;

        -- Insumos de la receta: se bloquean en orden de id (sin interbloqueos), se verifica el stock y se
        -- toma el costo promedio de este momento. Nada se descuenta hasta que el lote exista.
        FOR r IN (SELECT i.id_insumo, i.codigo, i.nombre, i.activo, i.stock_actual, i.costo_promedio, i.unidad_medida,
                         rp.cantidad_por_unidad
                    FROM recetas_producto rp
                    JOIN insumos i ON i.id_insumo = rp.id_insumo
                   WHERE rp.id_producto = p_id_producto
                   ORDER BY i.id_insumo
                     FOR UPDATE OF i.stock_actual WAIT 10) LOOP
            v_req := ROUND(r.cantidad_por_unidad * p_cantidad_obtenida, 3);
            IF v_req > 0 THEN
                IF r.activo = 0 THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                        'El insumo ' || r.nombre || ' de la receta esta inactivo.');
                END IF;
                IF r.stock_actual < v_req THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_stock_insuficiente,
                        'Falta ' || r.nombre || ': se necesitan ' || v_req || ' ' || r.unidad_medida
                        || ' y hay ' || r.stock_actual || '.');
                END IF;
                v_consumos(v_consumos.COUNT + 1).id_insumo := r.id_insumo;
                v_consumos(v_consumos.COUNT).cantidad := v_req;
                v_consumos(v_consumos.COUNT).costo_unitario := r.costo_promedio;
                v_consumos(v_consumos.COUNT).valor := ROUND(v_req * r.costo_promedio, 2);
                v_costo_ins := v_costo_ins + v_consumos(v_consumos.COUNT).valor;
            END IF;
        END LOOP;

        SELECT COUNT(*) + 1 INTO v_secuencia
          FROM produccion_lotes
         WHERE id_producto = p_id_producto AND fecha_produccion = v_fecha;
        p_codigo_lote := v_sku || '-' || TO_CHAR(v_fecha, 'YYYYMMDD') || '-' || LPAD(v_secuencia, 3, '0');

        v_vence := NVL(TRUNC(p_fecha_vencimiento), v_fecha + pkg_parametros.fn_numero('DIAS_VIDA_UTIL_DEFAULT'));
        v_costo_leche := ROUND(p_litros_usados * p_costo_por_litro, 2);

        INSERT INTO produccion_lotes (codigo_lote, id_producto, fecha_produccion, litros_leche_usados,
                                      cantidad_obtenida, costo_total, costo_insumos, fecha_vencimiento, usuario_registro)
        VALUES (p_codigo_lote, p_id_producto, v_fecha, p_litros_usados,
                p_cantidad_obtenida, v_costo_leche + v_costo_ins, v_costo_ins, v_vence, v_usuario)
        RETURNING id_lote INTO p_id_lote;

        FOR k IN 1 .. v_consumos.COUNT LOOP
            INSERT INTO consumos_insumo (id_lote, id_insumo, cantidad, costo_unitario, valor)
            VALUES (p_id_lote, v_consumos(k).id_insumo, v_consumos(k).cantidad, v_consumos(k).costo_unitario, v_consumos(k).valor);
            UPDATE insumos SET stock_actual = stock_actual - v_consumos(k).cantidad
             WHERE id_insumo = v_consumos(k).id_insumo;
        END LOOP;

        UPDATE productos SET stock_actual = stock_actual + p_cantidad_obtenida
         WHERE id_producto = p_id_producto;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_lote := NULL;
            p_codigo_lote := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_lote', 'id_producto=' || p_id_producto);
    END sp_registrar_lote;

    PROCEDURE sp_registrar_ajuste(
        p_id_producto IN  NUMBER,
        p_tipo_ajuste IN  VARCHAR2,
        p_cantidad    IN  NUMBER,
        p_observacion IN  VARCHAR2,
        p_id_ajuste   OUT NUMBER
    ) IS
        v_stock   NUMBER;
        v_delta   NUMBER;
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_tipo_ajuste IS NULL OR p_tipo_ajuste NOT IN
           ('MERMA', 'DANO', 'VENCIMIENTO', 'MUESTRA', 'INGRESO_INICIAL', 'CORRECCION_MAS', 'CORRECCION_MENOS') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Tipo de ajuste invalido.');
        END IF;
        IF p_id_producto IS NULL OR p_cantidad IS NULL OR p_cantidad <= 0 OR p_cantidad <> ROUND(p_cantidad, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Producto y cantidad (mayor a cero) son obligatorios.');
        END IF;
        IF p_observacion IS NULL OR LENGTH(TRIM(p_observacion)) < 5 OR LENGTH(p_observacion) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'La observacion es obligatoria (5 a 255 caracteres).');
        END IF;
        -- Sumar stock o corregir hacia arriba es una decision de control: solo ADMIN.
        IF p_tipo_ajuste IN ('INGRESO_INICIAL', 'CORRECCION_MAS', 'CORRECCION_MENOS') THEN
            pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        END IF;
        v_delta := CASE WHEN p_tipo_ajuste IN ('INGRESO_INICIAL', 'CORRECCION_MAS') THEN p_cantidad ELSE -p_cantidad END;

        BEGIN
            SELECT stock_actual INTO v_stock
              FROM productos WHERE id_producto = p_id_producto FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe.');
        END;
        IF v_stock + v_delta < 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_stock_insuficiente,
                'El ajuste dejaria el stock negativo (stock actual ' || v_stock || ').');
        END IF;

        UPDATE productos SET stock_actual = stock_actual + v_delta WHERE id_producto = p_id_producto;
        INSERT INTO ajustes_inventario (id_producto, tipo_ajuste, cantidad_delta, observacion, usuario_registro)
        VALUES (p_id_producto, p_tipo_ajuste, v_delta, TRIM(p_observacion), v_usuario)
        RETURNING id_ajuste INTO p_id_ajuste;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_ajuste := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_ajuste', 'id_producto=' || p_id_producto || ';tipo=' || p_tipo_ajuste);
    END sp_registrar_ajuste;

END pkg_produccion;
/
SHOW ERRORS

-- ============ Vistas ============
CREATE OR REPLACE VIEW vw_lotes AS
SELECT l.id_lote, l.codigo_lote, l.id_producto, p.nombre AS producto, p.codigo_sku, p.unidad_medida,
       l.fecha_produccion, l.litros_leche_usados, l.cantidad_obtenida,
       fn_rendimiento_pct(l.cantidad_obtenida, l.litros_leche_usados) AS porcentaje_rendimiento,
       l.costo_total, l.costo_insumos, l.costo_total - l.costo_insumos AS costo_leche,
       ROUND(l.costo_total / l.cantidad_obtenida, 2) AS costo_unitario,
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

CREATE OR REPLACE VIEW vw_insumos AS
SELECT i.id_insumo, i.codigo, i.nombre, i.unidad_medida, i.costo_promedio, i.stock_actual, i.stock_minimo,
       ROUND(i.stock_actual * i.costo_promedio, 2) AS valor_inventario,
       CASE WHEN i.stock_actual <= i.stock_minimo THEN 1 ELSE 0 END AS bajo_minimo,
       (SELECT COUNT(*) FROM recetas_producto r WHERE r.id_insumo = i.id_insumo) AS productos_que_lo_usan,
       i.activo, i.fecha_creacion, i.usuario_creacion
  FROM insumos i
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_compras_insumo AS
SELECT c.id_compra, c.id_insumo, i.codigo, i.nombre AS insumo, i.unidad_medida,
       c.id_proveedor, pr.nombre AS proveedor, c.id_periodo, c.fecha, c.cantidad, c.valor_total, c.costo_unitario,
       c.referencia, c.estado, c.motivo_anulacion, c.usuario_registro, c.fecha_registro
  FROM compras_insumo c
  JOIN insumos i ON i.id_insumo = c.id_insumo
  LEFT JOIN proveedores pr ON pr.id_proveedor = c.id_proveedor
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_ajustes_insumo AS
SELECT a.id_ajuste, a.id_insumo, i.codigo, i.nombre AS insumo, i.unidad_medida,
       a.tipo_ajuste, a.cantidad_delta, a.valor_delta, a.observacion, a.usuario_registro, a.fecha_registro
  FROM ajustes_insumo a
  JOIN insumos i ON i.id_insumo = a.id_insumo
WITH READ ONLY;

-- La receta de cada producto, valorada al costo promedio actual de cada insumo.
CREATE OR REPLACE VIEW vw_recetas AS
SELECT r.id_producto, p.codigo_sku, p.nombre AS producto, p.unidad_medida AS unidad_producto,
       r.id_insumo, i.codigo AS codigo_insumo, i.nombre AS insumo, i.unidad_medida AS unidad_insumo,
       r.cantidad_por_unidad, i.costo_promedio AS costo_unitario_insumo,
       ROUND(r.cantidad_por_unidad * i.costo_promedio, 4) AS valor_por_unidad,
       i.stock_actual AS stock_insumo, i.activo AS insumo_activo
  FROM recetas_producto r
  JOIN productos p ON p.id_producto = r.id_producto
  JOIN insumos i ON i.id_insumo = r.id_insumo
WITH READ ONLY;

-- Costo de insumos de UNA unidad de cada producto con receta, y cuantas unidades alcanza a producir el stock.
CREATE OR REPLACE VIEW vw_costo_insumos_producto AS
SELECT p.id_producto, p.codigo_sku, p.nombre AS producto,
       COUNT(*) AS cantidad_insumos,
       ROUND(SUM(r.cantidad_por_unidad * i.costo_promedio), 4) AS costo_insumos_unitario,
       FLOOR(MIN(i.stock_actual / r.cantidad_por_unidad)) AS unidades_posibles
  FROM recetas_producto r
  JOIN productos p ON p.id_producto = r.id_producto
  JOIN insumos i ON i.id_insumo = r.id_insumo
 GROUP BY p.id_producto, p.codigo_sku, p.nombre
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_consumos_lote AS
SELECT c.id_consumo, c.id_lote, l.codigo_lote, c.id_insumo, i.codigo, i.nombre AS insumo, i.unidad_medida,
       c.cantidad, c.costo_unitario, c.valor
  FROM consumos_insumo c
  JOIN produccion_lotes l ON l.id_lote = c.id_lote
  JOIN insumos i ON i.id_insumo = c.id_insumo
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
  LEFT JOIN (SELECT id_periodo, SUM(monto) AS gastos FROM gastos_operativos GROUP BY id_periodo) g ON g.id_periodo = p.id_periodo
  LEFT JOIN (SELECT id_periodo, SUM(valor_total) AS compras FROM compras_insumo WHERE estado = 'VIGENTE' GROUP BY id_periodo) ci ON ci.id_periodo = p.id_periodo
WITH READ ONLY;

GRANT SELECT ON vw_lotes                 TO __ROL_APP__;
GRANT SELECT ON vw_insumos               TO __ROL_APP__;
GRANT SELECT ON vw_compras_insumo        TO __ROL_APP__;
GRANT SELECT ON vw_ajustes_insumo        TO __ROL_APP__;
GRANT SELECT ON vw_recetas               TO __ROL_APP__;
GRANT SELECT ON vw_costo_insumos_producto TO __ROL_APP__;
GRANT SELECT ON vw_consumos_lote         TO __ROL_APP__;
GRANT SELECT ON vw_cuentas_quincena      TO __ROL_APP__;
GRANT EXECUTE ON pkg_insumos             TO __ROL_APP__;
GRANT EXECUTE ON pkg_produccion          TO __ROL_APP__;
SHOW ERRORS
EXIT
