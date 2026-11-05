-- =====================================================================
-- 10 - Ventas y Cartera: precios pactados por cliente, pagos mixtos y fecha de Colombia
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Reejecutable. Va DESPUES de 02, 06, 07, 08 y 09.
--
--  * precios_cliente / pkg_precios: precio pactado con un cliente para un producto (solo ADMIN lo fija).
--    Si existe, la venta lo usa en lugar del precio de lista; la linea guarda ambos (precio_lista).
--  * ventas_pagos: una venta de CONTADO puede pagarse con varios medios (efectivo + transferencia...);
--    los pagos deben sumar exactamente el total. Solo insercion.
--  * pkg_ventas: sp_registrar_venta recibe ahora p_pagos_json y aplica los precios pactados.
--  * La fecha de la venta y del abono es la de COLOMBIA (antes SYSDATE, que es UTC): de noche, una venta
--    caia en el dia (y la quincena) siguiente. El calculo de dias de mora tambien usa el dia de Colombia.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

CREATE OR REPLACE FUNCTION fn_ahora_colombia RETURN DATE AUTHID DEFINER AS
BEGIN
    RETURN CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE);
END fn_ahora_colombia;
/

DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-955, -1430, -2260, -1408) THEN RAISE; END IF;   -- ya existe
    END;
BEGIN
    ejecutar('ALTER TABLE ventas_detalle ADD (precio_lista NUMBER(12,2))');
    -- Fecha en que se dio por perdida la cartera: el castigo cuenta en la quincena de ESA fecha, no en la de la venta.
    ejecutar('ALTER TABLE ventas ADD (fecha_castigo DATE)');

    ejecutar('
CREATE TABLE precios_cliente (
    id_precio            NUMBER GENERATED ALWAYS AS IDENTITY,
    id_cliente           NUMBER             NOT NULL,
    id_producto          NUMBER             NOT NULL,
    precio               NUMBER(12,2)       NOT NULL,
    activo               NUMBER(1)          DEFAULT 1 NOT NULL,
    fecha_creacion       DATE               DEFAULT SYSDATE NOT NULL,
    usuario_creacion     VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT(''__CTX__'', ''USUARIO''), SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) NOT NULL,
    CONSTRAINT pk_precios_cliente PRIMARY KEY (id_precio),
    CONSTRAINT uk_precios_cliente UNIQUE (id_cliente, id_producto),
    CONSTRAINT fk_precios_cliente_cli FOREIGN KEY (id_cliente) REFERENCES clientes (id_cliente),
    CONSTRAINT fk_precios_cliente_prod FOREIGN KEY (id_producto) REFERENCES productos (id_producto),
    CONSTRAINT ck_precios_cliente_precio CHECK (precio > 0),
    CONSTRAINT ck_precios_cliente_activo CHECK (activo IN (0, 1))
)');

    ejecutar('
CREATE TABLE ventas_pagos (
    id_pago           NUMBER GENERATED ALWAYS AS IDENTITY,
    id_venta          NUMBER             NOT NULL,
    metodo_pago       VARCHAR2(15 CHAR)  NOT NULL,
    monto             NUMBER(12,2)       NOT NULL,
    referencia_pago   VARCHAR2(60 CHAR),
    usuario_registro  VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT(''__CTX__'', ''USUARIO''), SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) NOT NULL,
    fecha_registro    TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    CONSTRAINT pk_ventas_pagos PRIMARY KEY (id_pago),
    CONSTRAINT fk_ventas_pagos_venta FOREIGN KEY (id_venta) REFERENCES ventas (id_venta),
    CONSTRAINT ck_ventas_pagos_metodo CHECK (metodo_pago IN (''EFECTIVO'', ''TRANSFERENCIA'', ''TARJETA'', ''CHEQUE'', ''OTRO'')),
    CONSTRAINT ck_ventas_pagos_monto CHECK (monto > 0)
)');
    ejecutar('CREATE INDEX ix_ventas_pagos_venta ON ventas_pagos (id_venta)');
END;
/

COMMENT ON TABLE precios_cliente IS 'Precio pactado con un cliente para un producto; reemplaza al precio de lista en sus ventas';
COMMENT ON TABLE ventas_pagos IS 'Medios de pago de una venta de contado (solo insercion); suman el total de la venta';
COMMENT ON COLUMN ventas_detalle.precio_lista IS 'Precio de lista del producto al vender (precio_unitario puede ser el pactado con el cliente)';

CREATE OR REPLACE TRIGGER trg_ro_ventas_pagos
BEFORE UPDATE OR DELETE ON ventas_pagos
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los pagos de una venta no pueden modificarse ni eliminarse.');
END trg_ro_ventas_pagos;
/
CREATE OR REPLACE TRIGGER trg_precios_cliente_nodelete
BEFORE DELETE ON precios_cliente
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los precios pactados no se eliminan; se desactivan.');
END trg_precios_cliente_nodelete;
/
CREATE OR REPLACE TRIGGER trg_aud_precios_cliente
AFTER INSERT OR UPDATE OF precio, activo ON precios_cliente
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        pkg_auditoria.sp_registrar('PRECIOS_CLIENTE', TO_CHAR(:NEW.id_precio), 'PRECIO',
                                   NULL, 'cliente=' || :NEW.id_cliente || ';producto=' || :NEW.id_producto || ';precio=' || :NEW.precio);
    ELSE
        IF :OLD.precio <> :NEW.precio THEN
            pkg_auditoria.sp_registrar('PRECIOS_CLIENTE', TO_CHAR(:NEW.id_precio), 'PRECIO', TO_CHAR(:OLD.precio), TO_CHAR(:NEW.precio));
        END IF;
        IF :OLD.activo <> :NEW.activo THEN
            pkg_auditoria.sp_registrar('PRECIOS_CLIENTE', TO_CHAR(:NEW.id_precio), 'ACTIVO', TO_CHAR(:OLD.activo), TO_CHAR(:NEW.activo));
        END IF;
    END IF;
END trg_aud_precios_cliente;
/

CREATE OR REPLACE PACKAGE pkg_precios AUTHID DEFINER AS
    -- Solo ADMIN. Crea o actualiza el precio pactado (y lo deja activo).
    PROCEDURE sp_fijar_precio(p_id_cliente IN NUMBER, p_id_producto IN NUMBER, p_precio IN NUMBER, p_id_precio OUT NUMBER);
    PROCEDURE sp_quitar_precio(p_id_cliente IN NUMBER, p_id_producto IN NUMBER);
END pkg_precios;
/
CREATE OR REPLACE PACKAGE BODY pkg_precios AS

    PROCEDURE sp_fijar_precio(p_id_cliente IN NUMBER, p_id_producto IN NUMBER, p_precio IN NUMBER, p_id_precio OUT NUMBER) IS
        v_n NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        pkg_modulos.sp_exigir_modulo('PRECIOS_CLIENTE');
        IF p_id_cliente IS NULL OR p_id_producto IS NULL OR p_precio IS NULL OR p_precio <= 0 OR p_precio <> ROUND(p_precio, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Cliente, producto y un precio mayor a cero (maximo 2 decimales) son obligatorios.');
        END IF;
        SELECT COUNT(*) INTO v_n FROM clientes WHERE id_cliente = p_id_cliente AND activo = 1;
        IF v_n = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe o esta inactivo.');
        END IF;
        SELECT COUNT(*) INTO v_n FROM productos WHERE id_producto = p_id_producto AND activo = 1;
        IF v_n = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe o esta inactivo.');
        END IF;
        UPDATE precios_cliente SET precio = p_precio, activo = 1
         WHERE id_cliente = p_id_cliente AND id_producto = p_id_producto
        RETURNING id_precio INTO p_id_precio;
        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO precios_cliente (id_cliente, id_producto, precio)
            VALUES (p_id_cliente, p_id_producto, p_precio)
            RETURNING id_precio INTO p_id_precio;
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_precio := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_fijar_precio', 'cliente=' || p_id_cliente || ';producto=' || p_id_producto);
    END sp_fijar_precio;

    PROCEDURE sp_quitar_precio(p_id_cliente IN NUMBER, p_id_producto IN NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        pkg_modulos.sp_exigir_modulo('PRECIOS_CLIENTE');
        UPDATE precios_cliente SET activo = 0
         WHERE id_cliente = p_id_cliente AND id_producto = p_id_producto AND activo = 1;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'No hay un precio pactado activo para ese cliente y producto.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_quitar_precio', 'cliente=' || p_id_cliente || ';producto=' || p_id_producto);
    END sp_quitar_precio;

END pkg_precios;
/

-- ---------- Vistas ----------
CREATE OR REPLACE VIEW vw_precios_cliente AS
SELECT pc.id_precio, pc.id_cliente, c.nombre AS cliente, pc.id_producto, p.codigo_sku, p.nombre AS producto,
       p.unidad_medida, pc.precio, p.precio_base, pc.precio - p.precio_base AS diferencia, pc.activo,
       pc.fecha_creacion
  FROM precios_cliente pc
  JOIN clientes c ON c.id_cliente = pc.id_cliente
  JOIN productos p ON p.id_producto = pc.id_producto
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_ventas_pagos AS
SELECT g.id_pago, g.id_venta, v.id_cliente, v.fecha_venta, v.estado_pago AS estado_venta,
       g.metodo_pago, g.monto, g.referencia_pago, g.usuario_registro, g.fecha_registro
  FROM ventas_pagos g
  JOIN ventas v ON v.id_venta = g.id_venta
WITH READ ONLY;

-- Detalle de venta con el precio de lista (para mostrar «precio pactado»)
CREATE OR REPLACE VIEW vw_ventas_lineas AS
SELECT d.id_detalle, d.id_venta, d.id_producto, p.codigo_sku, p.nombre AS producto, p.unidad_medida,
       d.cantidad, d.precio_unitario, d.precio_lista, d.tarifa_iva, d.subtotal, d.valor_iva,
       d.subtotal + d.valor_iva AS total_linea
  FROM ventas_detalle d
  JOIN productos p ON p.id_producto = d.id_producto
WITH READ ONLY;

-- Dias de mora con el dia de Colombia
CREATE OR REPLACE VIEW vw_dashboard_cartera AS
SELECT c.id_cliente, c.nombre AS cliente, c.telefono, c.limite_credito, c.saldo_deudor,
       c.limite_credito - c.saldo_deudor AS cupo_disponible,
       NVL(m.dias_mora, 0) AS dias_mora,
       fn_estado_credito(c.limite_credito, c.saldo_deudor, NVL(m.dias_mora, 0)) AS estado_credito
  FROM clientes c
  LEFT JOIN (SELECT v.id_cliente, MAX(TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE)) - v.fecha_vencimiento) AS dias_mora
               FROM ventas v
              WHERE v.estado_pago = 'PENDIENTE'
                AND v.fecha_vencimiento < TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE))
              GROUP BY v.id_cliente) m ON m.id_cliente = c.id_cliente
 WHERE c.activo = 1
WITH READ ONLY;

-- ---------- Paquetes con el cambio ----------
CREATE OR REPLACE PACKAGE pkg_ventas AUTHID DEFINER AS
    PROCEDURE sp_registrar_venta(
        p_id_cliente  IN  NUMBER,
        p_tipo_venta  IN  VARCHAR2,
        p_lineas_json IN  CLOB,
        -- Pagos de una venta de CONTADO: [{"metodo_pago":"EFECTIVO","monto":50000,"referencia":null}, ...]
        -- (varios medios en una venta; deben sumar EXACTAMENTE el total). En CREDITO debe ir NULL o [].
        p_pagos_json  IN  CLOB,
        p_id_venta    OUT NUMBER,
        p_total_venta OUT NUMBER
    );

    PROCEDURE sp_anular_venta(p_id_venta IN NUMBER, p_motivo IN VARCHAR2);
END pkg_ventas;
/
CREATE OR REPLACE PACKAGE BODY pkg_ventas AS

    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    TYPE t_vc  IS TABLE OF VARCHAR2(60 CHAR) INDEX BY PLS_INTEGER;

    PROCEDURE sp_registrar_venta(
        p_id_cliente  IN  NUMBER,
        p_tipo_venta  IN  VARCHAR2,
        p_lineas_json IN  CLOB,
        p_pagos_json  IN  CLOB,
        p_id_venta    OUT NUMBER,
        p_total_venta OUT NUMBER
    ) IS
        v_ids        t_num;   -- productos solicitados (agrupados, ordenados)
        v_lock_ids   sys.odcinumberlist;  -- CORRECCION: tipo SQL para TABLE()
        v_cant       t_num;   -- cantidades solicitadas
        v_inval      t_num;   -- lineas con cantidad nula o no positiva
        v_p_id       t_num;   -- productos bloqueados
        v_p_precio   t_num;
        v_p_iva      t_num;
        v_p_stock    t_num;
        v_p_activo   t_num;
        v_sub        t_num;
        v_valor_iva  t_num;
        v_es_json    NUMBER;
        v_max_lineas NUMBER;
        v_subtotal   NUMBER := 0;
        v_iva        NUMBER := 0;
        v_total      NUMBER;
        v_limite     NUMBER;
        v_saldo      NUMBER;
        v_activo     NUMBER;
        v_id_periodo NUMBER;
        -- Hoy es el dia de COLOMBIA (la base esta en UTC: con SYSDATE, de noche la venta caeria en la quincena siguiente).
        v_fecha      DATE := fn_ahora_colombia;
        v_vence      DATE;
        v_estado     VARCHAR2(10);
        v_saldo_pend NUMBER;
        v_usuario    VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
        v_base       t_num;   -- precio de lista de cada linea
        v_especial   t_num;   -- precio pactado con este cliente, indexado por id_producto
        v_pg_metodo  t_vc;
        v_pg_monto   t_num;
        v_pg_ref     t_vc;
        v_suma_pagos NUMBER := 0;
        v_pagos_json NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);

        -- 1. Validacion de parametros
        IF p_id_cliente IS NULL OR p_tipo_venta IS NULL OR p_tipo_venta NOT IN ('CONTADO', 'CREDITO')
           OR p_lineas_json IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Cliente, tipo de venta (CONTADO o CREDITO) y lineas son obligatorios.');
        END IF;
        SELECT CASE WHEN p_lineas_json IS JSON STRICT THEN 1 ELSE 0 END INTO v_es_json FROM dual;
        IF v_es_json = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Las lineas no son un JSON valido.');
        END IF;
        -- Modulo CREDITO: sin el, solo hay ventas de contado (la base tambien se niega, no solo el backend).
        IF p_tipo_venta = 'CREDITO' THEN
            pkg_modulos.sp_exigir_modulo('CREDITO');
        END IF;
        v_max_lineas := pkg_parametros.fn_numero('MAX_LINEAS_DOCUMENTO');

        -- 2. Lineas agrupadas por producto (un solo recorrido del JSON, variables de enlace)
        SELECT jt.id_producto,
               SUM(jt.cantidad),
               SUM(CASE WHEN jt.cantidad IS NULL OR jt.cantidad <= 0
                          OR jt.cantidad <> ROUND(jt.cantidad, 2) THEN 1 ELSE 0 END)
          BULK COLLECT INTO v_ids, v_cant, v_inval
          FROM JSON_TABLE(p_lineas_json, '$[*]'
                 COLUMNS (id_producto NUMBER PATH '$.id_producto',
                          cantidad    NUMBER PATH '$.cantidad')) jt
         GROUP BY jt.id_producto
         ORDER BY jt.id_producto;

        IF v_ids.COUNT = 0 OR v_ids.COUNT > v_max_lineas THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'La venta debe tener entre 1 y ' || v_max_lineas || ' productos.');
        END IF;
        FOR i IN 1 .. v_ids.COUNT LOOP
            IF v_ids(i) IS NULL OR v_inval(i) > 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                    'Cada linea requiere id_producto y una cantidad positiva con maximo 2 decimales.');
            END IF;
        END LOOP;

        -- 3. Bloqueo del cliente (punto de serializacion de la cartera)
        BEGIN
            SELECT limite_credito, saldo_deudor, activo
              INTO v_limite, v_saldo, v_activo
              FROM clientes
             WHERE id_cliente = p_id_cliente
               FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe.');
        END;
        IF v_activo = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'El cliente esta inactivo.');
        END IF;

        -- 4. Bloqueo ordenado de TODOS los productos en una sola consulta (evita N consultas y interbloqueos)
        -- CORRECCION (ORA-01786): FOR UPDATE no admite un JSON_TABLE en el
        -- subquery. Se reutiliza v_ids (ya validada, agrupada y ordenada)
        -- a traves de un tipo de coleccion SQL, que si admite bloqueo.
        v_lock_ids := sys.odcinumberlist();
        v_lock_ids.EXTEND(v_ids.COUNT);
        FOR i IN 1 .. v_ids.COUNT LOOP
            v_lock_ids(i) := v_ids(i);
        END LOOP;

        SELECT p.id_producto, p.precio_base, p.tarifa_iva, p.stock_actual, p.activo
          BULK COLLECT INTO v_p_id, v_p_precio, v_p_iva, v_p_stock, v_p_activo
          FROM productos p
         WHERE p.id_producto IN (SELECT column_value FROM TABLE(v_lock_ids))
         ORDER BY p.id_producto
           FOR UPDATE WAIT 10;

        IF v_p_id.COUNT <> v_ids.COUNT THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'Hay productos que no existen en el catalogo.');
        END IF;

        -- 4b. Precios pactados con ESTE cliente (si no hay, se usa el precio de lista del producto)
        -- Modulo PRECIOS_CLIENTE apagado: se cobra siempre el precio de lista (los acuerdos guardados se conservan).
        IF pkg_modulos.fn_modulo_activo('PRECIOS_CLIENTE') = 1 THEN
            FOR r IN (SELECT pc.id_producto, pc.precio
                        FROM precios_cliente pc
                       WHERE pc.id_cliente = p_id_cliente AND pc.activo = 1
                         AND pc.id_producto IN (SELECT column_value FROM TABLE(v_lock_ids))) LOOP
                v_especial(r.id_producto) := r.precio;
            END LOOP;
        END IF;

        -- 5. Calculo en memoria (sin SQL dentro del bucle)
        FOR i IN 1 .. v_ids.COUNT LOOP
            IF v_p_id(i) <> v_ids(i) THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'Hay productos que no existen en el catalogo.');
            END IF;
            IF v_p_activo(i) = 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                    'El producto ' || v_ids(i) || ' esta inactivo.');
            END IF;
            IF v_p_stock(i) < v_cant(i) THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_stock_insuficiente,
                    'Stock insuficiente del producto ' || v_ids(i) || ': disponible ' || v_p_stock(i) ||
                    ', solicitado ' || v_cant(i) || '.');
            END IF;
            v_base(i) := v_p_precio(i);
            IF v_especial.EXISTS(v_p_id(i)) THEN
                v_p_precio(i) := v_especial(v_p_id(i));
            END IF;
            v_sub(i)       := ROUND(v_cant(i) * v_p_precio(i), 2);
            v_valor_iva(i) := ROUND(v_sub(i) * v_p_iva(i) / 100, 2);
            v_subtotal     := v_subtotal + v_sub(i);
            v_iva          := v_iva + v_valor_iva(i);
        END LOOP;
        v_total := v_subtotal + v_iva;
        IF v_total <= 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El total de la venta debe ser mayor a cero.');
        END IF;

        -- 6. Periodo y credito
        v_id_periodo := pkg_periodos.fn_id_periodo(v_fecha);
        pkg_periodos.sp_validar_abierto(v_id_periodo, v_fecha);

        IF p_tipo_venta = 'CREDITO' THEN
            IF v_saldo + v_total > v_limite THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_limite_credito,
                    'La venta excede el cupo de credito: cupo ' || v_limite || ', deuda ' || v_saldo ||
                    ', venta ' || v_total || '.');
            END IF;
            v_vence      := TRUNC(v_fecha) + pkg_parametros.fn_numero('PLAZO_CREDITO_DIAS');
            v_estado     := 'PENDIENTE';
            v_saldo_pend := v_total;
        ELSE
            v_vence      := NULL;
            v_estado     := 'PAGADA';
            v_saldo_pend := 0;
        END IF;

        -- 6b. Pagos. CONTADO: uno o varios medios que sumen exactamente el total. CREDITO: ninguno (se cobra por Cartera).
        IF p_tipo_venta = 'CONTADO' THEN
            IF p_pagos_json IS NULL THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                    'Una venta de contado necesita al menos un pago (medio y monto).');
            END IF;
            SELECT CASE WHEN p_pagos_json IS JSON STRICT THEN 1 ELSE 0 END INTO v_pagos_json FROM dual;
            IF v_pagos_json = 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Los pagos no son un JSON valido.');
            END IF;
            SELECT jt.metodo_pago, jt.monto, jt.referencia
              BULK COLLECT INTO v_pg_metodo, v_pg_monto, v_pg_ref
              FROM JSON_TABLE(p_pagos_json, '$[*]'
                     COLUMNS (metodo_pago VARCHAR2(15) PATH '$.metodo_pago',
                              monto       NUMBER       PATH '$.monto',
                              referencia  VARCHAR2(60) PATH '$.referencia')) jt;
            IF v_pg_monto.COUNT < 1 OR v_pg_monto.COUNT > 6 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La venta de contado lleva entre 1 y 6 pagos.');
            END IF;
            FOR i IN 1 .. v_pg_monto.COUNT LOOP
                IF v_pg_metodo(i) IS NULL OR v_pg_metodo(i) NOT IN ('EFECTIVO', 'TRANSFERENCIA', 'TARJETA', 'CHEQUE', 'OTRO') THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                        'Medio de pago invalido (EFECTIVO, TRANSFERENCIA, TARJETA, CHEQUE u OTRO).');
                END IF;
                IF v_pg_monto(i) IS NULL OR v_pg_monto(i) <= 0 OR v_pg_monto(i) <> ROUND(v_pg_monto(i), 2) THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                        'Cada pago debe ser mayor a cero con maximo 2 decimales.');
                END IF;
                v_suma_pagos := v_suma_pagos + v_pg_monto(i);
            END LOOP;
            IF v_suma_pagos <> v_total THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                    'Los pagos suman ' || v_suma_pagos || ' y el total de la venta es ' || v_total || '.');
            END IF;
        ELSIF p_pagos_json IS NOT NULL AND DBMS_LOB.GETLENGTH(p_pagos_json) > 0
              AND REGEXP_REPLACE(DBMS_LOB.SUBSTR(p_pagos_json, 20, 1), '\s') <> '[]' THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Una venta a credito no lleva pagos: el cobro se registra como abono en Cartera.');
        END IF;

        -- 7. Escritura por lotes
        INSERT INTO ventas (id_cliente, id_periodo, fecha_venta, tipo_venta, fecha_vencimiento,
                            subtotal_venta, total_iva, total_venta, saldo_pendiente, estado_pago, usuario_registro)
        VALUES (p_id_cliente, v_id_periodo, v_fecha, p_tipo_venta, v_vence,
                v_subtotal, v_iva, v_total, v_saldo_pend, v_estado, v_usuario)
        RETURNING id_venta INTO p_id_venta;

        FORALL i IN 1 .. v_ids.COUNT
            INSERT INTO ventas_detalle (id_venta, id_producto, cantidad, precio_unitario, precio_lista, tarifa_iva, subtotal, valor_iva)
            VALUES (p_id_venta, v_ids(i), v_cant(i), v_p_precio(i), v_base(i), v_p_iva(i), v_sub(i), v_valor_iva(i));

        IF p_tipo_venta = 'CONTADO' THEN
            FORALL i IN 1 .. v_pg_monto.COUNT
                INSERT INTO ventas_pagos (id_venta, metodo_pago, monto, referencia_pago, usuario_registro)
                VALUES (p_id_venta, v_pg_metodo(i), v_pg_monto(i), v_pg_ref(i), v_usuario);
        END IF;

        FORALL i IN 1 .. v_ids.COUNT
            UPDATE productos SET stock_actual = stock_actual - v_cant(i) WHERE id_producto = v_ids(i);

        IF p_tipo_venta = 'CREDITO' THEN
            UPDATE clientes SET saldo_deudor = saldo_deudor + v_total WHERE id_cliente = p_id_cliente;
        END IF;

        p_total_venta := v_total;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_venta := NULL;
            p_total_venta := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_venta',
                                    'id_cliente=' || p_id_cliente || ';tipo=' || p_tipo_venta);
    END sp_registrar_venta;

    PROCEDURE sp_anular_venta(p_id_venta IN NUMBER, p_motivo IN VARCHAR2) IS
        v_ids        t_num;
        v_cant       t_num;
        v_bloq       t_num;
        v_id_cliente NUMBER;
        v_tipo       VARCHAR2(10);
        v_estado     VARCHAR2(10);
        v_saldo_pend NUMBER;
        v_id_periodo NUMBER;
        v_fecha      DATE;
        v_n          NUMBER;
        v_deuda      NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_venta IS NULL OR p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 10 OR LENGTH(p_motivo) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Venta y motivo (10 a 255 caracteres) son obligatorios.');
        END IF;

        -- Orden de bloqueo: cliente -> venta -> productos
        BEGIN
            SELECT id_cliente INTO v_id_cliente FROM ventas WHERE id_venta = p_id_venta;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La venta no existe.');
        END;
        SELECT saldo_deudor INTO v_deuda FROM clientes WHERE id_cliente = v_id_cliente FOR UPDATE WAIT 10;
        SELECT tipo_venta, estado_pago, saldo_pendiente, id_periodo, fecha_venta
          INTO v_tipo, v_estado, v_saldo_pend, v_id_periodo, v_fecha
          FROM ventas WHERE id_venta = p_id_venta FOR UPDATE WAIT 10;

        IF v_estado NOT IN ('PAGADA', 'PENDIENTE') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La venta ya esta ' || v_estado || '.');
        END IF;
        pkg_periodos.sp_validar_abierto(v_id_periodo);

        SELECT COUNT(*) INTO v_n FROM facturas
         WHERE id_venta = p_id_venta AND estado_dian IN ('EN_PROCESO', 'ACEPTADA');
        IF v_n > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'La venta tiene una factura enviada o aceptada por la DIAN: corrija con una nota credito.');
        END IF;
        SELECT COUNT(*) INTO v_n FROM abonos_cartera WHERE id_venta = p_id_venta;
        IF v_n > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'La venta tiene abonos registrados y no puede anularse.');
        END IF;

        -- Devolucion de stock por lotes
        SELECT id_producto, cantidad BULK COLLECT INTO v_ids, v_cant
          FROM ventas_detalle WHERE id_venta = p_id_venta ORDER BY id_producto;

        SELECT id_producto BULK COLLECT INTO v_bloq
          FROM productos
         WHERE id_producto IN (SELECT id_producto FROM ventas_detalle WHERE id_venta = p_id_venta)
         ORDER BY id_producto
           FOR UPDATE WAIT 10;

        FORALL i IN 1 .. v_ids.COUNT
            UPDATE productos SET stock_actual = stock_actual + v_cant(i) WHERE id_producto = v_ids(i);

        IF v_tipo = 'CREDITO' AND v_saldo_pend > 0 THEN
            UPDATE clientes SET saldo_deudor = saldo_deudor - v_saldo_pend WHERE id_cliente = v_id_cliente;
        END IF;

        UPDATE ventas
           SET estado_pago = 'ANULADA', saldo_pendiente = 0, motivo_anulacion = TRIM(p_motivo)
         WHERE id_venta = p_id_venta;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_anular_venta', 'id_venta=' || p_id_venta);
    END sp_anular_venta;

END pkg_ventas;
/

CREATE OR REPLACE PACKAGE pkg_cartera AUTHID DEFINER AS
    PROCEDURE sp_registrar_abono(
        p_id_cliente     IN  NUMBER,
        p_monto          IN  NUMBER,
        p_metodo_pago    IN  VARCHAR2,
        p_referencia     IN  VARCHAR2,
        p_id_recibo      OUT NUMBER,
        p_saldo_restante OUT NUMBER
    );

    PROCEDURE sp_castigar_cartera(
        p_id_cliente     IN  NUMBER,
        p_motivo         IN  VARCHAR2,
        p_monto_castigado OUT NUMBER
    );
END pkg_cartera;
/
CREATE OR REPLACE PACKAGE BODY pkg_cartera AS

    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    PROCEDURE sp_registrar_abono(
        p_id_cliente     IN  NUMBER,
        p_monto          IN  NUMBER,
        p_metodo_pago    IN  VARCHAR2,
        p_referencia     IN  VARCHAR2,
        p_id_recibo      OUT NUMBER,
        p_saldo_restante OUT NUMBER
    ) IS
        v_id_venta  t_num;   -- ventas pendientes, mas antiguas primero
        v_saldo     t_num;
        v_ap_venta  t_num;   -- reparto del abono
        v_ap_monto  t_num;
        v_deuda     NUMBER;
        v_restante  NUMBER;
        v_n         PLS_INTEGER := 0;
        v_usuario   VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pkg_modulos.sp_exigir_modulo('CREDITO');
        IF p_id_cliente IS NULL OR p_monto IS NULL OR p_monto <= 0 OR p_monto <> ROUND(p_monto, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_abono_invalido,
                'El abono debe ser mayor a cero y tener maximo 2 decimales.');
        END IF;
        IF p_metodo_pago IS NULL OR p_metodo_pago NOT IN ('EFECTIVO', 'TRANSFERENCIA', 'TARJETA', 'CHEQUE', 'OTRO') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Metodo de pago invalido.');
        END IF;

        BEGIN
            SELECT saldo_deudor INTO v_deuda FROM clientes WHERE id_cliente = p_id_cliente FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe.');
        END;
        IF p_monto > v_deuda THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_abono_invalido,
                'El abono (' || p_monto || ') excede la deuda del cliente (' || v_deuda || ').');
        END IF;

        -- Una sola lectura, con bloqueo, de todas las ventas pendientes (FIFO)
        SELECT v.id_venta, v.saldo_pendiente
          BULK COLLECT INTO v_id_venta, v_saldo
          FROM ventas v
         WHERE v.id_cliente = p_id_cliente AND v.estado_pago = 'PENDIENTE'
         ORDER BY v.fecha_venta, v.id_venta
           FOR UPDATE WAIT 10;

        -- Reparto en memoria
        v_restante := p_monto;
        FOR i IN 1 .. v_id_venta.COUNT LOOP
            EXIT WHEN v_restante <= 0;
            v_n := v_n + 1;
            v_ap_venta(v_n) := v_id_venta(i);
            v_ap_monto(v_n) := LEAST(v_restante, v_saldo(i));
            v_restante      := v_restante - v_ap_monto(v_n);
        END LOOP;
        IF v_restante > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'Inconsistencia: la deuda del cliente no coincide con sus ventas pendientes. Avise a soporte.');
        END IF;

        p_id_recibo := seq_recibo_caja.NEXTVAL;

        FORALL i IN 1 .. v_n
            INSERT INTO abonos_cartera (id_recibo, id_venta, fecha_abono, monto, metodo_pago, referencia_pago, usuario_registro)
            VALUES (p_id_recibo, v_ap_venta(i), fn_ahora_colombia, v_ap_monto(i), p_metodo_pago, p_referencia, v_usuario);

        FORALL i IN 1 .. v_n
            UPDATE ventas
               SET saldo_pendiente = saldo_pendiente - v_ap_monto(i),
                   estado_pago = CASE WHEN saldo_pendiente - v_ap_monto(i) = 0 THEN 'PAGADA' ELSE 'PENDIENTE' END
             WHERE id_venta = v_ap_venta(i);

        UPDATE clientes SET saldo_deudor = saldo_deudor - p_monto WHERE id_cliente = p_id_cliente;
        p_saldo_restante := v_deuda - p_monto;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_recibo := NULL;
            p_saldo_restante := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_abono', 'id_cliente=' || p_id_cliente || ';monto=' || p_monto);
    END sp_registrar_abono;

    PROCEDURE sp_castigar_cartera(
        p_id_cliente      IN  NUMBER,
        p_motivo          IN  VARCHAR2,
        p_monto_castigado OUT NUMBER
    ) IS
        v_montos t_num;
        v_deuda  NUMBER;
        v_total  NUMBER := 0;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        pkg_modulos.sp_exigir_modulo('CREDITO');
        IF p_id_cliente IS NULL OR p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 10 OR LENGTH(p_motivo) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Cliente y motivo (10 a 255 caracteres) son obligatorios.');
        END IF;

        BEGIN
            SELECT saldo_deudor INTO v_deuda FROM clientes WHERE id_cliente = p_id_cliente FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe.');
        END;

        -- El castigo se registra en la quincena de hoy: esa quincena debe estar abierta (las cerradas no se tocan).
        pkg_periodos.sp_validar_abierto(pkg_periodos.fn_id_periodo(TRUNC(fn_ahora_colombia)), TRUNC(fn_ahora_colombia));

        UPDATE ventas
           SET monto_castigado = saldo_pendiente, saldo_pendiente = 0, estado_pago = 'CASTIGADA',
               fecha_castigo = TRUNC(fn_ahora_colombia)
         WHERE id_cliente = p_id_cliente AND estado_pago = 'PENDIENTE'
        RETURNING monto_castigado BULK COLLECT INTO v_montos;

        FOR i IN 1 .. v_montos.COUNT LOOP
            v_total := v_total + v_montos(i);
        END LOOP;
        IF v_total = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'El cliente no tiene cartera pendiente.');
        END IF;

        UPDATE clientes SET saldo_deudor = saldo_deudor - v_total WHERE id_cliente = p_id_cliente;
        pkg_auditoria.sp_registrar('CLIENTES', TO_CHAR(p_id_cliente), 'CASTIGO_CARTERA',
                                   TO_CHAR(v_total), SUBSTR(TRIM(p_motivo), 1, 400));
        p_monto_castigado := v_total;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_monto_castigado := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_castigar_cartera', 'id_cliente=' || p_id_cliente);
    END sp_castigar_cartera;

END pkg_cartera;
/
-- Cabecera completa de una venta (con motivo de anulacion y castigo)
CREATE OR REPLACE VIEW vw_ventas_completa AS
SELECT v.id_venta, v.id_cliente, c.nombre AS cliente, c.tipo_documento, c.numero_documento, v.id_periodo,
       v.fecha_venta, v.tipo_venta, v.fecha_vencimiento, v.subtotal_venta, v.total_iva, v.total_venta,
       v.saldo_pendiente, v.monto_castigado, v.estado_pago, v.motivo_anulacion, v.usuario_registro, v.fecha_registro
  FROM ventas v
  JOIN clientes c ON c.id_cliente = v.id_cliente
WITH READ ONLY;
GRANT SELECT ON vw_ventas_completa TO __ROL_APP__;

-- Cliente generico para ventas de contado de mostrador sin identificar al comprador
-- (documento 222222222222, el que se usa habitualmente para "consumidor final"). Cupo 0: no compra a credito.
MERGE INTO clientes c
USING (SELECT 'CC' td, '222222222222' nd FROM dual) s
ON (c.tipo_documento = s.td AND c.numero_documento = s.nd)
WHEN NOT MATCHED THEN INSERT (tipo_documento, numero_documento, nombre, limite_credito)
     VALUES ('CC', '222222222222', 'CONSUMIDOR FINAL', 0);
COMMIT;


GRANT EXECUTE ON pkg_precios        TO __ROL_APP__;
GRANT EXECUTE ON pkg_ventas         TO __ROL_APP__;
GRANT EXECUTE ON pkg_cartera        TO __ROL_APP__;
GRANT SELECT  ON vw_precios_cliente TO __ROL_APP__;
GRANT SELECT  ON vw_ventas_pagos    TO __ROL_APP__;
GRANT SELECT  ON vw_ventas_lineas   TO __ROL_APP__;
GRANT SELECT  ON vw_dashboard_cartera TO __ROL_APP__;

SHOW ERRORS
