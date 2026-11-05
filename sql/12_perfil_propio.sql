-- =====================================================================
-- 12 - Editar mis propios datos (nombre y correo)
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1, DESPUES de 06. Reejecutable.
-- No toca rol, usuario ni estado: solo nombre y correo de la persona indicada. El backend exige
-- el codigo del segundo factor antes de llamarlo.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

CREATE OR REPLACE PACKAGE pkg_perfil AUTHID DEFINER AS
    PROCEDURE sp_actualizar_mis_datos(p_id_usuario IN NUMBER, p_nombre IN VARCHAR2, p_email IN VARCHAR2);
END pkg_perfil;
/
CREATE OR REPLACE PACKAGE BODY pkg_perfil AS
    PROCEDURE sp_actualizar_mis_datos(p_id_usuario IN NUMBER, p_nombre IN VARCHAR2, p_email IN VARCHAR2) IS
        v_usuario VARCHAR2(100);
        v_nombre  VARCHAR2(120);
        v_email   VARCHAR2(150);
        v_cuenta  NUMBER;
    BEGIN
        IF p_nombre IS NULL OR LENGTH(TRIM(p_nombre)) < 3 OR LENGTH(p_nombre) > 120 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Nombre invalido (3 a 120 caracteres).');
        END IF;
        IF p_email IS NULL OR LENGTH(p_email) > 150 OR NOT REGEXP_LIKE(p_email, '^[^@ ]+@[^@ ]+\.[^@ ]+$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Correo electronico invalido.');
        END IF;
        BEGIN
            SELECT usuario, nombre, email INTO v_usuario, v_nombre, v_email
              FROM usuarios_app WHERE id_usuario = p_id_usuario;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El usuario no existe.');
        END;
        SELECT COUNT(*) INTO v_cuenta FROM usuarios_app
         WHERE email = LOWER(TRIM(p_email)) AND id_usuario <> p_id_usuario;
        IF v_cuenta > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'Ese correo ya esta en uso por otra cuenta.');
        END IF;
        UPDATE usuarios_app SET nombre = TRIM(p_nombre), email = LOWER(TRIM(p_email))
         WHERE id_usuario = p_id_usuario;
        IF v_nombre <> TRIM(p_nombre) THEN
            INSERT INTO auditoria_cambios (tabla, id_registro, columna, valor_anterior, valor_nuevo, usuario)
            VALUES ('USUARIOS_APP', TO_CHAR(p_id_usuario), 'NOMBRE', v_nombre, TRIM(p_nombre), v_usuario);
        END IF;
        IF v_email <> LOWER(TRIM(p_email)) THEN
            INSERT INTO auditoria_cambios (tabla, id_registro, columna, valor_anterior, valor_nuevo, usuario)
            VALUES ('USUARIOS_APP', TO_CHAR(p_id_usuario), 'EMAIL', v_email, LOWER(TRIM(p_email)), v_usuario);
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_mis_datos', 'id_usuario=' || p_id_usuario);
    END sp_actualizar_mis_datos;
END pkg_perfil;
/
SHOW ERRORS
GRANT EXECUTE ON pkg_perfil TO __ROL_APP__;
EXIT
