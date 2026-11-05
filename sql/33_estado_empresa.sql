-- =====================================================================
-- 33 - Estado de la empresa: ACTIVA o SUSPENDIDA
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Lo aplica migrar.sh. Reejecutable.
--
--  * empresa.estado (ACTIVA | SUSPENDIDA), motivo_estado y fecha_estado. Lo cambia SOLO el dueno (sql/empresa.sh
--    suspender | reactivar, por proxy): la app no tiene permiso de escritura sobre la tabla ni sobre ningun paquete que la cambie.
--  * Suspender es REVERSIBLE: no borra ni cambia datos. El backend responde 403 / 20021 (EMPRESA_SUSPENDIDA) a todo menos
--    /empresa/publica, /empresa/logo y /actuator/health, y la base se niega a abrir sesiones de aplicacion
--    (pkg_seguridad.sp_iniciar_sesion -> ORA-20021): ninguna escritura pasa aunque el backend fallara.
--  * vw_empresa expone estado y fecha_estado (no el motivo: es una nota interna del dueno).
--  * La baja definitiva NO esta aqui: es sql/baja_empresa.sh (respaldo + borrado), que exige la empresa SUSPENDIDA.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            -- ya existe: columna (1430), nombre de restriccion (2264)
            IF SQLCODE NOT IN (-1430, -2264) THEN RAISE; END IF;
    END;
BEGIN
    ejecutar(q'~ALTER TABLE empresa ADD (
        estado        VARCHAR2(12 CHAR)  DEFAULT 'ACTIVA' NOT NULL,
        motivo_estado VARCHAR2(300 CHAR),
        fecha_estado  TIMESTAMP)~');
    ejecutar(q'~ALTER TABLE empresa ADD CONSTRAINT ck_empresa_estado CHECK (estado IN ('ACTIVA', 'SUSPENDIDA'))~');
END;
/

COMMENT ON COLUMN empresa.estado IS 'ACTIVA | SUSPENDIDA. Suspendida: el backend responde 403/20021 y la base no abre sesiones de aplicacion. Solo el dueno (sql/empresa.sh).';
COMMENT ON COLUMN empresa.motivo_estado IS 'Nota interna del dueno sobre la suspension (no la ve la empresa).';
COMMENT ON COLUMN empresa.fecha_estado IS 'Ultimo cambio de estado.';

-- ---------- Auditoria: se agregan ESTADO y MOTIVO_ESTADO al trigger de 31 ----------
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
    IF NVL(:OLD.pie_comprobante, '~') <> NVL(:NEW.pie_comprobante, '~') THEN
        pkg_auditoria.sp_registrar('EMPRESA', '1', 'PIE_COMPROBANTE', :OLD.pie_comprobante, :NEW.pie_comprobante);
    END IF;
    IF :OLD.estado <> :NEW.estado THEN
        pkg_auditoria.sp_registrar('EMPRESA', '1', 'ESTADO', :OLD.estado, :NEW.estado);
    END IF;
    IF NVL(:OLD.motivo_estado, '~') <> NVL(:NEW.motivo_estado, '~') THEN
        pkg_auditoria.sp_registrar('EMPRESA', '1', 'MOTIVO_ESTADO', :OLD.motivo_estado, :NEW.motivo_estado);
    END IF;
END trg_aud_empresa;
/

-- fecha_estado la pone la base, no quien actualiza.
CREATE OR REPLACE TRIGGER trg_empresa_estado
BEFORE UPDATE OF estado ON empresa
FOR EACH ROW
WHEN (OLD.estado <> NEW.estado)
BEGIN
    :NEW.fecha_estado := SYSTIMESTAMP;
END trg_empresa_estado;
/

CREATE OR REPLACE VIEW vw_empresa AS
SELECT nombre, nombre_corto, nit, direccion, telefono, ciudad, correo_contacto, pie_comprobante, estado, fecha_estado
  FROM empresa
WITH READ ONLY;

-- ---------- Defensa en la base: sin sesion de aplicacion mientras la empresa este suspendida ----------
-- Mismo paquete de 02 (spec sin cambios); el cuerpo agrega la comprobacion al iniciar sesion.
CREATE OR REPLACE PACKAGE BODY pkg_seguridad AS

    -- ORA-20021: el dueno suspendio la empresa (sql/empresa.sh suspender).
    c_empresa_suspendida CONSTANT PLS_INTEGER := -20021;

    PROCEDURE sp_iniciar_sesion(p_usuario IN VARCHAR2, p_rol IN VARCHAR2) IS
        v_suspendida NUMBER;
    BEGIN
        IF p_usuario IS NULL OR NOT REGEXP_LIKE(p_usuario, '^[A-Za-z0-9_.@-]{3,100}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Identificador de usuario invalido.');
        END IF;
        IF p_rol IS NULL OR p_rol NOT IN (c_rol_admin, c_rol_operativo) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Rol de aplicacion invalido.');
        END IF;
        SELECT COUNT(*) INTO v_suspendida FROM empresa WHERE estado = 'SUSPENDIDA';
        IF v_suspendida > 0 THEN
            RAISE_APPLICATION_ERROR(c_empresa_suspendida, 'El servicio de su empresa está suspendido.');
        END IF;
        DBMS_SESSION.SET_CONTEXT('__CTX__', 'USUARIO', p_usuario);
        DBMS_SESSION.SET_CONTEXT('__CTX__', 'ROL', p_rol);
        DBMS_SESSION.SET_IDENTIFIER(p_usuario);
    END sp_iniciar_sesion;

    PROCEDURE sp_cerrar_sesion IS
    BEGIN
        DBMS_SESSION.CLEAR_CONTEXT('__CTX__');
        DBMS_SESSION.CLEAR_IDENTIFIER;
    END sp_cerrar_sesion;

    FUNCTION fn_usuario_actual RETURN VARCHAR2 IS
    BEGIN
        RETURN SYS_CONTEXT('__CTX__', 'USUARIO');
    END fn_usuario_actual;

    FUNCTION fn_rol_actual RETURN VARCHAR2 IS
    BEGIN
        RETURN SYS_CONTEXT('__CTX__', 'ROL');
    END fn_rol_actual;

    PROCEDURE sp_exigir_rol(p_rol_minimo IN VARCHAR2) IS
        v_rol    VARCHAR2(20) := SYS_CONTEXT('__CTX__', 'ROL');
        v_id_log NUMBER;
    BEGIN
        IF v_rol IS NULL THEN
            pkg_log.sp_error('PKG_SEGURIDAD.sp_exigir_rol', pkg_errores.c_permiso_denegado,
                             'Intento sin sesion de aplicacion', NULL, 'exigido=' || p_rol_minimo, v_id_log);
            RAISE_APPLICATION_ERROR(pkg_errores.c_permiso_denegado, 'No hay una sesion de aplicacion iniciada.');
        END IF;
        IF p_rol_minimo = c_rol_admin AND v_rol <> c_rol_admin THEN
            pkg_log.sp_error('PKG_SEGURIDAD.sp_exigir_rol', pkg_errores.c_permiso_denegado,
                             'Rol insuficiente', NULL, 'rol=' || v_rol || ';exigido=' || p_rol_minimo, v_id_log);
            RAISE_APPLICATION_ERROR(pkg_errores.c_permiso_denegado, 'Operacion reservada al rol ADMIN.');
        END IF;
    END sp_exigir_rol;

END pkg_seguridad;
/
SHOW ERRORS
