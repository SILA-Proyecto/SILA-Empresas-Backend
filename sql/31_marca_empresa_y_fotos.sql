-- =====================================================================
-- 31 - Marca de la empresa (logo, datos de contacto, pie del comprobante) y foto de cada usuario
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Lo aplica migrar.sh. Reejecutable.
--
--  * QUIEN CAMBIA QUE (decision del usuario, 2026-10-26):
--      - el DUENO del sistema (sql/empresa.sh, por proxy): todo, y es el UNICO que cambia nombre, nombre corto y NIT;
--      - el ADMIN de la empresa (dashboard, pkg_empresa): logo, direccion, telefono, ciudad, correo y pie del comprobante.
--        El backend le pide ademas su codigo del segundo factor.
--      - cada usuario: SU foto. El ADMIN solo puede QUITAR la de otro (contenido inapropiado), nunca subirla por el.
--  * Las imagenes van DENTRO de la base (BLOB), en tablas aparte de empresa/usuarios_app para que ninguna consulta
--    normal las arrastre: son pocas y pequenas (el backend las reescribe a un tamano fijo antes de guardarlas), quedan en
--    el esquema de la empresa y entran en su respaldo. El backend las valida y RECODIFICA (tipo real, pixeles, EXIF);
--    la base vuelve a comprobar tipo, tamano y el formato de la huella (el SHA-256 lo calcula el backend: el dueno del
--    esquema no tiene EXECUTE sobre DBMS_CRYPTO y no se amplian sus privilegios por esto).
--  * La app recibe SELECT sobre vistas de solo lectura y EXECUTE sobre pkg_empresa / pkg_fotos; nada de tablas.
--  * Reemplaza trg_aud_empresa (de 05) para auditar tambien el pie del comprobante.
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
    ejecutar(q'~ALTER TABLE empresa ADD (pie_comprobante VARCHAR2(200 CHAR))~');

    ejecutar(q'~
CREATE TABLE empresa_logo (
    id_empresa     NUMBER(1)          DEFAULT 1 NOT NULL,
    contenido      BLOB               NOT NULL,
    tipo           VARCHAR2(20 CHAR)  NOT NULL,
    bytes          NUMBER(7)          NOT NULL,
    sha256         VARCHAR2(64 CHAR)  NOT NULL,
    fecha_cambio   TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    usuario_cambio VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT('__CTX__', 'USUARIO'), SYS_CONTEXT('USERENV', 'SESSION_USER')) NOT NULL,
    CONSTRAINT pk_empresa_logo PRIMARY KEY (id_empresa),
    CONSTRAINT fk_empresa_logo FOREIGN KEY (id_empresa) REFERENCES empresa (id_empresa),
    CONSTRAINT ck_empresa_logo_tipo CHECK (tipo IN ('image/png', 'image/jpeg')),
    CONSTRAINT ck_empresa_logo_bytes CHECK (bytes BETWEEN 1 AND 1048576),
    CONSTRAINT ck_empresa_logo_sha CHECK (REGEXP_LIKE(sha256, '^[0-9a-f]{64}$'))
)~');

    ejecutar(q'~
CREATE TABLE usuario_foto (
    id_usuario     NUMBER             NOT NULL,
    contenido      BLOB               NOT NULL,
    tipo           VARCHAR2(20 CHAR)  NOT NULL,
    bytes          NUMBER(7)          NOT NULL,
    sha256         VARCHAR2(64 CHAR)  NOT NULL,
    fecha_cambio   TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    usuario_cambio VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT('__CTX__', 'USUARIO'), SYS_CONTEXT('USERENV', 'SESSION_USER')) NOT NULL,
    CONSTRAINT pk_usuario_foto PRIMARY KEY (id_usuario),
    CONSTRAINT fk_usuario_foto FOREIGN KEY (id_usuario) REFERENCES usuarios_app (id_usuario),
    CONSTRAINT ck_usuario_foto_tipo CHECK (tipo IN ('image/png', 'image/jpeg')),
    CONSTRAINT ck_usuario_foto_bytes CHECK (bytes BETWEEN 1 AND 524288),
    CONSTRAINT ck_usuario_foto_sha CHECK (REGEXP_LIKE(sha256, '^[0-9a-f]{64}$'))
)~');
END;
/

-- ---------- Auditoria (la huella, nunca la imagen) ----------
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
END trg_aud_empresa;
/
CREATE OR REPLACE TRIGGER trg_aud_empresa_logo
AFTER INSERT OR UPDATE OR DELETE ON empresa_logo
FOR EACH ROW
BEGIN
    pkg_auditoria.sp_registrar('EMPRESA_LOGO', '1', 'SHA256',
                               CASE WHEN INSERTING THEN NULL ELSE :OLD.sha256 END,
                               CASE WHEN DELETING THEN NULL ELSE :NEW.sha256 END);
END trg_aud_empresa_logo;
/
CREATE OR REPLACE TRIGGER trg_aud_usuario_foto
AFTER INSERT OR UPDATE OR DELETE ON usuario_foto
FOR EACH ROW
BEGIN
    pkg_auditoria.sp_registrar('USUARIO_FOTO', TO_CHAR(NVL(:NEW.id_usuario, :OLD.id_usuario)), 'SHA256',
                               CASE WHEN INSERTING THEN NULL ELSE :OLD.sha256 END,
                               CASE WHEN DELETING THEN NULL ELSE :NEW.sha256 END);
END trg_aud_usuario_foto;
/

-- ---------- pkg_empresa: lo que el ADMIN puede cambiar ----------
CREATE OR REPLACE PACKAGE pkg_empresa AUTHID DEFINER AS
    -- Direccion, telefono, ciudad, correo y pie del comprobante. Un texto vacio deja el campo en blanco (NULL).
    -- Nombre, nombre corto y NIT NO: los cambia solo el dueno (sql/empresa.sh).
    PROCEDURE sp_actualizar_contacto(p_direccion IN VARCHAR2, p_telefono IN VARCHAR2, p_ciudad IN VARCHAR2,
                                     p_correo IN VARCHAR2, p_pie IN VARCHAR2);
    -- El logo ya validado y recodificado por el backend.
    PROCEDURE sp_fijar_logo(p_contenido IN BLOB, p_tipo IN VARCHAR2, p_sha256 IN VARCHAR2);
    PROCEDURE sp_quitar_logo;
END pkg_empresa;
/
CREATE OR REPLACE PACKAGE BODY pkg_empresa AS

    -- NULL si viene vacio; error si es mas largo de lo permitido o trae caracteres de control.
    FUNCTION fn_texto(p_valor IN VARCHAR2, p_max IN PLS_INTEGER, p_campo IN VARCHAR2) RETURN VARCHAR2 IS
        v VARCHAR2(4000) := TRIM(p_valor);
    BEGIN
        IF v IS NULL THEN RETURN NULL; END IF;
        IF LENGTH(v) > p_max THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, p_campo || ': maximo ' || p_max || ' caracteres.');
        END IF;
        IF REGEXP_LIKE(v, '[[:cntrl:]]') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, p_campo || ': contiene caracteres no permitidos.');
        END IF;
        RETURN v;
    END fn_texto;

    PROCEDURE sp_validar_imagen(p_contenido IN BLOB, p_tipo IN VARCHAR2, p_sha256 IN VARCHAR2, p_max IN PLS_INTEGER) IS
    BEGIN
        IF p_tipo IS NULL OR p_tipo NOT IN ('image/png', 'image/jpeg') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Tipo de imagen no permitido.');
        END IF;
        IF p_contenido IS NULL OR DBMS_LOB.GETLENGTH(p_contenido) NOT BETWEEN 1 AND p_max THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La imagen esta vacia o es demasiado grande.');
        END IF;
        IF p_sha256 IS NULL OR NOT REGEXP_LIKE(p_sha256, '^[0-9a-f]{64}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Huella de la imagen invalida.');
        END IF;
    END sp_validar_imagen;

    PROCEDURE sp_actualizar_contacto(p_direccion IN VARCHAR2, p_telefono IN VARCHAR2, p_ciudad IN VARCHAR2,
                                     p_correo IN VARCHAR2, p_pie IN VARCHAR2) IS
        v_direccion VARCHAR2(200);
        v_telefono  VARCHAR2(40);
        v_ciudad    VARCHAR2(80);
        v_correo    VARCHAR2(150);
        v_pie       VARCHAR2(200);
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        v_telefono := fn_texto(p_telefono, 40, 'Telefono');
        IF v_telefono IS NOT NULL AND NOT REGEXP_LIKE(v_telefono, '^[0-9 +().#/-]{5,40}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Telefono: solo numeros, espacios y + ( ) . # / -');
        END IF;
        v_correo := LOWER(fn_texto(p_correo, 150, 'Correo'));
        IF v_correo IS NOT NULL AND NOT REGEXP_LIKE(v_correo, '^[^@ ]+@[^@ ]+\.[^@ ]+$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Correo electronico invalido.');
        END IF;
        v_direccion := fn_texto(p_direccion, 200, 'Direccion');
        v_ciudad    := fn_texto(p_ciudad, 80, 'Ciudad');
        v_pie       := fn_texto(p_pie, 200, 'Pie del comprobante');
        UPDATE empresa
           SET direccion       = v_direccion,
               telefono        = v_telefono,
               ciudad          = v_ciudad,
               correo_contacto = v_correo,
               pie_comprobante = v_pie
         WHERE id_empresa = 1;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La empresa aun no tiene sus datos registrados.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_contacto');
    END sp_actualizar_contacto;

    PROCEDURE sp_fijar_logo(p_contenido IN BLOB, p_tipo IN VARCHAR2, p_sha256 IN VARCHAR2) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        sp_validar_imagen(p_contenido, p_tipo, p_sha256, 1048576);
        MERGE INTO empresa_logo l
        USING (SELECT 1 id_empresa FROM dual) s ON (l.id_empresa = s.id_empresa)
        WHEN MATCHED THEN UPDATE SET l.contenido = p_contenido, l.tipo = p_tipo, l.bytes = DBMS_LOB.GETLENGTH(p_contenido),
                                     l.sha256 = p_sha256, l.fecha_cambio = SYSTIMESTAMP,
                                     l.usuario_cambio = pkg_seguridad.fn_usuario_actual
        WHEN NOT MATCHED THEN INSERT (id_empresa, contenido, tipo, bytes, sha256, usuario_cambio)
             VALUES (1, p_contenido, p_tipo, DBMS_LOB.GETLENGTH(p_contenido), p_sha256, pkg_seguridad.fn_usuario_actual);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_fijar_logo');
    END sp_fijar_logo;

    PROCEDURE sp_quitar_logo IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        DELETE FROM empresa_logo WHERE id_empresa = 1;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_quitar_logo');
    END sp_quitar_logo;

END pkg_empresa;
/

-- ---------- pkg_fotos: la foto de cada usuario ----------
CREATE OR REPLACE PACKAGE pkg_fotos AUTHID DEFINER AS
    -- La foto de quien tiene la sesion (el usuario sale del contexto, no de un parametro: nadie sube la foto de otro).
    PROCEDURE sp_fijar_mi_foto(p_contenido IN BLOB, p_tipo IN VARCHAR2, p_sha256 IN VARCHAR2);
    -- La propia, o la de cualquiera si es ADMIN.
    PROCEDURE sp_quitar_foto(p_id_usuario IN NUMBER);
END pkg_fotos;
/
CREATE OR REPLACE PACKAGE BODY pkg_fotos AS

    FUNCTION fn_id_actual RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        SELECT id_usuario INTO v_id FROM usuarios_app WHERE usuario = pkg_seguridad.fn_usuario_actual AND activo = 1;
        RETURN v_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_permiso_denegado, 'El usuario de la sesion no existe o esta inactivo.');
    END fn_id_actual;

    PROCEDURE sp_fijar_mi_foto(p_contenido IN BLOB, p_tipo IN VARCHAR2, p_sha256 IN VARCHAR2) IS
        v_id NUMBER := fn_id_actual;
    BEGIN
        IF p_tipo IS NULL OR p_tipo NOT IN ('image/png', 'image/jpeg') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Tipo de imagen no permitido.');
        END IF;
        IF p_contenido IS NULL OR DBMS_LOB.GETLENGTH(p_contenido) NOT BETWEEN 1 AND 524288 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La imagen esta vacia o es demasiado grande.');
        END IF;
        IF p_sha256 IS NULL OR NOT REGEXP_LIKE(p_sha256, '^[0-9a-f]{64}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Huella de la imagen invalida.');
        END IF;
        MERGE INTO usuario_foto f
        USING (SELECT v_id id_usuario FROM dual) s ON (f.id_usuario = s.id_usuario)
        WHEN MATCHED THEN UPDATE SET f.contenido = p_contenido, f.tipo = p_tipo, f.bytes = DBMS_LOB.GETLENGTH(p_contenido),
                                     f.sha256 = p_sha256, f.fecha_cambio = SYSTIMESTAMP,
                                     f.usuario_cambio = pkg_seguridad.fn_usuario_actual
        WHEN NOT MATCHED THEN INSERT (id_usuario, contenido, tipo, bytes, sha256, usuario_cambio)
             VALUES (v_id, p_contenido, p_tipo, DBMS_LOB.GETLENGTH(p_contenido), p_sha256, pkg_seguridad.fn_usuario_actual);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_fijar_mi_foto');
    END sp_fijar_mi_foto;

    PROCEDURE sp_quitar_foto(p_id_usuario IN NUMBER) IS
        v_id NUMBER := fn_id_actual;
    BEGIN
        IF p_id_usuario IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Falta el usuario.');
        END IF;
        IF p_id_usuario <> v_id THEN
            pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        END IF;
        DELETE FROM usuario_foto WHERE id_usuario = p_id_usuario;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_quitar_foto', 'id_usuario=' || p_id_usuario);
    END sp_quitar_foto;

END pkg_fotos;
/
SHOW ERRORS

-- ---------- Vistas de lectura para la app ----------
CREATE OR REPLACE VIEW vw_empresa AS
SELECT nombre, nombre_corto, nit, direccion, telefono, ciudad, correo_contacto, pie_comprobante
  FROM empresa
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_empresa_logo AS
SELECT contenido, tipo, bytes, sha256, fecha_cambio
  FROM empresa_logo
 WHERE id_empresa = 1
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_usuario_foto AS
SELECT id_usuario, contenido, tipo, bytes, sha256, fecha_cambio
  FROM usuario_foto
WITH READ ONLY;

GRANT SELECT ON vw_empresa_logo TO __ROL_APP__;
GRANT SELECT ON vw_usuario_foto TO __ROL_APP__;
GRANT EXECUTE ON pkg_empresa    TO __ROL_APP__;
GRANT EXECUTE ON pkg_fotos      TO __ROL_APP__;

COMMENT ON COLUMN empresa.pie_comprobante IS 'Texto corto al pie de los comprobantes PDF. Lo cambia el ADMIN (pkg_empresa) o el dueno.';
COMMENT ON TABLE empresa_logo IS 'Logo de la empresa (0 o 1 fila), ya recodificado por el backend. Lo cambia el ADMIN (pkg_empresa).';
COMMENT ON TABLE usuario_foto IS 'Foto de perfil de cada usuario, ya recodificada por el backend. La sube el propio usuario (pkg_fotos).';

-- Verificacion: todo debe estar VALID
SELECT object_name, object_type, status FROM user_objects
 WHERE status <> 'VALID' AND object_name IN
   ('EMPRESA', 'EMPRESA_LOGO', 'USUARIO_FOTO', 'PKG_EMPRESA', 'PKG_FOTOS', 'VW_EMPRESA', 'VW_EMPRESA_LOGO', 'VW_USUARIO_FOTO',
    'TRG_AUD_EMPRESA', 'TRG_AUD_EMPRESA_LOGO', 'TRG_AUD_USUARIO_FOTO');
SHOW ERRORS
