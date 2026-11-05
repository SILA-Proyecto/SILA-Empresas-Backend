-- =====================================================================
-- 11 - Parametros del sistema editables (solo ADMIN)
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Reejecutable. Va DESPUES de 02, 06 y 10.
--
-- La tabla parametros_sistema ya existia, pero solo se podia cambiar con acceso directo a la base.
-- Ahora cada parametro numerico tiene un rango permitido (valor_minimo / valor_maximo) y un ADMIN lo
-- cambia por pkg_parametros.sp_actualizar; el trigger trg_aud_parametros ya audita cada cambio
-- (valor anterior y nuevo). Se agrega IVA_DEFECTO_PORCENTAJE (valor inicial del IVA de un producto nuevo).
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-955, -1430, -2260, -1408) THEN RAISE; END IF;
    END;
BEGIN
    ejecutar('ALTER TABLE parametros_sistema ADD (valor_minimo NUMBER, valor_maximo NUMBER)');
END;
/

MERGE INTO parametros_sistema p
USING (SELECT 'IVA_DEFECTO_PORCENTAJE' clave, 19 valor, 'Porcentaje de IVA que se propone al crear un producto nuevo' descripcion FROM dual) s
ON (p.clave = s.clave)
WHEN NOT MATCHED THEN INSERT (clave, valor_numero, descripcion) VALUES (s.clave, s.valor, s.descripcion);

-- Rangos permitidos: evitan valores absurdos (por ejemplo, 0 intentos de login o un plazo de 10 000 dias).
UPDATE parametros_sistema SET valor_minimo =   0, valor_maximo =  30  WHERE clave = 'TEMP_MAX_LECHE_C';
UPDATE parametros_sistema SET valor_minimo =  10, valor_maximo =  30  WHERE clave = 'ACIDEZ_MAX_DORNIC';
UPDATE parametros_sistema SET valor_minimo =   1, valor_maximo = 365  WHERE clave = 'DIAS_VIDA_UTIL_DEFAULT';
UPDATE parametros_sistema SET valor_minimo =   0, valor_maximo = 365  WHERE clave = 'PLAZO_CREDITO_DIAS';
UPDATE parametros_sistema SET valor_minimo =   1, valor_maximo = 500  WHERE clave = 'MAX_LINEAS_DOCUMENTO';
UPDATE parametros_sistema SET valor_minimo =   3, valor_maximo =  20  WHERE clave = 'LOGIN_MAX_INTENTOS';
UPDATE parametros_sistema SET valor_minimo =   1, valor_maximo = 1440 WHERE clave = 'LOGIN_BLOQUEO_MINUTOS';
UPDATE parametros_sistema SET valor_minimo =   1, valor_maximo = 168  WHERE clave = 'SESION_MAX_HORAS';
UPDATE parametros_sistema SET valor_minimo =   0, valor_maximo = 100  WHERE clave = 'IVA_DEFECTO_PORCENTAJE';
COMMIT;

CREATE OR REPLACE PACKAGE pkg_parametros AUTHID DEFINER AS
    FUNCTION fn_numero(p_clave IN VARCHAR2) RETURN NUMBER RESULT_CACHE;

    -- Solo ADMIN. Cambia el valor de un parametro numerico dentro de su rango permitido.
    PROCEDURE sp_actualizar(p_clave IN VARCHAR2, p_valor IN NUMBER);
END pkg_parametros;
/
CREATE OR REPLACE PACKAGE BODY pkg_parametros AS

    FUNCTION fn_numero(p_clave IN VARCHAR2) RETURN NUMBER RESULT_CACHE IS
        v_valor NUMBER;
    BEGIN
        SELECT valor_numero INTO v_valor
          FROM parametros_sistema
         WHERE clave = p_clave;
        RETURN v_valor;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                                    'Parametro de sistema no configurado: ' || p_clave);
    END fn_numero;

    PROCEDURE sp_actualizar(p_clave IN VARCHAR2, p_valor IN NUMBER) IS
        v_min    NUMBER;
        v_max    NUMBER;
        v_actual NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_clave IS NULL OR p_valor IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La clave y el valor son obligatorios.');
        END IF;
        BEGIN
            SELECT valor_minimo, valor_maximo, valor_numero INTO v_min, v_max, v_actual
              FROM parametros_sistema WHERE clave = p_clave FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El parametro no existe.');
        END;
        IF v_actual IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'Ese parametro no es numerico y no se edita aqui.');
        END IF;
        IF p_valor <> ROUND(p_valor, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El valor admite como maximo 2 decimales.');
        END IF;
        IF (v_min IS NOT NULL AND p_valor < v_min) OR (v_max IS NOT NULL AND p_valor > v_max) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'El valor debe estar entre ' || NVL(TO_CHAR(v_min), '-') || ' y ' || NVL(TO_CHAR(v_max), '-') || '.');
        END IF;
        UPDATE parametros_sistema SET valor_numero = p_valor WHERE clave = p_clave;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar', 'clave=' || p_clave);
    END sp_actualizar;

END pkg_parametros;
/

CREATE OR REPLACE VIEW vw_parametros_sistema AS
SELECT clave, valor_numero AS valor, valor_minimo AS minimo, valor_maximo AS maximo, descripcion
  FROM parametros_sistema
 WHERE valor_numero IS NOT NULL
WITH READ ONLY;

GRANT EXECUTE ON pkg_parametros     TO __ROL_APP__;
GRANT SELECT  ON vw_parametros_sistema TO __ROL_APP__;

SHOW ERRORS
