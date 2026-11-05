-- =====================================================================
-- 26 - Materias primas: la leche y los insumos pasan a ser un solo catalogo con stock y costo promedio
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1, DESPUES de 02 y 09-22 (22_archivos ya con los tipos PAGO_PROVEEDOR/COMPRA).
-- Con NLS_LANG=.AL32UTF8. Reejecutable.
--
--  * insumos.requiere_calidad: la LECHE (codigo LECHE, litros) es la unica materia prima con control de calidad
--    (temperatura y acidez). Se siembra aqui; no se puede desactivar ni cambiar de unidad.
--  * compras_insumo es la UNICA entrada de materias primas (reemplaza a recepcion_leche): proveedor opcional,
--    "comprado_en", marca contado, calidad de la leche (una entrega RECHAZADA vale 0 y no entra al stock).
--  * precios_proveedor: precio pactado por proveedor + materia prima (antes solo por litro, solo lecheros).
--    Es una referencia: la compra puede traer su propio valor.
--  * pagos_proveedor: se paga por quincena a TODOS los proveedores; la deuda de una quincena son sus compras a
--    credito (las de contado no entran).
--  * sp_registrar_lote ya NO recibe el costo por litro: la leche se descuenta del stock y se valora al costo
--    promedio vigente (igual que los demas insumos) y queda congelada en consumos_insumo.
--  * proveedores.tipo_proveedor desaparece: un proveedor surte varias materias primas.
--  * Se eliminan recepcion_leche, pkg_acopio, fn_precio_litro, vw_recepciones y vw_resumen_pago_lecheros.
-- Si recepcion_leche tiene filas, el script se detiene (no las migra).
-- =====================================================================
SET DEFINE OFF
SET ECHO ON
SET SERVEROUTPUT ON

DECLARE
    n NUMBER;
BEGIN
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM recepcion_leche' INTO n;
    EXCEPTION WHEN OTHERS THEN n := 0;   -- ya no existe (segunda corrida)
    END;
    IF n > 0 THEN
        RAISE_APPLICATION_ERROR(-20999, 'recepcion_leche tiene ' || n || ' filas: este script no las migra. Limpie la base o conviertalas a compras de LECHE antes.');
    END IF;
END;
/

-- ============ 1. Estructura ============
DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-955, -1430, -2260, -1408, -2261, -2264, -2275, -2443, -1442, -1451, -957) THEN RAISE; END IF;
    END;
    FUNCTION existe_col(p_tabla VARCHAR2, p_col VARCHAR2) RETURN BOOLEAN IS
        n NUMBER;
    BEGIN
        SELECT COUNT(*) INTO n FROM user_tab_columns WHERE table_name = p_tabla AND column_name = p_col;
        RETURN n > 0;
    END;
BEGIN
    -- Cartera castigada: el castigo cuenta en la quincena de su fecha (la usan vw_cuentas_quincena y vw_resultado_periodo).
    ejecutar('ALTER TABLE ventas ADD (fecha_castigo DATE)');
    -- Materias primas: la leche lleva control de calidad
    ejecutar('ALTER TABLE insumos ADD (requiere_calidad NUMBER(1) DEFAULT 0 NOT NULL)');
    ejecutar('ALTER TABLE insumos ADD CONSTRAINT ck_insumos_calidad CHECK (requiere_calidad IN (0, 1))');
    -- Solo UNA materia prima puede llevar control de calidad (los umbrales son los de la leche).
    ejecutar('CREATE UNIQUE INDEX uk_insumos_calidad ON insumos (CASE WHEN requiere_calidad = 1 THEN 1 END)');

    -- Compras: contado, procedencia sin proveedor y calidad de la leche
    IF NOT existe_col('COMPRAS_INSUMO', 'CONTADO') THEN
        -- Las compras anteriores se pagaron al comprar: se conservan como de contado.
        ejecutar('ALTER TABLE compras_insumo ADD (contado NUMBER(1) DEFAULT 1 NOT NULL)');
        ejecutar('ALTER TABLE compras_insumo MODIFY (contado DEFAULT 0)');
    END IF;
    ejecutar('ALTER TABLE compras_insumo ADD (comprado_en VARCHAR2(100 CHAR))');
    ejecutar('ALTER TABLE compras_insumo ADD (estado_calidad VARCHAR2(10 CHAR) DEFAULT ''APROBADO'' NOT NULL)');
    ejecutar('ALTER TABLE compras_insumo ADD (temperatura NUMBER(5,2))');
    ejecutar('ALTER TABLE compras_insumo ADD (acidez NUMBER(5,2))');
    ejecutar('ALTER TABLE compras_insumo ADD (motivo_rechazo VARCHAR2(200 CHAR))');
    ejecutar('ALTER TABLE compras_insumo DROP CONSTRAINT ck_compras_ins_valor');
    ejecutar('ALTER TABLE compras_insumo ADD CONSTRAINT ck_compras_ins_valor CHECK (valor_total >= 0)');
    ejecutar('ALTER TABLE compras_insumo ADD CONSTRAINT ck_compras_ins_calidad CHECK (estado_calidad IN (''APROBADO'', ''RECHAZADO''))');
    ejecutar('ALTER TABLE compras_insumo ADD CONSTRAINT ck_compras_ins_rechazo CHECK ' ||
             '((estado_calidad = ''APROBADO'' AND valor_total > 0) OR (estado_calidad = ''RECHAZADO'' AND valor_total = 0 AND motivo_rechazo IS NOT NULL))');
    ejecutar('ALTER TABLE compras_insumo ADD CONSTRAINT ck_compras_ins_contado CHECK (contado IN (0, 1))');
    ejecutar('ALTER TABLE compras_insumo ADD CONSTRAINT ck_compras_ins_credito CHECK (contado = 1 OR id_proveedor IS NOT NULL)');
    ejecutar('CREATE INDEX ix_compras_ins_prov ON compras_insumo (id_proveedor, id_periodo, estado)');

    -- Lotes: litros que la receta esperaba (referencia; los litros usados son los reales)
    ejecutar('ALTER TABLE produccion_lotes ADD (litros_esperados NUMBER(12,2))');

    -- Precios: por proveedor + materia prima
    ejecutar('ALTER TABLE precios_proveedor ADD (id_insumo NUMBER)');
END;
/

-- La leche (codigo LECHE) es la materia prima con control de calidad.
DECLARE
    v_id NUMBER;
    v_unidad VARCHAR2(10);
BEGIN
    BEGIN
        SELECT id_insumo, unidad_medida INTO v_id, v_unidad FROM insumos WHERE codigo = 'LECHE';
        IF v_unidad <> 'LT' THEN
            RAISE_APPLICATION_ERROR(-20999, 'Ya existe un insumo LECHE con unidad ' || v_unidad || '; debe ser LT.');
        END IF;
        UPDATE insumos SET requiere_calidad = 1, activo = 1 WHERE id_insumo = v_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            INSERT INTO insumos (codigo, nombre, unidad_medida, stock_minimo, requiere_calidad)
            VALUES ('LECHE', 'Leche cruda', 'LT', 0, 1);
    END;
    COMMIT;
END;
/

-- Los precios que ya existian eran de leche.
DECLARE
    v_leche NUMBER;
    n NUMBER;
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-955, -1430, -2260, -1408, -2261, -2264, -2275, -2443, -1442, -1451, -957) THEN RAISE; END IF;
    END;
BEGIN
    SELECT id_insumo INTO v_leche FROM insumos WHERE codigo = 'LECHE';
    UPDATE precios_proveedor SET id_insumo = v_leche WHERE id_insumo IS NULL;
    COMMIT;
    ejecutar('ALTER TABLE precios_proveedor MODIFY (id_insumo NOT NULL)');
    ejecutar('ALTER TABLE precios_proveedor ADD CONSTRAINT fk_precios_prov_insumo FOREIGN KEY (id_insumo) REFERENCES insumos (id_insumo)');
    ejecutar('ALTER TABLE precios_proveedor DROP CONSTRAINT uk_precios_proveedor');
    ejecutar('ALTER TABLE precios_proveedor ADD CONSTRAINT uk_precios_prov_insumo UNIQUE (id_proveedor, id_insumo, vigente_desde)');
    SELECT COUNT(*) INTO n FROM user_tab_columns WHERE table_name = 'PRECIOS_PROVEEDOR' AND column_name = 'PRECIO_LITRO';
    IF n > 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE precios_proveedor RENAME COLUMN precio_litro TO precio_unitario';
    END IF;
    ejecutar('ALTER TABLE precios_proveedor MODIFY (precio_unitario NUMBER(14,4))');
END;
/

-- ============ 2. Triggers y funcion de precio ============
-- Una compra solo puede pasar de VIGENTE a ANULADA.
CREATE OR REPLACE TRIGGER trg_compras_ins_guard
BEFORE UPDATE OR DELETE ON compras_insumo
FOR EACH ROW
BEGIN
    IF DELETING THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Las compras no pueden eliminarse; se anulan.');
    END IF;
    IF :OLD.estado = 'ANULADA'
       OR :NEW.id_insumo <> :OLD.id_insumo OR :NEW.id_periodo <> :OLD.id_periodo OR :NEW.fecha <> :OLD.fecha
       OR :NEW.cantidad <> :OLD.cantidad OR :NEW.valor_total <> :OLD.valor_total
       OR :NEW.costo_unitario <> :OLD.costo_unitario
       OR :NEW.contado <> :OLD.contado OR :NEW.estado_calidad <> :OLD.estado_calidad
       OR NVL(:NEW.id_proveedor, -1) <> NVL(:OLD.id_proveedor, -1) THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Una compra solo puede anularse.');
    END IF;
END trg_compras_ins_guard;
/

-- Precio pactado vigente de un proveedor para una materia prima en una fecha (NULL si no hay).
CREATE OR REPLACE FUNCTION fn_precio_proveedor(p_id_proveedor IN NUMBER, p_id_insumo IN NUMBER, p_fecha IN DATE) RETURN NUMBER IS
    v_precio NUMBER;
BEGIN
    SELECT precio_unitario INTO v_precio
      FROM precios_proveedor
     WHERE id_proveedor = p_id_proveedor AND id_insumo = p_id_insumo
       AND vigente_desde = (SELECT MAX(vigente_desde) FROM precios_proveedor
                             WHERE id_proveedor = p_id_proveedor AND id_insumo = p_id_insumo
                               AND vigente_desde <= TRUNC(p_fecha));
    RETURN v_precio;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN NULL;
END fn_precio_proveedor;
/


-- ============ 3. Paquetes ============
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
    -- Entra stock y se recalcula el costo promedio ponderado. La LECHE (control de calidad) la registra el OPERATIVO y
    -- exige proveedor, temperatura y acidez; las demas materias primas, el ADMIN. p_id_proveedor es opcional (si falta,
    -- la compra es de contado y p_comprado_en dice donde se compro). p_valor_total opcional: si falta se usa el precio
    -- pactado del proveedor (la leche, ademas, el parametro PRECIO_LECHE_DEFAULT). Una entrega de leche RECHAZADA vale 0
    -- y no entra al stock. p_contado: 1 = pagada al comprar (no suma a lo que se debe al proveedor).
    PROCEDURE sp_registrar_compra(
        p_id_insumo IN NUMBER, p_id_proveedor IN NUMBER, p_cantidad IN NUMBER, p_valor_total IN NUMBER,
        p_referencia IN VARCHAR2, p_fecha IN DATE, p_contado IN NUMBER, p_comprado_en IN VARCHAR2,
        p_temperatura IN NUMBER, p_acidez IN NUMBER,
        p_id_compra OUT NUMBER, p_estado_calidad OUT VARCHAR2);
    -- ADMIN. Revierte el stock y el costo; solo si el stock alcanza para devolver lo comprado y la quincena no quedo
    -- con pagos por encima de lo comprado.
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
        v_unidad  insumos.unidad_medida%TYPE;
        v_calidad NUMBER;
        v_n       NUMBER;
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
            SELECT unidad_medida, requiere_calidad INTO v_unidad, v_calidad FROM insumos WHERE id_insumo = p_id_insumo FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El insumo no existe.');
        END;
        IF v_calidad = 1 AND v_unidad <> p_unidad_medida THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'La leche se mide siempre en litros.');
        END IF;
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
        v_activo  NUMBER;
        v_calidad NUMBER;
        v_n       NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_activo IS NULL OR p_activo NOT IN (0, 1) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El estado debe ser 0 o 1.');
        END IF;
        BEGIN
            SELECT activo, requiere_calidad INTO v_activo, v_calidad FROM insumos WHERE id_insumo = p_id_insumo FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El insumo no existe.');
        END;
        IF p_activo = 0 AND v_calidad = 1 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'La leche no se puede desactivar.');
        END IF;
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
        p_referencia IN VARCHAR2, p_fecha IN DATE, p_contado IN NUMBER, p_comprado_en IN VARCHAR2,
        p_temperatura IN NUMBER, p_acidez IN NUMBER,
        p_id_compra OUT NUMBER, p_estado_calidad OUT VARCHAR2
    ) IS
        v_fecha    DATE := TRUNC(NVL(p_fecha, SYSDATE));
        v_periodo  NUMBER;
        v_activo   NUMBER;
        v_calidad  NUMBER;
        v_ctrl     NUMBER := 0;   -- 1 = la leche se evalua (modulo CALIDAD_LECHE activo)
        v_prov_ok  NUMBER;
        v_stock    NUMBER;
        v_costo    NUMBER;
        v_contado  NUMBER;
        v_precio   NUMBER;
        v_valor    NUMBER;
        v_motivo   VARCHAR2(200);
        v_temp_max NUMBER;
        v_acid_max NUMBER;
        v_usuario  VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        IF p_id_insumo IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La materia prima es obligatoria.');
        END IF;
        BEGIN
            SELECT requiere_calidad INTO v_calidad FROM insumos WHERE id_insumo = p_id_insumo;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La materia prima no existe.');
        END;
        -- Modulo CALIDAD_LECHE apagado: la leche no exige temperatura ni acidez y entra APROBADA (lo que llegue se ignora).
        IF v_calidad = 1 AND pkg_modulos.fn_modulo_activo('CALIDAD_LECHE') = 1 THEN
            v_ctrl := 1;
        END IF;
        -- La leche la recibe el OPERATIVO (como siempre); el resto de las compras, el ADMIN.
        pkg_seguridad.sp_exigir_rol(CASE WHEN v_calidad = 1 THEN pkg_seguridad.c_rol_operativo ELSE pkg_seguridad.c_rol_admin END);

        -- El valor de la leche lo fija el precio pactado con el proveedor (o el precio por defecto): el OPERATIVO no lo digita.
        IF v_calidad = 1 AND p_valor_total IS NOT NULL AND pkg_seguridad.fn_rol_actual = pkg_seguridad.c_rol_operativo THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'El valor de la leche lo fija el precio pactado con el proveedor; no se puede digitar.');
        END IF;
        IF p_cantidad IS NULL OR p_cantidad <= 0 OR p_cantidad <> ROUND(p_cantidad, 3)
           OR (p_valor_total IS NOT NULL AND (p_valor_total <= 0 OR p_valor_total <> ROUND(p_valor_total, 2))) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'La cantidad (hasta 3 decimales) y el valor total (2 decimales), si se indica, deben ser mayores a cero.');
        END IF;
        IF p_contado IS NOT NULL AND p_contado NOT IN (0, 1) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'contado debe ser 0 o 1.');
        END IF;
        IF p_comprado_en IS NOT NULL AND LENGTH(p_comprado_en) > 100 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'comprado_en admite hasta 100 caracteres.');
        END IF;
        IF v_calidad = 1 THEN
            IF v_ctrl = 1 AND (p_temperatura IS NULL OR p_acidez IS NULL) THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La leche exige temperatura y acidez.');
            END IF;
            IF p_id_proveedor IS NULL THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La leche se recibe de un proveedor registrado.');
            END IF;
        ELSIF p_temperatura IS NOT NULL OR p_acidez IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Solo la leche lleva temperatura y acidez.');
        END IF;
        v_contado := NVL(p_contado, CASE WHEN p_id_proveedor IS NULL THEN 1 ELSE 0 END);
        IF p_id_proveedor IS NULL AND v_contado = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Sin proveedor la compra es de contado.');
        END IF;

        IF p_id_proveedor IS NOT NULL THEN
            BEGIN
                SELECT activo INTO v_prov_ok FROM proveedores WHERE id_proveedor = p_id_proveedor;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El proveedor no existe.');
            END;
            IF v_prov_ok = 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'El proveedor esta inactivo.');
            END IF;
        END IF;

        v_periodo := pkg_periodos.fn_id_periodo(v_fecha);
        pkg_periodos.sp_validar_abierto(v_periodo, v_fecha);

        BEGIN
            SELECT activo, stock_actual, costo_promedio INTO v_activo, v_stock, v_costo
              FROM insumos WHERE id_insumo = p_id_insumo FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La materia prima no existe.');
        END;
        IF v_activo = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'La materia prima esta inactiva.');
        END IF;

        -- Valor: el digitado, o cantidad x precio pactado del proveedor (la leche cae al precio por defecto).
        IF p_valor_total IS NOT NULL THEN
            v_valor := p_valor_total;
            v_precio := ROUND(p_valor_total / p_cantidad, 4);
        ELSE
            v_precio := fn_precio_proveedor(p_id_proveedor, p_id_insumo, v_fecha);
            IF v_precio IS NULL AND v_calidad = 1 THEN
                v_precio := pkg_parametros.fn_numero('PRECIO_LECHE_DEFAULT');
            END IF;
            IF v_precio IS NULL THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                    'El proveedor no tiene precio pactado para esta materia prima: indique el valor total.');
            END IF;
            v_valor := ROUND(p_cantidad * v_precio, 2);
            IF v_valor <= 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El valor de la compra debe ser mayor a cero.');
            END IF;
        END IF;

        p_estado_calidad := 'APROBADO';
        IF v_ctrl = 1 THEN
            v_temp_max := pkg_parametros.fn_numero('TEMP_MAX_LECHE_C');
            v_acid_max := pkg_parametros.fn_numero('ACIDEZ_MAX_DORNIC');
            IF p_temperatura > v_temp_max THEN
                v_motivo := 'Temperatura ' || p_temperatura || ' C supera el maximo de ' || v_temp_max || ' C';
            ELSIF p_acidez > v_acid_max THEN
                v_motivo := 'Acidez ' || p_acidez || ' supera el maximo de ' || v_acid_max;
            END IF;
            IF v_motivo IS NOT NULL THEN
                p_estado_calidad := 'RECHAZADO';
            END IF;
        END IF;

        INSERT INTO compras_insumo (id_insumo, id_proveedor, id_periodo, fecha, cantidad, valor_total, costo_unitario,
                                    referencia, usuario_registro, estado_calidad, temperatura, acidez, motivo_rechazo,
                                    contado, comprado_en)
        VALUES (p_id_insumo, p_id_proveedor, v_periodo, v_fecha, p_cantidad,
                CASE WHEN p_estado_calidad = 'APROBADO' THEN v_valor ELSE 0 END, v_precio,
                SUBSTR(TRIM(p_referencia), 1, 60), v_usuario, p_estado_calidad,
                CASE WHEN v_ctrl = 1 THEN p_temperatura END, CASE WHEN v_ctrl = 1 THEN p_acidez END, v_motivo,
                v_contado, SUBSTR(TRIM(p_comprado_en), 1, 100))
        RETURNING id_compra INTO p_id_compra;

        IF p_estado_calidad = 'APROBADO' THEN
            -- Costo promedio ponderado: (valor que habia + valor que entra) / (stock que habia + stock que entra).
            UPDATE insumos
               SET stock_actual   = v_stock + p_cantidad,
                   costo_promedio = ROUND((v_stock * v_costo + v_valor) / (v_stock + p_cantidad), 4)
             WHERE id_insumo = p_id_insumo;
        END IF;
        pkg_auditoria.sp_registrar('COMPRAS_INSUMO', TO_CHAR(p_id_compra), 'COMPRA_REGISTRADA', NULL,
            'insumo=' || p_id_insumo || '; cantidad=' || p_cantidad || '; valor=' || v_valor || '; calidad=' || p_estado_calidad);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_compra := NULL;
            p_estado_calidad := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_compra', 'id_insumo=' || p_id_insumo);
    END sp_registrar_compra;

    PROCEDURE sp_anular_compra(p_id_compra IN NUMBER, p_motivo IN VARCHAR2) IS
        v_estado    compras_insumo.estado%TYPE;
        v_insumo    NUMBER;
        v_periodo   NUMBER;
        v_fecha     DATE;
        v_cantidad  NUMBER;
        v_valor     NUMBER;
        v_calidad   VARCHAR2(10);
        v_proveedor NUMBER;
        v_contado   NUMBER;
        v_stock     NUMBER;
        v_costo     NUMBER;
        v_nuevo     NUMBER;
        v_valor_inv NUMBER;
        v_comprado  NUMBER;
        v_pagado    NUMBER;
        v_dummy     NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_compra IS NULL OR p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 10 OR LENGTH(p_motivo) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Compra y motivo (10 a 255 caracteres) son obligatorios.');
        END IF;
        BEGIN
            SELECT estado, id_insumo, id_periodo, fecha, cantidad, valor_total, estado_calidad, id_proveedor, contado
              INTO v_estado, v_insumo, v_periodo, v_fecha, v_cantidad, v_valor, v_calidad, v_proveedor, v_contado
              FROM compras_insumo WHERE id_compra = p_id_compra;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La compra no existe.');
        END;
        -- Se bloquea la materia prima (y el proveedor) y se relee la compra: dos anulaciones simultaneas no deben restar dos veces.
        SELECT stock_actual, costo_promedio INTO v_stock, v_costo FROM insumos WHERE id_insumo = v_insumo FOR UPDATE WAIT 10;
        IF v_proveedor IS NOT NULL THEN
            SELECT id_proveedor INTO v_dummy FROM proveedores WHERE id_proveedor = v_proveedor FOR UPDATE WAIT 10;
        END IF;
        SELECT estado INTO v_estado FROM compras_insumo WHERE id_compra = p_id_compra FOR UPDATE WAIT 10;
        IF v_estado = 'ANULADA' THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La compra ya esta anulada.');
        END IF;
        pkg_periodos.sp_validar_abierto(v_periodo, v_fecha);

        IF v_calidad = 'APROBADO' THEN
            -- Con el costo promedio no hay forma exacta de "devolver" una compra si despues se uso o se ajusto esta materia
            -- prima: el promedio quedaria mal para los lotes siguientes. En ese caso se corrige con un ajuste de inventario.
            SELECT COUNT(*) INTO v_dummy FROM dual
             WHERE EXISTS (SELECT 1 FROM consumos_insumo ci JOIN produccion_lotes lt ON lt.id_lote = ci.id_lote
                            WHERE ci.id_insumo = v_insumo
                              AND lt.fecha_registro > (SELECT k.fecha_registro FROM compras_insumo k WHERE k.id_compra = p_id_compra))
                OR EXISTS (SELECT 1 FROM ajustes_insumo aj
                            WHERE aj.id_insumo = v_insumo
                              AND aj.fecha_registro > (SELECT k.fecha_registro FROM compras_insumo k WHERE k.id_compra = p_id_compra));
            IF v_dummy > 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                    'No se puede anular: despues de esta compra ya se uso o se ajusto esta materia prima. Registre un ajuste de inventario.');
            END IF;
            IF v_stock < v_cantidad THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_stock_insuficiente,
                    'No se puede anular: ya se gasto parte de lo comprado (stock actual ' || v_stock || ', compra ' || v_cantidad || '). Use un ajuste.');
            END IF;
            -- Una compra a credito ya pagada: la quincena no puede quedar con pagos por encima de lo comprado.
            IF v_contado = 0 AND v_proveedor IS NOT NULL THEN
                SELECT NVL(SUM(valor_total), 0) INTO v_comprado FROM compras_insumo
                 WHERE id_proveedor = v_proveedor AND id_periodo = v_periodo AND estado = 'VIGENTE' AND contado = 0;
                SELECT NVL(SUM(monto), 0) INTO v_pagado FROM pagos_proveedor
                 WHERE id_proveedor = v_proveedor AND id_periodo_liquidado = v_periodo AND estado = 'VIGENTE';
                IF v_comprado - v_valor < v_pagado THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                        'No se puede anular: esa quincena ya se pago al proveedor (' || v_pagado || '). Anule primero el pago.');
                END IF;
            END IF;
            v_nuevo := v_stock - v_cantidad;
            v_valor_inv := v_stock * v_costo - v_valor;
            UPDATE insumos
               SET stock_actual   = v_nuevo,
                   costo_promedio = CASE WHEN v_nuevo > 0 AND v_valor_inv > 0 THEN ROUND(v_valor_inv / v_nuevo, 4) ELSE costo_promedio END
             WHERE id_insumo = v_insumo;
        END IF;
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

CREATE OR REPLACE PACKAGE pkg_produccion AUTHID DEFINER AS
    -- La leche se descuenta del stock al costo promedio vigente (como cualquier materia prima) y queda congelada en
    -- consumos_insumo; el costo del lote = leche + demas materias primas de la receta. Si la receta lleva leche,
    -- litros_esperados = cantidad por unidad x cantidad obtenida (referencia: los litros usados son los reales).
    PROCEDURE sp_registrar_lote(
        p_id_producto       IN  NUMBER,
        p_litros_usados     IN  NUMBER,
        p_cantidad_obtenida IN  NUMBER,
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
        p_fecha_produccion  IN  DATE,
        p_fecha_vencimiento IN  DATE,
        p_id_lote           OUT NUMBER,
        p_codigo_lote       OUT VARCHAR2
    ) IS
        v_sku         VARCHAR2(20);
        v_activo      NUMBER;
        v_fecha       DATE := TRUNC(NVL(p_fecha_produccion, SYSDATE));
        v_vence       DATE;
        v_secuencia   NUMBER;
        v_costo_leche NUMBER := 0;
        v_costo_ins   NUMBER := 0;
        v_esperados   NUMBER;
        v_hay_leche   BOOLEAN := FALSE;
        v_consumos    t_consumos;
        v_req         NUMBER;
        v_usuario     VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_producto IS NULL OR p_litros_usados IS NULL OR p_litros_usados <= 0 OR p_litros_usados <> ROUND(p_litros_usados, 2)
           OR p_cantidad_obtenida IS NULL OR p_cantidad_obtenida <= 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Producto, litros (hasta 2 decimales) y cantidad son obligatorios y mayores a cero.');
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

        -- Materias primas: la leche (siempre) y las de la receta. Se bloquean en orden de id (sin interbloqueos), se
        -- verifica el stock y se toma el costo promedio de este momento. Nada se descuenta hasta que el lote exista.
        FOR r IN (SELECT i.id_insumo, i.nombre, i.activo, i.stock_actual, i.costo_promedio, i.unidad_medida,
                         i.requiere_calidad,
                         (SELECT rp.cantidad_por_unidad FROM recetas_producto rp
                           WHERE rp.id_producto = p_id_producto AND rp.id_insumo = i.id_insumo) AS cantidad_por_unidad
                    FROM insumos i
                   WHERE i.requiere_calidad = 1
                      OR i.id_insumo IN (SELECT id_insumo FROM recetas_producto WHERE id_producto = p_id_producto)
                   ORDER BY i.id_insumo
                     FOR UPDATE OF i.stock_actual WAIT 10) LOOP
            IF r.requiere_calidad = 1 THEN
                v_hay_leche := TRUE;
                v_req := p_litros_usados;
                IF r.cantidad_por_unidad IS NOT NULL THEN
                    v_esperados := ROUND(r.cantidad_por_unidad * p_cantidad_obtenida, 2);
                END IF;
            ELSE
                v_req := ROUND(r.cantidad_por_unidad * p_cantidad_obtenida, 3);
            END IF;
            IF v_req > 0 THEN
                IF r.activo = 0 THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                        'La materia prima ' || r.nombre || ' esta inactiva.');
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
                IF r.requiere_calidad = 1 THEN
                    v_costo_leche := v_costo_leche + v_consumos(v_consumos.COUNT).valor;
                ELSE
                    v_costo_ins := v_costo_ins + v_consumos(v_consumos.COUNT).valor;
                END IF;
            END IF;
        END LOOP;
        IF NOT v_hay_leche THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'No esta definida la materia prima LECHE.');
        END IF;

        SELECT COUNT(*) + 1 INTO v_secuencia
          FROM produccion_lotes
         WHERE id_producto = p_id_producto AND fecha_produccion = v_fecha;
        p_codigo_lote := v_sku || '-' || TO_CHAR(v_fecha, 'YYYYMMDD') || '-' || LPAD(v_secuencia, 3, '0');

        v_vence := NVL(TRUNC(p_fecha_vencimiento), v_fecha + pkg_parametros.fn_numero('DIAS_VIDA_UTIL_DEFAULT'));

        INSERT INTO produccion_lotes (codigo_lote, id_producto, fecha_produccion, litros_leche_usados,
                                      cantidad_obtenida, costo_total, costo_insumos, fecha_vencimiento, usuario_registro,
                                      litros_esperados)
        VALUES (p_codigo_lote, p_id_producto, v_fecha, p_litros_usados,
                p_cantidad_obtenida, v_costo_leche + v_costo_ins, v_costo_ins, v_vence, v_usuario, v_esperados)
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


-- ============ pkg_pagos_proveedor: precios por materia prima y pagos por quincena a TODOS los proveedores ============
CREATE OR REPLACE PACKAGE pkg_pagos_proveedor AUTHID DEFINER AS
    -- ADMIN. Fija el precio pactado de una materia prima con un proveedor desde una fecha. Es una referencia para las
    -- compras futuras (las ya hechas conservan su valor). Misma fecha = corrige el precio de ese dia.
    PROCEDURE sp_fijar_precio(p_id_proveedor IN NUMBER, p_id_insumo IN NUMBER, p_precio IN NUMBER, p_vigente_desde IN DATE);
    -- ADMIN. Paga (todo o parte) lo comprado a credito en una quincena. No puede superar el saldo de esa quincena.
    PROCEDURE sp_registrar_pago(
        p_id_proveedor IN NUMBER, p_id_periodo_liquidado IN NUMBER, p_monto IN NUMBER,
        p_metodo_pago IN VARCHAR2, p_referencia IN VARCHAR2, p_fecha IN DATE, p_id_pago OUT NUMBER);
    -- ADMIN. Anula un pago (motivo obligatorio). La quincena del pago debe estar abierta.
    PROCEDURE sp_anular_pago(p_id_pago IN NUMBER, p_motivo IN VARCHAR2);
END pkg_pagos_proveedor;
/
CREATE OR REPLACE PACKAGE BODY pkg_pagos_proveedor AS

    PROCEDURE sp_fijar_precio(p_id_proveedor IN NUMBER, p_id_insumo IN NUMBER, p_precio IN NUMBER, p_vigente_desde IN DATE) IS
        v_dummy    NUMBER;
        v_activo   NUMBER;
        v_fecha    DATE := TRUNC(NVL(p_vigente_desde, SYSDATE));
        v_anterior NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_proveedor IS NULL OR p_id_insumo IS NULL OR p_precio IS NULL OR p_precio <= 0 OR p_precio > 100000000
           OR p_precio <> ROUND(p_precio, 4) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'El precio debe ser mayor a cero, de hasta 100000000 y con maximo 4 decimales.');
        END IF;
        BEGIN
            SELECT id_proveedor INTO v_dummy FROM proveedores WHERE id_proveedor = p_id_proveedor FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El proveedor no existe.');
        END;
        BEGIN
            SELECT activo INTO v_activo FROM insumos WHERE id_insumo = p_id_insumo;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La materia prima no existe.');
        END;
        IF v_activo = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'La materia prima esta inactiva.');
        END IF;
        BEGIN
            SELECT precio_unitario INTO v_anterior FROM precios_proveedor
             WHERE id_proveedor = p_id_proveedor AND id_insumo = p_id_insumo AND vigente_desde = v_fecha;
            UPDATE precios_proveedor SET precio_unitario = p_precio
             WHERE id_proveedor = p_id_proveedor AND id_insumo = p_id_insumo AND vigente_desde = v_fecha;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                INSERT INTO precios_proveedor (id_proveedor, id_insumo, precio_unitario, vigente_desde)
                VALUES (p_id_proveedor, p_id_insumo, p_precio, v_fecha);
        END;
        pkg_auditoria.sp_registrar('PRECIOS_PROVEEDOR', p_id_proveedor || ':' || p_id_insumo, 'PRECIO',
            TO_CHAR(v_anterior), p_precio || ' desde ' || TO_CHAR(v_fecha, 'YYYY-MM-DD'));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_fijar_precio', 'id_proveedor=' || p_id_proveedor || ';id_insumo=' || p_id_insumo);
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
            SELECT id_proveedor INTO v_dummy FROM proveedores WHERE id_proveedor = p_id_proveedor FOR UPDATE WAIT 10;
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
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'No se puede pagar una quincena que aun no empieza.');
        END IF;
        v_id_per := pkg_periodos.fn_id_periodo(v_fecha);
        pkg_periodos.sp_validar_abierto(v_id_per, v_fecha);

        -- Lo que se debe de esa quincena: las compras VIGENTES a credito (las de contado ya estan pagadas; lo rechazado vale 0).
        SELECT NVL(SUM(valor_total), 0) INTO v_valor FROM compras_insumo
         WHERE id_proveedor = p_id_proveedor AND id_periodo = p_id_periodo_liquidado AND estado = 'VIGENTE' AND contado = 0;
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
              FROM pagos_proveedor WHERE id_pago = p_id_pago FOR UPDATE WAIT 10;
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


-- pkg_catalogos: el proveedor ya no tiene tipo (surte varias materias primas)
CREATE OR REPLACE PACKAGE pkg_catalogos AUTHID DEFINER AS
    PROCEDURE sp_crear_cliente(
        p_tipo_documento   IN  VARCHAR2,
        p_numero_documento IN  VARCHAR2,
        p_nombre           IN  VARCHAR2,
        p_email            IN  VARCHAR2,
        p_telefono         IN  VARCHAR2,
        p_direccion        IN  VARCHAR2,
        p_limite_credito   IN  NUMBER,
        p_id_cliente       OUT NUMBER
    );
    PROCEDURE sp_actualizar_cliente(
        p_id_cliente IN NUMBER,
        p_nombre     IN VARCHAR2,
        p_email      IN VARCHAR2,
        p_telefono   IN VARCHAR2,
        p_direccion  IN VARCHAR2
    );
    PROCEDURE sp_cambiar_limite_credito(p_id_cliente IN NUMBER, p_nuevo_limite IN NUMBER);

    PROCEDURE sp_crear_proveedor(
        p_tipo_documento   IN  VARCHAR2,
        p_numero_documento IN  VARCHAR2,
        p_nombre           IN  VARCHAR2,
        p_telefono         IN  VARCHAR2,
        p_id_proveedor     OUT NUMBER
    );
    PROCEDURE sp_actualizar_proveedor(p_id_proveedor IN NUMBER, p_nombre IN VARCHAR2, p_telefono IN VARCHAR2);

    PROCEDURE sp_crear_producto(
        p_codigo_sku    IN  VARCHAR2,
        p_nombre        IN  VARCHAR2,
        p_unidad_medida IN  VARCHAR2,
        p_precio_base   IN  NUMBER,
        p_tarifa_iva    IN  NUMBER,
        p_id_producto   OUT NUMBER
    );
    -- Edita nombre y unidad de medida (OPERATIVO; supuesto C-07 del dashboard).
    -- La unidad solo puede cambiar si el producto no tiene movimientos.
    PROCEDURE sp_actualizar_producto(p_id_producto IN NUMBER, p_nombre IN VARCHAR2, p_unidad_medida IN VARCHAR2);
    PROCEDURE sp_actualizar_precio(p_id_producto IN NUMBER, p_precio_base IN NUMBER, p_tarifa_iva IN NUMBER);

    -- p_entidad: CLIENTE, PROVEEDOR, PRODUCTO o CATEGORIA_GASTO
    PROCEDURE sp_cambiar_estado(p_entidad IN VARCHAR2, p_id IN NUMBER, p_activo IN NUMBER);
END pkg_catalogos;
/
CREATE OR REPLACE PACKAGE BODY pkg_catalogos AS

    PROCEDURE pr_requerir_texto(p_valor IN VARCHAR2, p_campo IN VARCHAR2, p_max IN PLS_INTEGER) IS
    BEGIN
        IF p_valor IS NULL OR TRIM(p_valor) IS NULL OR LENGTH(p_valor) > p_max THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'El campo ' || p_campo || ' es obligatorio (maximo ' || p_max || ' caracteres).');
        END IF;
    END pr_requerir_texto;

    PROCEDURE pr_validar_documento(p_tipo IN VARCHAR2, p_numero IN VARCHAR2) IS
    BEGIN
        IF p_tipo IS NULL OR p_tipo NOT IN ('CC', 'NIT', 'CE', 'PASAPORTE', 'TI') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Tipo de documento invalido.');
        END IF;
        IF p_numero IS NULL OR NOT REGEXP_LIKE(p_numero, '^[A-Za-z0-9-]{5,20}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Numero de documento invalido (5 a 20 letras, numeros o guion).');
        END IF;
    END pr_validar_documento;

    PROCEDURE pr_validar_email(p_email IN VARCHAR2) IS
    BEGIN
        IF p_email IS NOT NULL
           AND NOT REGEXP_LIKE(p_email, '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Correo electronico invalido.');
        END IF;
    END pr_validar_email;

    PROCEDURE sp_crear_cliente(
        p_tipo_documento   IN  VARCHAR2,
        p_numero_documento IN  VARCHAR2,
        p_nombre           IN  VARCHAR2,
        p_email            IN  VARCHAR2,
        p_telefono         IN  VARCHAR2,
        p_direccion        IN  VARCHAR2,
        p_limite_credito   IN  NUMBER,
        p_id_cliente       OUT NUMBER
    ) IS
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pr_validar_documento(p_tipo_documento, p_numero_documento);
        pr_requerir_texto(p_nombre, 'nombre', 120);
        pr_validar_email(p_email);
        IF p_limite_credito IS NULL OR p_limite_credito < 0 OR p_limite_credito <> ROUND(p_limite_credito, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Limite de credito invalido.');
        END IF;
        IF p_limite_credito > 0 THEN
            pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        END IF;

        INSERT INTO clientes (tipo_documento, numero_documento, nombre, email, telefono, direccion,
                              limite_credito, usuario_creacion)
        VALUES (p_tipo_documento, p_numero_documento, TRIM(p_nombre), p_email, p_telefono, p_direccion,
                p_limite_credito, v_usuario)
        RETURNING id_cliente INTO p_id_cliente;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_cliente := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_cliente', 'doc=' || p_tipo_documento || ' ' || p_numero_documento);
    END sp_crear_cliente;

    PROCEDURE sp_actualizar_cliente(
        p_id_cliente IN NUMBER,
        p_nombre     IN VARCHAR2,
        p_email      IN VARCHAR2,
        p_telefono   IN VARCHAR2,
        p_direccion  IN VARCHAR2
    ) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pr_requerir_texto(p_nombre, 'nombre', 120);
        pr_validar_email(p_email);
        UPDATE clientes
           SET nombre = TRIM(p_nombre), email = p_email, telefono = p_telefono, direccion = p_direccion
         WHERE id_cliente = p_id_cliente;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_cliente', 'id_cliente=' || p_id_cliente);
    END sp_actualizar_cliente;

    PROCEDURE sp_cambiar_limite_credito(p_id_cliente IN NUMBER, p_nuevo_limite IN NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_nuevo_limite IS NULL OR p_nuevo_limite < 0 OR p_nuevo_limite <> ROUND(p_nuevo_limite, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Limite de credito invalido.');
        END IF;
        UPDATE clientes SET limite_credito = p_nuevo_limite WHERE id_cliente = p_id_cliente;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_cambiar_limite_credito', 'id_cliente=' || p_id_cliente);
    END sp_cambiar_limite_credito;

    PROCEDURE sp_crear_proveedor(
        p_tipo_documento   IN  VARCHAR2,
        p_numero_documento IN  VARCHAR2,
        p_nombre           IN  VARCHAR2,
        p_telefono         IN  VARCHAR2,
        p_id_proveedor     OUT NUMBER
    ) IS
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pr_validar_documento(p_tipo_documento, p_numero_documento);
        pr_requerir_texto(p_nombre, 'nombre', 120);
        INSERT INTO proveedores (tipo_documento, numero_documento, nombre, telefono, usuario_creacion)
        VALUES (p_tipo_documento, p_numero_documento, TRIM(p_nombre), p_telefono, v_usuario)
        RETURNING id_proveedor INTO p_id_proveedor;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_proveedor := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_proveedor', 'doc=' || p_tipo_documento || ' ' || p_numero_documento);
    END sp_crear_proveedor;

    PROCEDURE sp_actualizar_proveedor(p_id_proveedor IN NUMBER, p_nombre IN VARCHAR2, p_telefono IN VARCHAR2) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pr_requerir_texto(p_nombre, 'nombre', 120);
        UPDATE proveedores SET nombre = TRIM(p_nombre), telefono = p_telefono WHERE id_proveedor = p_id_proveedor;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El proveedor no existe.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_proveedor', 'id_proveedor=' || p_id_proveedor);
    END sp_actualizar_proveedor;

    PROCEDURE sp_crear_producto(
        p_codigo_sku    IN  VARCHAR2,
        p_nombre        IN  VARCHAR2,
        p_unidad_medida IN  VARCHAR2,
        p_precio_base   IN  NUMBER,
        p_tarifa_iva    IN  NUMBER,
        p_id_producto   OUT NUMBER
    ) IS
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_codigo_sku IS NULL OR NOT REGEXP_LIKE(p_codigo_sku, '^[A-Z0-9-]{3,20}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'El SKU debe tener de 3 a 20 caracteres: mayusculas, numeros o guion.');
        END IF;
        pr_requerir_texto(p_nombre, 'nombre', 100);
        IF p_unidad_medida IS NULL OR p_unidad_medida NOT IN ('KG', 'GR', 'LT', 'ML', 'UND', 'PAQ') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Unidad de medida invalida.');
        END IF;
        IF p_precio_base IS NULL OR p_precio_base < 0 OR p_precio_base <> ROUND(p_precio_base, 2)
           OR p_tarifa_iva IS NULL OR p_tarifa_iva NOT BETWEEN 0 AND 100 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Precio o tarifa de IVA invalidos.');
        END IF;
        INSERT INTO productos (codigo_sku, nombre, unidad_medida, precio_base, tarifa_iva, usuario_creacion)
        VALUES (p_codigo_sku, TRIM(p_nombre), p_unidad_medida, p_precio_base, p_tarifa_iva, v_usuario)
        RETURNING id_producto INTO p_id_producto;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_producto := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_producto', 'sku=' || p_codigo_sku);
    END sp_crear_producto;

    PROCEDURE sp_actualizar_producto(p_id_producto IN NUMBER, p_nombre IN VARCHAR2, p_unidad_medida IN VARCHAR2) IS
        v_unidad_actual productos.unidad_medida%TYPE;
        v_stock         productos.stock_actual%TYPE;
        v_movimientos   NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pr_requerir_texto(p_nombre, 'nombre', 100);
        IF p_unidad_medida IS NULL OR p_unidad_medida NOT IN ('KG', 'GR', 'LT', 'ML', 'UND', 'PAQ') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Unidad de medida invalida.');
        END IF;

        -- Bloquea la fila: evita que una venta o un ajuste concurrente cambie los
        -- movimientos entre la verificacion y el UPDATE.
        BEGIN
            SELECT unidad_medida, stock_actual
              INTO v_unidad_actual, v_stock
              FROM productos
             WHERE id_producto = p_id_producto
               FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe.');
        END;

        IF p_unidad_medida <> v_unidad_actual THEN
            SELECT COUNT(*) INTO v_movimientos FROM (
                SELECT 1 FROM ventas_detalle        WHERE id_producto = p_id_producto AND ROWNUM = 1
                UNION ALL
                SELECT 1 FROM ajustes_inventario    WHERE id_producto = p_id_producto AND ROWNUM = 1
                UNION ALL
                SELECT 1 FROM produccion_lotes      WHERE id_producto = p_id_producto AND ROWNUM = 1
                UNION ALL
                SELECT 1 FROM notas_credito_detalle WHERE id_producto = p_id_producto AND ROWNUM = 1
            );
            IF v_movimientos > 0 OR v_stock <> 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                    'La unidad de medida no puede cambiarse: el producto ya tiene movimientos o existencias.');
            END IF;
        END IF;

        UPDATE productos
           SET nombre = TRIM(p_nombre), unidad_medida = p_unidad_medida
         WHERE id_producto = p_id_producto;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_producto', 'id_producto=' || p_id_producto);
    END sp_actualizar_producto;

    PROCEDURE sp_actualizar_precio(p_id_producto IN NUMBER, p_precio_base IN NUMBER, p_tarifa_iva IN NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_precio_base IS NULL OR p_precio_base < 0 OR p_precio_base <> ROUND(p_precio_base, 2)
           OR p_tarifa_iva IS NULL OR p_tarifa_iva NOT BETWEEN 0 AND 100 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Precio o tarifa de IVA invalidos.');
        END IF;
        UPDATE productos SET precio_base = p_precio_base, tarifa_iva = p_tarifa_iva WHERE id_producto = p_id_producto;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_precio', 'id_producto=' || p_id_producto);
    END sp_actualizar_precio;

    PROCEDURE sp_cambiar_estado(p_entidad IN VARCHAR2, p_id IN NUMBER, p_activo IN NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_activo IS NULL OR p_activo NOT IN (0, 1) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El estado debe ser 0 o 1.');
        END IF;
        IF p_entidad = 'CLIENTE' THEN
            UPDATE clientes SET activo = p_activo WHERE id_cliente = p_id;
        ELSIF p_entidad = 'PROVEEDOR' THEN
            UPDATE proveedores SET activo = p_activo WHERE id_proveedor = p_id;
        ELSIF p_entidad = 'PRODUCTO' THEN
            UPDATE productos SET activo = p_activo WHERE id_producto = p_id;
        ELSIF p_entidad = 'CATEGORIA_GASTO' THEN
            UPDATE categorias_gasto SET activo = p_activo WHERE id_categoria = p_id;
        ELSE
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Entidad no soportada.');
        END IF;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El registro no existe.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_cambiar_estado', p_entidad || ' id=' || p_id);
    END sp_cambiar_estado;

END pkg_catalogos;
/
SHOW ERRORS


-- ============ 4. Vistas ============
CREATE OR REPLACE VIEW vw_proveedores AS
SELECT id_proveedor, tipo_documento, numero_documento, nombre, telefono, activo
  FROM proveedores
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_insumos AS
SELECT i.id_insumo, i.codigo, i.nombre, i.unidad_medida, i.costo_promedio, i.stock_actual, i.stock_minimo,
       ROUND(i.stock_actual * i.costo_promedio, 2) AS valor_inventario,
       CASE WHEN i.stock_minimo > 0 AND i.stock_actual <= i.stock_minimo THEN 1 ELSE 0 END AS bajo_minimo,
       (SELECT COUNT(*) FROM recetas_producto r WHERE r.id_insumo = i.id_insumo) AS productos_que_lo_usan,
       i.activo, i.fecha_creacion, i.usuario_creacion, i.requiere_calidad
  FROM insumos i
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_compras_insumo AS
SELECT c.id_compra, c.id_insumo, i.codigo, i.nombre AS insumo, i.unidad_medida,
       c.id_proveedor, pr.nombre AS proveedor, c.id_periodo, c.fecha, c.cantidad, c.valor_total, c.costo_unitario,
       c.referencia, c.estado, c.motivo_anulacion, c.usuario_registro, c.fecha_registro,
       c.contado, c.comprado_en, c.estado_calidad, c.temperatura, c.acidez, c.motivo_rechazo, i.requiere_calidad
  FROM compras_insumo c
  JOIN insumos i ON i.id_insumo = c.id_insumo
  LEFT JOIN proveedores pr ON pr.id_proveedor = c.id_proveedor
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_precios_proveedor AS
SELECT p.id_precio, p.id_proveedor, pr.nombre AS proveedor, p.id_insumo, i.codigo, i.nombre AS insumo, i.unidad_medida,
       p.precio_unitario, p.vigente_desde,
       CASE WHEN p.vigente_desde = (SELECT MAX(x.vigente_desde) FROM precios_proveedor x
                                     WHERE x.id_proveedor = p.id_proveedor AND x.id_insumo = p.id_insumo
                                       AND x.vigente_desde <= TRUNC(SYSDATE))
            THEN 1 ELSE 0 END AS vigente,
       p.usuario_creacion, p.fecha_creacion
  FROM precios_proveedor p
  JOIN proveedores pr ON pr.id_proveedor = p.id_proveedor
  JOIN insumos i ON i.id_insumo = p.id_insumo
WITH READ ONLY;

-- Por quincena y proveedor: lo comprado a credito, lo pagado y lo que se debe.
CREATE OR REPLACE VIEW vw_resumen_pagos_proveedores AS
SELECT p.id_periodo, p.anio, p.mes, p.quincena, pr.id_proveedor, pr.nombre AS proveedor,
       COUNT(*) AS numero_compras,
       SUM(c.valor_total) AS valor_compras,
       NVL((SELECT SUM(g.monto) FROM pagos_proveedor g
             WHERE g.id_proveedor = pr.id_proveedor AND g.id_periodo_liquidado = p.id_periodo
               AND g.estado = 'VIGENTE'), 0) AS valor_pagado,
       SUM(c.valor_total) - NVL((SELECT SUM(g.monto) FROM pagos_proveedor g
             WHERE g.id_proveedor = pr.id_proveedor AND g.id_periodo_liquidado = p.id_periodo
               AND g.estado = 'VIGENTE'), 0) AS saldo
  FROM compras_insumo c
  JOIN proveedores pr ON pr.id_proveedor = c.id_proveedor
  JOIN periodos_quincena p ON p.id_periodo = c.id_periodo
 WHERE c.estado = 'VIGENTE' AND c.contado = 0 AND c.estado_calidad = 'APROBADO'
 GROUP BY p.id_periodo, p.anio, p.mes, p.quincena, pr.id_proveedor, pr.nombre
WITH READ ONLY;

-- Cuanto se le debe a cada proveedor en total (todas las quincenas).
CREATE OR REPLACE VIEW vw_saldo_proveedores AS
SELECT pr.id_proveedor, pr.nombre AS proveedor, pr.activo,
       NVL(c.valor, 0)    AS total_comprado,
       NVL(g.pagado, 0)   AS total_pagado,
       NVL(c.valor, 0) - NVL(g.pagado, 0) AS saldo,
       c.ultima_compra, g.ultimo_pago
  FROM proveedores pr
  LEFT JOIN (SELECT id_proveedor, SUM(valor_total) AS valor, MAX(fecha) AS ultima_compra
               FROM compras_insumo WHERE estado = 'VIGENTE' AND contado = 0 AND estado_calidad = 'APROBADO'
              GROUP BY id_proveedor) c ON c.id_proveedor = pr.id_proveedor
  LEFT JOIN (SELECT id_proveedor, SUM(monto) AS pagado, MAX(fecha_pago) AS ultimo_pago
               FROM pagos_proveedor WHERE estado = 'VIGENTE' GROUP BY id_proveedor) g ON g.id_proveedor = pr.id_proveedor
WITH READ ONLY;

-- Calidad de la leche por proveedor (las entregas anuladas no cuentan).
CREATE OR REPLACE VIEW vw_calidad_leche_proveedor AS
SELECT pr.id_proveedor, pr.nombre AS proveedor,
       COUNT(c.id_compra) AS numero_entregas,
       ROUND(AVG(c.temperatura), 2) AS temperatura_promedio,
       ROUND(AVG(c.acidez), 2) AS acidez_promedio,
       SUM(CASE WHEN c.estado_calidad = 'RECHAZADO' THEN 1 ELSE 0 END) AS entregas_rechazadas,
       ROUND(100 * SUM(CASE WHEN c.estado_calidad = 'RECHAZADO' THEN 1 ELSE 0 END) / COUNT(c.id_compra), 2) AS porcentaje_rechazo
  FROM compras_insumo c
  JOIN insumos i ON i.id_insumo = c.id_insumo AND i.requiere_calidad = 1
  JOIN proveedores pr ON pr.id_proveedor = c.id_proveedor
 WHERE c.estado = 'VIGENTE'
 GROUP BY pr.id_proveedor, pr.nombre
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_lotes AS
SELECT l.id_lote, l.codigo_lote, l.id_producto, p.nombre AS producto, p.codigo_sku, p.unidad_medida,
       l.fecha_produccion, l.litros_leche_usados, l.cantidad_obtenida,
       fn_rendimiento_pct(l.cantidad_obtenida, l.litros_leche_usados) AS porcentaje_rendimiento,
       l.costo_total, l.costo_insumos, l.costo_total - l.costo_insumos AS costo_leche,
       ROUND((l.costo_total - l.costo_insumos) / l.litros_leche_usados, 2) AS costo_por_litro,
       l.litros_esperados, ROUND(l.litros_leche_usados - l.litros_esperados, 2) AS diferencia_litros,
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

-- El panorama contable completo de la quincena, en una fila.
--   DEVENGADO (lo que se gano o se gasto, se haya cobrado/pagado o no): resultado_estimado
--   CAJA (plata que entro y salio de verdad en la quincena): caja_neta = cobros - pagos a proveedores - gastos
--        - compras de contado. Las compras a credito salen de la caja cuando se pagan.
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
       NVL(cs.castigos, 0)       AS cartera_castigada,
       -- Leche recibida (informativo; tambien esta dentro de las compras)
       NVL(cm.leche_litros, 0)       AS leche_litros,
       NVL(cm.leche_rechazados, 0)   AS leche_litros_rechazados,
       NVL(cm.leche_valor, 0)        AS leche_comprada,
       -- Compras de materias primas y cuentas con los proveedores
       NVL(cm.total, 0)              AS compras_materias_primas,
       NVL(cm.contado, 0)            AS compras_contado,
       NVL(cm.credito, 0)            AS compras_credito,
       NVL(pl.pagado, 0)             AS pagado_proveedores,
       NVL(cm.credito, 0) - NVL(pl.pagado, 0) AS por_pagar_proveedores,
       NVL(pp.pagos, 0)              AS pagos_proveedores_caja,
       -- Costos y gastos
       NVL(lt.costo, 0)          AS costo_produccion,
       NVL(g.gastos, 0)          AS gastos_operativos,
       -- Resultados
       NVL(v.ventas_sin_iva, 0) - NVL(lt.costo, 0) - NVL(g.gastos, 0) - NVL(cs.castigos, 0) AS resultado_estimado,
       NVL(c.cobrado_contado, 0) + NVL(a.abonos, 0) - NVL(pp.pagos, 0) - NVL(g.gastos, 0) - NVL(cm.contado, 0) AS caja_neta
  FROM periodos_quincena p
  LEFT JOIN (SELECT id_periodo, SUM(subtotal_venta) AS ventas_sin_iva, SUM(total_iva) AS iva, SUM(total_venta) AS total,
                    SUM(CASE WHEN tipo_venta = 'CONTADO' THEN total_venta ELSE 0 END) AS contado,
                    SUM(CASE WHEN tipo_venta = 'CREDITO' THEN total_venta ELSE 0 END) AS credito,
                    SUM(saldo_pendiente) AS pendiente
               FROM ventas WHERE estado_pago <> 'ANULADA' GROUP BY id_periodo) v ON v.id_periodo = p.id_periodo
  LEFT JOIN (SELECT vt.id_periodo, SUM(vp.monto) AS cobrado_contado
               FROM ventas_pagos vp JOIN ventas vt ON vt.id_venta = vp.id_venta
              WHERE vt.estado_pago <> 'ANULADA' GROUP BY vt.id_periodo) c ON c.id_periodo = p.id_periodo
  LEFT JOIN (SELECT q.id_periodo, SUM(ab.monto) AS abonos
               FROM abonos_cartera ab JOIN periodos_quincena q ON TRUNC(ab.fecha_abono) BETWEEN q.fecha_inicio AND q.fecha_fin
              GROUP BY q.id_periodo) a ON a.id_periodo = p.id_periodo
  LEFT JOIN (SELECT k.id_periodo,
                    SUM(CASE WHEN i.requiere_calidad = 1 AND k.estado_calidad = 'APROBADO' THEN k.cantidad ELSE 0 END) AS leche_litros,
                    SUM(CASE WHEN i.requiere_calidad = 1 AND k.estado_calidad = 'RECHAZADO' THEN k.cantidad ELSE 0 END) AS leche_rechazados,
                    SUM(CASE WHEN i.requiere_calidad = 1 THEN k.valor_total ELSE 0 END) AS leche_valor,
                    SUM(k.valor_total) AS total,
                    SUM(CASE WHEN k.contado = 1 THEN k.valor_total ELSE 0 END) AS contado,
                    SUM(CASE WHEN k.contado = 0 THEN k.valor_total ELSE 0 END) AS credito
               FROM compras_insumo k JOIN insumos i ON i.id_insumo = k.id_insumo
              WHERE k.estado = 'VIGENTE' GROUP BY k.id_periodo) cm ON cm.id_periodo = p.id_periodo
  LEFT JOIN (SELECT id_periodo_liquidado AS id_periodo, SUM(monto) AS pagado FROM pagos_proveedor WHERE estado = 'VIGENTE'
              GROUP BY id_periodo_liquidado) pl ON pl.id_periodo = p.id_periodo
  LEFT JOIN (SELECT id_periodo, SUM(monto) AS pagos FROM pagos_proveedor WHERE estado = 'VIGENTE'
              GROUP BY id_periodo) pp ON pp.id_periodo = p.id_periodo
  LEFT JOIN (SELECT q.id_periodo, SUM(lt2.costo_total) AS costo
               FROM produccion_lotes lt2 JOIN periodos_quincena q ON lt2.fecha_produccion BETWEEN q.fecha_inicio AND q.fecha_fin
              GROUP BY q.id_periodo) lt ON lt.id_periodo = p.id_periodo
  LEFT JOIN (SELECT id_periodo, SUM(monto) AS gastos FROM gastos_operativos WHERE estado = 'VIGENTE' GROUP BY id_periodo) g ON g.id_periodo = p.id_periodo
  LEFT JOIN (SELECT q.id_periodo, SUM(vc.monto_castigado) AS castigos
               FROM ventas vc JOIN periodos_quincena q ON TRUNC(NVL(vc.fecha_castigo, vc.fecha_venta)) BETWEEN q.fecha_inicio AND q.fecha_fin
              WHERE vc.monto_castigado > 0
              GROUP BY q.id_periodo) cs ON cs.id_periodo = p.id_periodo
WITH READ ONLY;

-- El castigo de cartera cuenta en la quincena en que se registra (fecha_castigo), no en la de la venta.
CREATE OR REPLACE VIEW vw_resultado_periodo AS
SELECT p.id_periodo, p.anio, p.mes, p.quincena, p.estado,
       NVL(v.ingresos, 0)   AS ingresos_ventas,
       NVL(l.costo, 0)      AS costo_produccion,
       NVL(g.gastos, 0)     AS gastos_operativos,
       NVL(cs.castigos, 0)  AS cartera_castigada,
       NVL(v.ingresos, 0) - NVL(l.costo, 0) - NVL(g.gastos, 0) - NVL(cs.castigos, 0) AS resultado_estimado
  FROM periodos_quincena p
  LEFT JOIN (SELECT id_periodo, SUM(subtotal_venta) AS ingresos
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
LEFT JOIN (SELECT q.id_periodo, SUM(vc.monto_castigado) AS castigos
               FROM ventas vc JOIN periodos_quincena q ON TRUNC(NVL(vc.fecha_castigo, vc.fecha_venta)) BETWEEN q.fecha_inicio AND q.fecha_fin
              WHERE vc.monto_castigado > 0
              GROUP BY q.id_periodo) cs ON cs.id_periodo = p.id_periodo
WITH READ ONLY;

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
SELECT 'PAGO_PROVEEDOR', p.id_pago, 'PAGO_PROVEEDOR #' || p.id_pago, 'EGRESO', 1,
       p.fecha_pago, p.monto,
       p.id_proveedor, 'PROVEEDOR', p.proveedor,
       'Pago a proveedor, quincena ' || p.quincena || ' / ' || p.mes || ' / ' || p.anio,
       p.metodo_pago, p.referencia_pago,
       CASE WHEN p.estado = 'ANULADO' THEN 'ANULADO' ELSE 'VIGENTE' END, p.motivo_anulacion,
       p.id_periodo, p.usuario_registro
  FROM vw_pagos_proveedor p
UNION ALL
SELECT 'COMPRA', c.id_compra, 'COMPRA #' || c.id_compra, 'EGRESO', c.contado,
       c.fecha, c.valor_total,
       c.id_proveedor, CASE WHEN c.id_proveedor IS NOT NULL THEN 'PROVEEDOR' END, NVL(c.proveedor, c.comprado_en),
       'Compra de ' || RTRIM(TO_CHAR(c.cantidad, 'FM99999999990.999'), '.') || ' ' || c.unidad_medida || ' de ' || c.insumo,
       CAST(NULL AS VARCHAR2(20)), c.referencia,
       CASE WHEN c.estado = 'ANULADA' THEN 'ANULADO' ELSE 'VIGENTE' END, c.motivo_anulacion,
       c.id_periodo, c.usuario_registro
  FROM vw_compras_insumo c WHERE c.estado_calidad = 'APROBADO'
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

CREATE OR REPLACE VIEW vw_notificaciones AS
WITH hoy AS (SELECT TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)) AS d FROM dual)
-- Materias primas (insumos y leche)
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
   AND pkg_modulos.fn_modulo_activo('CREDITO') = 1   -- sin el modulo CREDITO no hay alertas de cartera
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
   AND pkg_modulos.fn_modulo_activo('CREDITO') = 1
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
-- Compras a credito de quincenas ya terminadas que no se han pagado completas a los proveedores
SELECT 'PROVEEDORES_POR_PAGAR:' || c.id_periodo, 'PROVEEDORES_POR_PAGAR', 'ADVERTENCIA',
       'Proveedores por pagar: quincena ' || c.quincena || ' / ' || c.mes || ' / ' || c.anio,
       'Faltan $' || TO_CHAR(c.por_pagar_proveedores, 'FM999G999G999G990', 'NLS_NUMERIC_CHARACTERS='',.''') || ' a los proveedores.',
       'PERIODO', c.id_periodo, c.fecha_fin
  FROM vw_cuentas_quincena c CROSS JOIN hoy h
 WHERE c.fecha_fin < h.d AND c.por_pagar_proveedores > 0
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

-- pkg_documentos (cola legada de documentos para Drive): RECEPCION_LECHE desaparece; la entrega de leche es ahora una COMPRA.
CREATE OR REPLACE PACKAGE BODY pkg_documentos AS

    PROCEDURE sp_registrar_pendiente(
        p_tipo_entidad  IN  VARCHAR2,
        p_id_entidad    IN  NUMBER,
        p_nombre        IN  VARCHAR2,
        p_mime_type     IN  VARCHAR2,
        p_id_documento  OUT NUMBER
    ) IS
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_tipo_entidad IS NULL OR p_tipo_entidad NOT IN ('FACTURA', 'NOTA_CREDITO', 'COMPRA')
           OR p_id_entidad IS NULL OR p_nombre IS NULL OR LENGTH(TRIM(p_nombre)) < 3 OR LENGTH(p_nombre) > 255
           OR p_mime_type IS NULL OR LENGTH(p_mime_type) > 100 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Datos del documento invalidos.');
        END IF;
        -- El trigger trg_documentos_valida_entidad comprueba que la entidad exista.
        INSERT INTO documentos_repositorio (tipo_entidad, id_entidad, nombre_archivo, mime_type, usuario_carga)
        VALUES (p_tipo_entidad, p_id_entidad, TRIM(p_nombre), p_mime_type, v_usuario)
        RETURNING id_documento INTO p_id_documento;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_documento := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_pendiente', p_tipo_entidad || ' id=' || p_id_entidad);
    END sp_registrar_pendiente;

    PROCEDURE sp_marcar_subido(
        p_id_documento  IN NUMBER,
        p_drive_file_id IN VARCHAR2,
        p_drive_url     IN VARCHAR2,
        p_checksum      IN VARCHAR2
    ) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_documento IS NULL OR p_drive_file_id IS NULL OR LENGTH(p_drive_file_id) > 150
           OR (p_checksum IS NOT NULL AND NOT REGEXP_LIKE(p_checksum, '^[A-Fa-f0-9]{64}$')) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Datos de la carga invalidos.');
        END IF;
        UPDATE documentos_repositorio
           SET estado_carga = 'SUBIDO', drive_file_id = p_drive_file_id, drive_url = p_drive_url,
               checksum_sha256 = LOWER(p_checksum), ultimo_error = NULL, fecha_carga = SYSTIMESTAMP,
               intentos = intentos + 1
         WHERE id_documento = p_id_documento AND estado_carga IN ('PENDIENTE', 'ERROR');
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'El documento no existe o ya fue marcado como subido.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_marcar_subido', 'id_documento=' || p_id_documento);
    END sp_marcar_subido;

    PROCEDURE sp_marcar_error(p_id_documento IN NUMBER, p_mensaje IN VARCHAR2) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_documento IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El documento es obligatorio.');
        END IF;
        UPDATE documentos_repositorio
           SET estado_carga = 'ERROR', ultimo_error = SUBSTR(p_mensaje, 1, 500), intentos = intentos + 1
         WHERE id_documento = p_id_documento AND estado_carga IN ('PENDIENTE', 'ERROR');
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'El documento no existe o ya fue marcado como subido.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_marcar_error', 'id_documento=' || p_id_documento);
    END sp_marcar_error;

END pkg_documentos;
/
SHOW ERRORS

-- ============ 5. Se retira lo anterior ============
DECLARE
    PROCEDURE soltar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-942, -4043, -4080, -1418, -12003, -904) THEN RAISE; END IF;
    END;
BEGIN
    soltar('DROP VIEW vw_recepciones');
    soltar('DROP VIEW vw_resumen_pago_lecheros');
    soltar('DROP TRIGGER trg_recepcion_guard');
    soltar('DROP TABLE recepcion_leche CASCADE CONSTRAINTS');
    soltar('DROP PACKAGE pkg_acopio');
    soltar('DROP FUNCTION fn_precio_litro');
END;
/
DECLARE
    n NUMBER;
BEGIN
    SELECT COUNT(*) INTO n FROM user_tab_columns WHERE table_name = 'PROVEEDORES' AND column_name = 'TIPO_PROVEEDOR';
    IF n > 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE proveedores DROP COLUMN tipo_proveedor';
    END IF;
END;
/

-- ============ 6. Permisos ============
GRANT SELECT ON vw_proveedores                TO __ROL_APP__;
GRANT SELECT ON vw_insumos                    TO __ROL_APP__;
GRANT SELECT ON vw_compras_insumo             TO __ROL_APP__;
GRANT SELECT ON vw_precios_proveedor          TO __ROL_APP__;
GRANT SELECT ON vw_resumen_pagos_proveedores  TO __ROL_APP__;
GRANT SELECT ON vw_saldo_proveedores          TO __ROL_APP__;
GRANT SELECT ON vw_calidad_leche_proveedor    TO __ROL_APP__;
GRANT SELECT ON vw_lotes                      TO __ROL_APP__;
GRANT SELECT ON vw_cuentas_quincena           TO __ROL_APP__;
GRANT SELECT ON vw_comprobantes               TO __ROL_APP__;
GRANT SELECT ON vw_notificaciones             TO __ROL_APP__;
GRANT EXECUTE ON pkg_insumos                  TO __ROL_APP__;
GRANT EXECUTE ON pkg_produccion               TO __ROL_APP__;
GRANT EXECUTE ON pkg_pagos_proveedor          TO __ROL_APP__;
GRANT EXECUTE ON pkg_catalogos                TO __ROL_APP__;

-- ============ 7. Verificacion ============
SET PAGESIZE 100 LINESIZE 160
COLUMN object_name FORMAT A34
COLUMN object_type FORMAT A16
SELECT object_type, object_name, status FROM user_objects WHERE status = 'INVALID' ORDER BY 1, 2;
SELECT codigo, nombre, unidad_medida, requiere_calidad FROM insumos WHERE requiere_calidad = 1;
EXIT
