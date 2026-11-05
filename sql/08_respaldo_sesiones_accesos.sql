-- =====================================================================
-- 08 - Codigos de respaldo del MFA, gestion de sesiones y registro de accesos
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1, DESPUES de 06 y 07. Reejecutable.
--
--  * mfa_codigos_respaldo / pkg_respaldo_mfa: 10 codigos de un solo uso (solo su hash) para entrar
--    si se pierde el telefono. Se borran solos cuando se restablece el segundo factor.
--  * eventos_acceso / pkg_accesos / vw_eventos_acceso: quien entro, quien fallo, desde que IP y con
--    que navegador (solo insercion). Es lo que mira la pantalla de auditoria de accesos.
--  * vw_sesiones_activas / pkg_sesiones: ver y cerrar sesiones (las mias, las demas, o las de otra persona).
--  * pkg_estado_usuario: ahora tambien comprueba que la SESION (familia) siga abierta, de modo que cerrar
--    sesion o revocarla corta tambien el token de acceso vigente.
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
    ejecutar('
CREATE TABLE mfa_codigos_respaldo (
    id_codigo       NUMBER GENERATED ALWAYS AS IDENTITY,
    id_usuario      NUMBER            NOT NULL,
    codigo_hash     VARCHAR2(64 CHAR) NOT NULL,
    usado           NUMBER(1)         DEFAULT 0 NOT NULL,
    fecha_creacion  TIMESTAMP         DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    fecha_uso       TIMESTAMP,
    CONSTRAINT pk_mfa_respaldo PRIMARY KEY (id_codigo),
    CONSTRAINT uk_mfa_respaldo UNIQUE (id_usuario, codigo_hash),
    CONSTRAINT fk_mfa_respaldo_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios_app (id_usuario),
    CONSTRAINT ck_mfa_respaldo_usado CHECK (usado IN (0, 1))
)');
    ejecutar('
CREATE TABLE eventos_acceso (
    id_evento   NUMBER GENERATED ALWAYS AS IDENTITY,
    fecha       TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    usuario     VARCHAR2(100 CHAR),
    evento      VARCHAR2(40 CHAR)  NOT NULL,
    ip          VARCHAR2(45 CHAR),
    user_agent  VARCHAR2(200 CHAR),
    detalle     VARCHAR2(200 CHAR),
    CONSTRAINT pk_eventos_acceso PRIMARY KEY (id_evento)
)');
    ejecutar('CREATE INDEX ix_eventos_acceso_fecha ON eventos_acceso (fecha)');
    ejecutar('CREATE INDEX ix_eventos_acceso_usuario ON eventos_acceso (usuario, fecha)');
END;
/

COMMENT ON TABLE mfa_codigos_respaldo IS 'Codigos de un solo uso para entrar sin el telefono (solo su hash SHA-256)';
COMMENT ON TABLE eventos_acceso IS 'Bitacora de accesos: logins, fallos, bloqueos, cierres de sesion, con IP y navegador (solo insercion)';

CREATE OR REPLACE TRIGGER trg_ro_eventos_acceso
BEFORE UPDATE OR DELETE ON eventos_acceso
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'La bitacora de accesos es de solo insercion.');
END trg_ro_eventos_acceso;
/

-- Al quitar el segundo factor (restablecerlo) los codigos de respaldo dejan de valer.
CREATE OR REPLACE TRIGGER trg_usuarios_mfa_respaldo
AFTER UPDATE OF mfa_activo ON usuarios_app
FOR EACH ROW
WHEN (NEW.mfa_activo = 0 AND OLD.mfa_activo = 1)
BEGIN
    DELETE FROM mfa_codigos_respaldo WHERE id_usuario = :NEW.id_usuario;
END trg_usuarios_mfa_respaldo;
/

-- ---------- pkg_respaldo_mfa ----------
CREATE OR REPLACE PACKAGE pkg_respaldo_mfa AUTHID DEFINER AS
    -- p_hashes: SHA-256 en hexadecimal separados por coma (los calcula el backend; la base nunca ve un codigo).
    -- Reemplaza TODOS los codigos anteriores. Exige que el usuario tenga el segundo factor activo.
    PROCEDURE sp_reemplazar(p_id_usuario IN NUMBER, p_hashes IN VARCHAR2);
    -- p_ok = 1 si el codigo existia y no se habia usado (queda usado).
    PROCEDURE sp_consumir(p_id_usuario IN NUMBER, p_hash IN VARCHAR2, p_ok OUT NUMBER, p_restantes OUT NUMBER);
    PROCEDURE sp_restantes(p_id_usuario IN NUMBER, p_restantes OUT NUMBER);
END pkg_respaldo_mfa;
/
CREATE OR REPLACE PACKAGE BODY pkg_respaldo_mfa AS

    PROCEDURE pr_auditar(p_id IN NUMBER, p_evento IN VARCHAR2, p_detalle IN VARCHAR2) IS
        v_usuario VARCHAR2(100);
    BEGIN
        SELECT usuario INTO v_usuario FROM usuarios_app WHERE id_usuario = p_id;
        INSERT INTO auditoria_cambios (tabla, id_registro, columna, valor_anterior, valor_nuevo, usuario)
        VALUES ('USUARIOS_APP', TO_CHAR(p_id), p_evento, NULL, SUBSTR(p_detalle, 1, 400), v_usuario);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN NULL;
    END pr_auditar;

    PROCEDURE sp_reemplazar(p_id_usuario IN NUMBER, p_hashes IN VARCHAR2) IS
        v_mfa NUMBER;
        v_n   NUMBER := 0;
    BEGIN
        SELECT mfa_activo INTO v_mfa FROM usuarios_app WHERE id_usuario = p_id_usuario FOR UPDATE;
        IF v_mfa <> 1 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'El segundo factor no esta activo.');
        END IF;
        IF p_hashes IS NULL OR NOT REGEXP_LIKE(p_hashes, '^[0-9a-f]{64}(,[0-9a-f]{64}){0,19}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Lista de codigos invalida.');
        END IF;
        DELETE FROM mfa_codigos_respaldo WHERE id_usuario = p_id_usuario;
        FOR r IN (SELECT REGEXP_SUBSTR(p_hashes, '[^,]+', 1, LEVEL) AS h
                    FROM dual CONNECT BY REGEXP_SUBSTR(p_hashes, '[^,]+', 1, LEVEL) IS NOT NULL) LOOP
            INSERT INTO mfa_codigos_respaldo (id_usuario, codigo_hash) VALUES (p_id_usuario, r.h);
            v_n := v_n + 1;
        END LOOP;
        pr_auditar(p_id_usuario, 'CODIGOS_RESPALDO_GENERADOS', 'cantidad=' || v_n);
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El usuario no existe.');
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_reemplazar', 'id_usuario=' || p_id_usuario);
    END sp_reemplazar;

    PROCEDURE sp_consumir(p_id_usuario IN NUMBER, p_hash IN VARCHAR2, p_ok OUT NUMBER, p_restantes OUT NUMBER) IS
    BEGIN
        UPDATE mfa_codigos_respaldo
           SET usado = 1, fecha_uso = CAST(SYSTIMESTAMP AS TIMESTAMP)
         WHERE id_usuario = p_id_usuario AND codigo_hash = p_hash AND usado = 0;
        p_ok := CASE WHEN SQL%ROWCOUNT = 1 THEN 1 ELSE 0 END;
        SELECT COUNT(*) INTO p_restantes FROM mfa_codigos_respaldo WHERE id_usuario = p_id_usuario AND usado = 0;
        IF p_ok = 1 THEN
            pr_auditar(p_id_usuario, 'CODIGO_RESPALDO_USADO', 'restantes=' || p_restantes);
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_ok := 0;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_consumir', 'id_usuario=' || p_id_usuario);
    END sp_consumir;

    PROCEDURE sp_restantes(p_id_usuario IN NUMBER, p_restantes OUT NUMBER) IS
    BEGIN
        SELECT COUNT(*) INTO p_restantes FROM mfa_codigos_respaldo WHERE id_usuario = p_id_usuario AND usado = 0;
    END sp_restantes;

END pkg_respaldo_mfa;
/

-- ---------- pkg_accesos + vista ----------
CREATE OR REPLACE PACKAGE pkg_accesos AUTHID DEFINER AS
    PROCEDURE sp_registrar(
        p_usuario    IN VARCHAR2,
        p_evento     IN VARCHAR2,
        p_ip         IN VARCHAR2,
        p_user_agent IN VARCHAR2,
        p_detalle    IN VARCHAR2
    );
END pkg_accesos;
/
CREATE OR REPLACE PACKAGE BODY pkg_accesos AS
    PROCEDURE sp_registrar(
        p_usuario IN VARCHAR2, p_evento IN VARCHAR2, p_ip IN VARCHAR2, p_user_agent IN VARCHAR2, p_detalle IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO eventos_acceso (usuario, evento, ip, user_agent, detalle)
        VALUES (SUBSTR(p_usuario, 1, 100), SUBSTR(p_evento, 1, 40), SUBSTR(p_ip, 1, 45),
                SUBSTR(p_user_agent, 1, 200), SUBSTR(p_detalle, 1, 200));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar');
    END sp_registrar;
END pkg_accesos;
/

CREATE OR REPLACE VIEW vw_eventos_acceso AS
SELECT id_evento, fecha, usuario, evento, ip, user_agent, detalle
  FROM eventos_acceso
WITH READ ONLY;

-- ---------- Sesiones ----------
CREATE OR REPLACE VIEW vw_sesiones_activas AS
SELECT familia, id_usuario, inicio_familia AS iniciada, fecha_creacion AS ultima_actividad, expira, ip, user_agent
  FROM sesiones_usuario
 WHERE usado = 0 AND revocado = 0 AND expira > CAST(SYSTIMESTAMP AS TIMESTAMP)
WITH READ ONLY;

CREATE OR REPLACE PACKAGE pkg_sesiones AUTHID DEFINER AS
    -- Solo revoca sesiones de ESE usuario (el backend pasa el id del token, nunca uno del cliente).
    PROCEDURE sp_revocar_familia(p_id_usuario IN NUMBER, p_familia IN VARCHAR2, p_n OUT NUMBER);
    -- Todas las del usuario, menos p_familia_conservar (puede ser NULL = todas).
    PROCEDURE sp_revocar_todas(p_id_usuario IN NUMBER, p_familia_conservar IN VARCHAR2, p_n OUT NUMBER);
END pkg_sesiones;
/
CREATE OR REPLACE PACKAGE BODY pkg_sesiones AS
    PROCEDURE sp_revocar_familia(p_id_usuario IN NUMBER, p_familia IN VARCHAR2, p_n OUT NUMBER) IS
    BEGIN
        UPDATE sesiones_usuario SET revocado = 1
         WHERE id_usuario = p_id_usuario AND familia = p_familia AND revocado = 0;
        p_n := SQL%ROWCOUNT;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_revocar_familia');
    END sp_revocar_familia;

    PROCEDURE sp_revocar_todas(p_id_usuario IN NUMBER, p_familia_conservar IN VARCHAR2, p_n OUT NUMBER) IS
    BEGIN
        UPDATE sesiones_usuario SET revocado = 1
         WHERE id_usuario = p_id_usuario AND revocado = 0
           AND (p_familia_conservar IS NULL OR familia <> p_familia_conservar);
        p_n := SQL%ROWCOUNT;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_revocar_todas');
    END sp_revocar_todas;
END pkg_sesiones;
/

-- ---------- pkg_estado_usuario: ahora tambien valida la sesion ----------
CREATE OR REPLACE PACKAGE pkg_estado_usuario AUTHID DEFINER AS
    -- p_activo: 1 | 0 | NULL si no existe. p_rol: rol vigente. p_sesion_ok: 1 si la familia de sesion sigue abierta.
    PROCEDURE sp_consultar(p_id_usuario IN NUMBER, p_familia IN VARCHAR2,
                           p_activo OUT NUMBER, p_rol OUT VARCHAR2, p_sesion_ok OUT NUMBER);
END pkg_estado_usuario;
/
CREATE OR REPLACE PACKAGE BODY pkg_estado_usuario AS
    PROCEDURE sp_consultar(p_id_usuario IN NUMBER, p_familia IN VARCHAR2,
                           p_activo OUT NUMBER, p_rol OUT VARCHAR2, p_sesion_ok OUT NUMBER) IS
    BEGIN
        SELECT activo, rol INTO p_activo, p_rol FROM usuarios_app WHERE id_usuario = p_id_usuario;
        SELECT CASE WHEN EXISTS (SELECT 1 FROM sesiones_usuario
                                  WHERE familia = p_familia AND id_usuario = p_id_usuario AND revocado = 0)
                    THEN 1 ELSE 0 END
          INTO p_sesion_ok FROM dual;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_activo := NULL;
            p_rol := NULL;
            p_sesion_ok := 0;
    END sp_consultar;
END pkg_estado_usuario;
/

-- ---------- Permisos ----------
GRANT EXECUTE ON pkg_estado_usuario TO __ROL_APP__;
GRANT EXECUTE ON pkg_respaldo_mfa   TO __ROL_APP__;
GRANT EXECUTE ON pkg_accesos        TO __ROL_APP__;
GRANT EXECUTE ON pkg_sesiones       TO __ROL_APP__;
GRANT SELECT  ON vw_eventos_acceso    TO __ROL_APP__;
GRANT SELECT  ON vw_sesiones_activas  TO __ROL_APP__;
-- La auditoria general (cambios y errores) la consulta el backend solo para ADMIN.
GRANT SELECT  ON vw_auditoria_cambios TO __ROL_APP__;
GRANT SELECT  ON vw_log_errores       TO __ROL_APP__;

SHOW ERRORS
