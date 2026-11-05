-- =====================================================================
-- 05 - Datos de la empresa y modulos activables
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1, DESPUES de 02. Lo aplica migrar.sh. Va con el numero 05 (y no al final)
-- porque 10 y 26 llaman a pkg_modulos: el orden numerico es el orden de aplicacion. Reejecutable (no pisa el estado de los
-- modulos ni la fila de empresa).
--
--  * empresa: UNA sola fila con los datos de la empresa (nombre, NIT, direccion...). Sin logo binario por ahora:
--    un BLOB en la base y en cada respuesta pesa mas de lo que aporta; si se quiere, se agrega despues como archivo
--    cifrado (modulo ARCHIVOS) referenciado desde aqui.
--  * modulos: UNA sola tabla con el catalogo y su estado (codigo, nombre, descripcion, si es del nucleo, activo, quien y
--    cuando lo cambio). Se unifico en una tabla (y no en modulos + modulos_empresa) porque el esquema ya ES la empresa:
--    una base por empresa, asi que no hay relacion muchos-a-muchos que modelar. Los modulos del nucleo no se pueden apagar (CHECK).
--  * REGLA: los modulos y los datos de la empresa los cambia el DUENO del sistema (sql/modulos.sh y sql/empresa.sh, entrando
--    como dueno por proxy). La cuenta de la aplicacion solo recibe SELECT sobre vistas: ni tablas ni paquetes de cambio.
--  * pkg_modulos.fn_modulo_activo / sp_exigir_modulo: para que los paquetes de escritura de los modulos opcionales se
--    nieguen tambien en la base (defensa en profundidad; el backend ya bloquea la ruta). Error: ORA-20020 (MODULO_INACTIVO).
--    NO se concede EXECUTE sobre pkg_modulos a la app: los paquetes (AUTHID DEFINER) y las vistas lo ejecutan por ella.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            -- ya existe: tabla/indice (955), columna (1430), PK/UK (2260/2261), nombre de restriccion (2264), FK (2275)
            IF SQLCODE NOT IN (-955, -1430, -2260, -2261, -2264, -2275) THEN RAISE; END IF;
    END;
BEGIN
    ejecutar(q'~
CREATE TABLE empresa (
    id_empresa      NUMBER(1)          DEFAULT 1 NOT NULL,
    nombre          VARCHAR2(120 CHAR) NOT NULL,
    nombre_corto    VARCHAR2(40 CHAR)  NOT NULL,
    nit             VARCHAR2(30 CHAR),
    direccion       VARCHAR2(200 CHAR),
    telefono        VARCHAR2(40 CHAR),
    ciudad          VARCHAR2(80 CHAR),
    correo_contacto VARCHAR2(150 CHAR),
    fecha_cambio    TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    usuario_cambio  VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT('USERENV', 'PROXY_USER'), SYS_CONTEXT('USERENV', 'SESSION_USER')) NOT NULL,
    CONSTRAINT pk_empresa PRIMARY KEY (id_empresa),
    CONSTRAINT ck_empresa_unica CHECK (id_empresa = 1),
    CONSTRAINT ck_empresa_nombre CHECK (nombre = TRIM(nombre) AND nombre_corto = TRIM(nombre_corto)
                                        AND LENGTH(nombre) >= 2 AND LENGTH(nombre_corto) >= 2)
)~');

    ejecutar(q'~
CREATE TABLE modulos (
    codigo         VARCHAR2(30 CHAR)  NOT NULL,
    nombre         VARCHAR2(80 CHAR)  NOT NULL,
    descripcion    VARCHAR2(400 CHAR) NOT NULL,
    nucleo         NUMBER(1)          DEFAULT 0 NOT NULL,
    activo         NUMBER(1)          DEFAULT 1 NOT NULL,
    orden          NUMBER(3)          NOT NULL,
    fecha_cambio   TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    usuario_cambio VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT('USERENV', 'PROXY_USER'), SYS_CONTEXT('USERENV', 'SESSION_USER')) NOT NULL,
    CONSTRAINT pk_modulos PRIMARY KEY (codigo),
    CONSTRAINT ck_modulos_codigo CHECK (REGEXP_LIKE(codigo, '^[A-Z][A-Z0-9_]*$')),
    CONSTRAINT ck_modulos_flags CHECK (nucleo IN (0, 1) AND activo IN (0, 1)),
    -- El nucleo no se puede apagar.
    CONSTRAINT ck_modulos_nucleo_activo CHECK (nucleo = 0 OR activo = 1)
)~');
END;
/

-- ---------- Auditoria y reglas (en la base: tambien valen si alguien edita por SQL) ----------
CREATE OR REPLACE TRIGGER trg_empresa_cambio
BEFORE INSERT OR UPDATE ON empresa
FOR EACH ROW
BEGIN
    :NEW.fecha_cambio   := SYSTIMESTAMP;
    :NEW.usuario_cambio := NVL(SYS_CONTEXT('USERENV', 'PROXY_USER'), SYS_CONTEXT('USERENV', 'SESSION_USER'));
END trg_empresa_cambio;
/
CREATE OR REPLACE TRIGGER trg_aud_empresa
AFTER UPDATE ON empresa
FOR EACH ROW
BEGIN
    IF :OLD.nombre <> :NEW.nombre THEN
        pkg_auditoria.sp_registrar('EMPRESA', '1', 'NOMBRE', :OLD.nombre, :NEW.nombre);
    END IF;
    IF :OLD.nombre_corto <> :NEW.nombre_corto THEN
        pkg_auditoria.sp_registrar('EMPRESA', '1', 'NOMBRE_CORTO', :OLD.nombre_corto, :NEW.nombre_corto);
    END IF;
    IF NVL(:OLD.nit, '~') <> NVL(:NEW.nit, '~') THEN
        pkg_auditoria.sp_registrar('EMPRESA', '1', 'NIT', :OLD.nit, :NEW.nit);
    END IF;
    IF NVL(:OLD.direccion, '~') <> NVL(:NEW.direccion, '~') THEN
        pkg_auditoria.sp_registrar('EMPRESA', '1', 'DIRECCION', :OLD.direccion, :NEW.direccion);
    END IF;
    IF NVL(:OLD.telefono, '~') <> NVL(:NEW.telefono, '~') THEN
        pkg_auditoria.sp_registrar('EMPRESA', '1', 'TELEFONO', :OLD.telefono, :NEW.telefono);
    END IF;
    IF NVL(:OLD.ciudad, '~') <> NVL(:NEW.ciudad, '~') THEN
        pkg_auditoria.sp_registrar('EMPRESA', '1', 'CIUDAD', :OLD.ciudad, :NEW.ciudad);
    END IF;
    IF NVL(:OLD.correo_contacto, '~') <> NVL(:NEW.correo_contacto, '~') THEN
        pkg_auditoria.sp_registrar('EMPRESA', '1', 'CORREO_CONTACTO', :OLD.correo_contacto, :NEW.correo_contacto);
    END IF;
END trg_aud_empresa;
/
CREATE OR REPLACE TRIGGER trg_empresa_nodelete
BEFORE DELETE ON empresa
BEGIN
    RAISE_APPLICATION_ERROR(-20011, 'La fila de la empresa no se borra; se edita con sql/empresa.sh.');
END trg_empresa_nodelete;
/
CREATE OR REPLACE TRIGGER trg_modulos_cambio
BEFORE UPDATE OF activo ON modulos
FOR EACH ROW
BEGIN
    IF :OLD.activo <> :NEW.activo THEN
        :NEW.fecha_cambio   := SYSTIMESTAMP;
        :NEW.usuario_cambio := NVL(SYS_CONTEXT('USERENV', 'PROXY_USER'), SYS_CONTEXT('USERENV', 'SESSION_USER'));
    END IF;
END trg_modulos_cambio;
/
CREATE OR REPLACE TRIGGER trg_aud_modulos
AFTER UPDATE OF activo ON modulos
FOR EACH ROW
BEGIN
    IF :OLD.activo <> :NEW.activo THEN
        pkg_auditoria.sp_registrar('MODULOS', :NEW.codigo, 'ACTIVO', TO_CHAR(:OLD.activo), TO_CHAR(:NEW.activo));
    END IF;
END trg_aud_modulos;
/
CREATE OR REPLACE TRIGGER trg_modulos_nodelete
BEFORE DELETE ON modulos
BEGIN
    RAISE_APPLICATION_ERROR(-20011, 'Los modulos no se borran: se activan o desactivan con sql/modulos.sh.');
END trg_modulos_nodelete;
/

-- ---------- Catalogo (reejecutable: refresca nombre/descripcion; NO toca "activo" de lo que ya existe) ----------
-- Una empresa nueva nace con TODOS los modulos activos (es lo que tiene Llanolat).
MERGE INTO modulos m
USING (
    SELECT 'CREDITO' codigo, 'Credito y cartera' nombre, 0 nucleo, 10 orden,
           'Ventas a credito, cartera, abonos, castigos, edades de cartera y limite de credito del cliente.' descripcion FROM dual UNION ALL
    SELECT 'PRECIOS_CLIENTE', 'Precios por cliente', 0, 20,
           'Precios pactados por cliente: la venta los usa en lugar del precio de lista.' FROM dual UNION ALL
    SELECT 'CALIDAD_LECHE', 'Calidad de la leche', 0, 30,
           'Temperatura, acidez y rechazo de la leche al recibirla; umbrales y calidad por proveedor.' FROM dual UNION ALL
    SELECT 'MARGEN', 'Margen', 0, 40,
           'Reporte de margen por producto y por cliente.' FROM dual UNION ALL
    SELECT 'ARCHIVOS', 'Archivos', 0, 50,
           'Archivos subidos por el ADMIN, carpetas y copia en Google Drive. Los PDF de comprobantes son del nucleo.' FROM dual UNION ALL
    SELECT 'ASISTENTE', 'Asistente de IA', 0, 60,
           'Asistente de ayuda de solo lectura (n8n).' FROM dual UNION ALL
    SELECT 'VENTAS_CONTADO', 'Ventas de contado', 1, 100, 'Registro y anulacion de ventas de contado.' FROM dual UNION ALL
    SELECT 'CATALOGOS', 'Catalogos', 1, 110, 'Clientes, proveedores y productos.' FROM dual UNION ALL
    SELECT 'INVENTARIO', 'Inventario', 1, 120, 'Existencias y alertas de caducidad.' FROM dual UNION ALL
    SELECT 'PRODUCCION', 'Produccion y recetas', 1, 130, 'Lotes de produccion y recetas.' FROM dual UNION ALL
    SELECT 'MATERIAS_PRIMAS', 'Materias primas y proveedores', 1, 140, 'Compras, cuentas y pagos con proveedores.' FROM dual UNION ALL
    SELECT 'GASTOS', 'Gastos', 1, 150, 'Gastos y sus categorias.' FROM dual UNION ALL
    SELECT 'PERIODOS', 'Periodos', 1, 160, 'Quincenas y su cierre.' FROM dual UNION ALL
    SELECT 'COMPROBANTES', 'Comprobantes', 1, 170, 'Comprobantes de cada movimiento y sus PDF.' FROM dual UNION ALL
    SELECT 'TABLERO', 'Tablero y notificaciones', 1, 180, 'Tablero de control y campana de alertas.' FROM dual UNION ALL
    SELECT 'USUARIOS', 'Usuarios y seguridad', 1, 190, 'Usuarios, segundo factor, passkeys, sesiones y mi cuenta.' FROM dual UNION ALL
    SELECT 'AUDITORIA', 'Auditoria y parametros', 1, 200, 'Bitacora de accesos y cambios, y parametros del sistema.' FROM dual
) s ON (m.codigo = s.codigo)
WHEN MATCHED THEN UPDATE SET m.nombre = s.nombre, m.descripcion = s.descripcion, m.nucleo = s.nucleo, m.orden = s.orden
WHEN NOT MATCHED THEN INSERT (codigo, nombre, descripcion, nucleo, orden, activo)
     VALUES (s.codigo, s.nombre, s.descripcion, s.nucleo, s.orden, 1);
COMMIT;

-- ---------- pkg_modulos ----------
CREATE OR REPLACE PACKAGE pkg_modulos AUTHID DEFINER AS
    -- ORA-20020: la funcion existe en el sistema pero el dueno la apago para esta empresa.
    c_modulo_inactivo CONSTANT PLS_INTEGER := -20020;
    -- 1 si el modulo esta activo, 0 si no. Un codigo que no existe es un error de programacion (ORA-20001), no un "no".
    FUNCTION  fn_modulo_activo(p_codigo IN VARCHAR2) RETURN NUMBER;
    -- Lanza ORA-20020 si el modulo esta apagado.
    PROCEDURE sp_exigir_modulo(p_codigo IN VARCHAR2);
END pkg_modulos;
/
CREATE OR REPLACE PACKAGE BODY pkg_modulos AS

    FUNCTION fn_modulo_activo(p_codigo IN VARCHAR2) RETURN NUMBER IS
        v_activo NUMBER;
    BEGIN
        SELECT activo INTO v_activo FROM modulos WHERE codigo = p_codigo;
        RETURN v_activo;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Modulo desconocido: ' || p_codigo);
    END fn_modulo_activo;

    PROCEDURE sp_exigir_modulo(p_codigo IN VARCHAR2) IS
    BEGIN
        IF fn_modulo_activo(p_codigo) = 0 THEN
            RAISE_APPLICATION_ERROR(c_modulo_inactivo, 'Esta función no está activa para su empresa.');
        END IF;
    END sp_exigir_modulo;

END pkg_modulos;
/

-- ---------- Vistas de lectura para la app (WITH READ ONLY) ----------
CREATE OR REPLACE VIEW vw_empresa AS
SELECT nombre, nombre_corto, nit, direccion, telefono, ciudad, correo_contacto
  FROM empresa
WITH READ ONLY;

-- Todos los modulos (activos o no) con su marca de nucleo: /empresa los lista; el dashboard decide que mostrar.
CREATE OR REPLACE VIEW vw_modulos AS
SELECT codigo, nombre, descripcion, nucleo, activo, orden, fecha_cambio
  FROM modulos
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_modulos_activos AS
SELECT codigo, nombre, nucleo, orden
  FROM modulos
 WHERE activo = 1
WITH READ ONLY;

-- Solo SELECT sobre las vistas. NADA de escritura ni EXECUTE sobre pkg_modulos para la app.
GRANT SELECT ON vw_empresa         TO __ROL_APP__;
GRANT SELECT ON vw_modulos         TO __ROL_APP__;
GRANT SELECT ON vw_modulos_activos TO __ROL_APP__;

-- Verificacion: todo debe estar VALID
SELECT object_name, object_type, status FROM user_objects
 WHERE status <> 'VALID' AND object_name IN
   ('EMPRESA', 'MODULOS', 'PKG_MODULOS', 'VW_EMPRESA', 'VW_MODULOS', 'VW_MODULOS_ACTIVOS',
    'TRG_EMPRESA_CAMBIO', 'TRG_AUD_EMPRESA', 'TRG_EMPRESA_NODELETE', 'TRG_MODULOS_CAMBIO', 'TRG_AUD_MODULOS', 'TRG_MODULOS_NODELETE');
SHOW ERRORS
