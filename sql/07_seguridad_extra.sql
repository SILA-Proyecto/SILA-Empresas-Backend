-- =====================================================================
-- 07 - Idempotencia de escrituras y estado rapido de usuario
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Reejecutable.
--
--  * idempotencia / pkg_idempotencia: si el cliente repite una escritura con la misma
--    cabecera Idempotency-Key (reintento de red, doble clic), el backend devuelve la respuesta
--    guardada en vez de ejecutarla otra vez (evita ventas, abonos o facturas duplicadas).
--    Solo se guardan respuestas EXITOSAS, 24 horas, y nunca las de /auth ni /usuarios.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-955, -1430, -2260) THEN RAISE; END IF;
    END;
BEGIN
    ejecutar('
CREATE TABLE idempotencia (
    id_idem      NUMBER GENERATED ALWAYS AS IDENTITY,
    usuario      VARCHAR2(100 CHAR) NOT NULL,
    clave        VARCHAR2(100 CHAR) NOT NULL,
    huella       VARCHAR2(64 CHAR)  NOT NULL,
    estado       VARCHAR2(10 CHAR)  DEFAULT ''EN_PROCESO'' NOT NULL,
    http_status  NUMBER(3),
    respuesta    CLOB,
    creada       TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    CONSTRAINT pk_idempotencia PRIMARY KEY (id_idem),
    CONSTRAINT uk_idempotencia UNIQUE (usuario, clave),
    CONSTRAINT ck_idem_estado CHECK (estado IN (''EN_PROCESO'', ''COMPLETA''))
)');
END;
/

COMMENT ON TABLE idempotencia IS 'Respuestas guardadas por Idempotency-Key (24 h) para no repetir escrituras reintentadas';
COMMENT ON COLUMN idempotencia.huella IS 'SHA-256 de metodo + ruta + cuerpo: la misma clave con otro contenido es un error del cliente';

CREATE OR REPLACE PACKAGE pkg_idempotencia AUTHID DEFINER AS
    -- p_resultado: NUEVA (ejecutar la solicitud) | EN_PROCESO (otra identica sigue en curso)
    --              REPETIDA (devolver p_http y p_respuesta) | CONFLICTO (misma clave, contenido distinto)
    PROCEDURE sp_reservar(
        p_usuario   IN  VARCHAR2,
        p_clave     IN  VARCHAR2,
        p_huella    IN  VARCHAR2,
        p_resultado OUT VARCHAR2,
        p_http      OUT NUMBER,
        p_respuesta OUT CLOB
    );
    PROCEDURE sp_completar(p_usuario IN VARCHAR2, p_clave IN VARCHAR2, p_http IN NUMBER, p_respuesta IN CLOB);
    -- La solicitud fallo (no fue 2xx): se libera la clave para que pueda reintentarse.
    PROCEDURE sp_liberar(p_usuario IN VARCHAR2, p_clave IN VARCHAR2);
END pkg_idempotencia;
/
CREATE OR REPLACE PACKAGE BODY pkg_idempotencia AS

    c_vigencia_horas   CONSTANT NUMBER := 24;
    -- Una reserva EN_PROCESO mas vieja que esto se considera abandonada (el servidor se cayo a mitad).
    c_abandono_minutos CONSTANT NUMBER := 2;

    PROCEDURE sp_reservar(
        p_usuario IN VARCHAR2, p_clave IN VARCHAR2, p_huella IN VARCHAR2,
        p_resultado OUT VARCHAR2, p_http OUT NUMBER, p_respuesta OUT CLOB
    ) IS
        v_huella  VARCHAR2(64);
        v_estado  VARCHAR2(10);
        v_creada  TIMESTAMP;
        v_ahora   TIMESTAMP := CAST(SYSTIMESTAMP AS TIMESTAMP);
    BEGIN
        DELETE FROM idempotencia WHERE creada < v_ahora - NUMTODSINTERVAL(c_vigencia_horas, 'HOUR');
        FOR intento IN 1 .. 2 LOOP
            BEGIN
                INSERT INTO idempotencia (usuario, clave, huella) VALUES (p_usuario, p_clave, p_huella);
                COMMIT;
                p_resultado := 'NUEVA';
                RETURN;
            EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN
                    BEGIN
                        SELECT huella, estado, http_status, respuesta, creada
                          INTO v_huella, v_estado, p_http, p_respuesta, v_creada
                          FROM idempotencia
                         WHERE usuario = p_usuario AND clave = p_clave
                           FOR UPDATE;
                        IF v_huella <> p_huella THEN
                            p_resultado := 'CONFLICTO';
                        ELSIF v_estado = 'COMPLETA' THEN
                            p_resultado := 'REPETIDA';
                        ELSIF v_creada < v_ahora - NUMTODSINTERVAL(c_abandono_minutos, 'MINUTE') THEN
                            UPDATE idempotencia SET creada = v_ahora WHERE usuario = p_usuario AND clave = p_clave;
                            p_resultado := 'NUEVA';
                        ELSE
                            p_resultado := 'EN_PROCESO';
                        END IF;
                        COMMIT;
                        RETURN;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN NULL;  -- la borraron justo ahora: reintentar el INSERT
                    END;
            END;
        END LOOP;
        p_resultado := 'EN_PROCESO';
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_reservar');
    END sp_reservar;

    PROCEDURE sp_completar(p_usuario IN VARCHAR2, p_clave IN VARCHAR2, p_http IN NUMBER, p_respuesta IN CLOB) IS
    BEGIN
        UPDATE idempotencia SET estado = 'COMPLETA', http_status = p_http, respuesta = p_respuesta
         WHERE usuario = p_usuario AND clave = p_clave;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_completar');
    END sp_completar;

    PROCEDURE sp_liberar(p_usuario IN VARCHAR2, p_clave IN VARCHAR2) IS
    BEGIN
        DELETE FROM idempotencia WHERE usuario = p_usuario AND clave = p_clave AND estado = 'EN_PROCESO';
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_liberar');
    END sp_liberar;

END pkg_idempotencia;
/

-- pkg_estado_usuario (revocacion inmediata) vive en 08_respaldo_sesiones_accesos.sql.

GRANT EXECUTE ON pkg_idempotencia   TO __ROL_APP__;

SHOW ERRORS
