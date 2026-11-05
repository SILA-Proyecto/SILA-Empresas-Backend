-- =====================================================================
-- 34 - Aceptaciones legales: quien acepto los TERMINOS y la PRIVACIDAD (Ley 1581 de 2012), cuando, desde donde
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Lo aplica migrar.sh. Reejecutable.
--
--  * aceptaciones_legales: una fila por persona, documento (TERMINOS | PRIVACIDAD) y version aceptada, con fecha, IP y
--    navegador. Es EVIDENCIA: trg_ro_aceptaciones_legales impide UPDATE y DELETE, y no hay ningun permiso de escritura
--    sobre la tabla para la app. La unica puerta es pkg_legal.sp_aceptar, que toma la persona de la SESION de aplicacion
--    (nadie acepta por otro) y escribe en una sola transaccion las aceptaciones y el evento LEGAL_ACEPTADO de eventos_acceso.
--  * El texto de los documentos NO vive aqui: lo muestra el dashboard (HTML) y el backend solo conoce la version vigente
--    (sila.legal.*, variables SILA_LEGAL_*). Cambiar la version obliga a TODOS a aceptar de nuevo (la fila antigua se conserva).
--  * NINGUNA fila se siembra: todos los usuarios existentes y el primer ADMIN de crear_empresa.sh quedan PENDIENTES hasta que
--    ellos mismos acepten por la API. Jamas se marcan aceptaciones por SQL (ni en pruebas): seria fabricar evidencia.
--  * vw_aceptaciones_estado (id_usuario, documento, version, fecha): la lee la app para saber si alguien esta al dia.
--    vw_aceptaciones_legales (con usuario, nombre, IP y navegador): SOLO para el dueno del sistema (sql/legal.sh); no se le
--    da a ninguna cuenta de la app ni de reportes, y el ADMIN de la empresa no tiene endpoint para verla.
--  * Quien tenga SYSTEM puede borrar la tabla entera: el trigger frena a la app, no al dueno del servidor. Por eso las
--    aceptaciones tambien entran en los respaldos de la empresa (baja_empresa.sh) y hace falta un respaldo fuera del servidor.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            -- ya existe: tabla/indice (955), lista de columnas ya indexada (1408)
            IF SQLCODE NOT IN (-955, -1408) THEN RAISE; END IF;
    END;
BEGIN
    ejecutar('
CREATE TABLE aceptaciones_legales (
    id_aceptacion  NUMBER GENERATED ALWAYS AS IDENTITY,
    id_usuario     NUMBER              NOT NULL,
    documento      VARCHAR2(20 CHAR)   NOT NULL,
    version        VARCHAR2(30 CHAR)   NOT NULL,
    fecha          TIMESTAMP           DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    ip             VARCHAR2(45 CHAR),
    user_agent     VARCHAR2(200 CHAR),
    CONSTRAINT pk_aceptaciones_legales PRIMARY KEY (id_aceptacion),
    CONSTRAINT fk_aceptaciones_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios_app (id_usuario),
    CONSTRAINT ck_aceptaciones_documento CHECK (documento IN (''TERMINOS'', ''PRIVACIDAD'')),
    CONSTRAINT ck_aceptaciones_version CHECK (REGEXP_LIKE(version, ''^[0-9A-Za-z._-]{1,30}$''))
)');
    -- Una persona acepta una version de un documento una sola vez (aceptar de nuevo no duplica).
    ejecutar('CREATE UNIQUE INDEX uk_aceptaciones_legales ON aceptaciones_legales (id_usuario, documento, version)');
    ejecutar('CREATE INDEX ix_aceptaciones_legales_fecha ON aceptaciones_legales (fecha)');
END;
/

COMMENT ON TABLE aceptaciones_legales IS 'Evidencia de que cada persona acepto los TERMINOS y la PRIVACIDAD (documento, version, fecha, IP, navegador). Solo insercion.';
COMMENT ON COLUMN aceptaciones_legales.documento IS 'TERMINOS | PRIVACIDAD.';
COMMENT ON COLUMN aceptaciones_legales.version IS 'Version del texto aceptado (sila.legal.documentos.*.version del backend).';
COMMENT ON COLUMN aceptaciones_legales.ip IS 'Direccion desde la que se acepto, tal como la vio el servidor.';

CREATE OR REPLACE TRIGGER trg_ro_aceptaciones_legales
BEFORE UPDATE OR DELETE ON aceptaciones_legales
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Las aceptaciones legales son de solo insercion.');
END trg_ro_aceptaciones_legales;
/

-- ---------- Vistas ----------
-- Para la app: lo minimo para saber quien esta al dia (sin IP ni navegador).
CREATE OR REPLACE VIEW vw_aceptaciones_estado AS
SELECT id_usuario, documento, version, fecha
  FROM aceptaciones_legales
WITH READ ONLY;

-- Para el DUENO (sql/legal.sh): quien acepto que, cuando y desde donde. NO se concede a ninguna cuenta.
CREATE OR REPLACE VIEW vw_aceptaciones_legales AS
SELECT a.id_aceptacion, a.fecha, u.usuario, u.nombre, u.rol, a.documento, a.version, a.ip, a.user_agent
  FROM aceptaciones_legales a
  JOIN usuarios_app u ON u.id_usuario = a.id_usuario
WITH READ ONLY;

-- ---------- pkg_legal ----------
CREATE OR REPLACE PACKAGE pkg_legal AUTHID DEFINER AS
    -- Registra, para la persona de la SESION de aplicacion, la aceptacion de las versiones dadas de los dos documentos.
    -- Idempotente: lo ya aceptado (misma version) no se duplica. p_nuevas = aceptaciones nuevas escritas (0, 1 o 2).
    -- Todo en una transaccion, con el evento LEGAL_ACEPTADO en eventos_acceso si hubo algo nuevo.
    PROCEDURE sp_aceptar(p_version_terminos IN VARCHAR2, p_version_privacidad IN VARCHAR2,
                         p_ip IN VARCHAR2, p_user_agent IN VARCHAR2, p_nuevas OUT NUMBER);
END pkg_legal;
/

CREATE OR REPLACE PACKAGE BODY pkg_legal AS

    PROCEDURE sp_aceptar(p_version_terminos IN VARCHAR2, p_version_privacidad IN VARCHAR2,
                         p_ip IN VARCHAR2, p_user_agent IN VARCHAR2, p_nuevas OUT NUMBER) IS
        v_usuario VARCHAR2(100 CHAR);
        v_id      NUMBER;

        PROCEDURE aceptar(p_documento IN VARCHAR2, p_version IN VARCHAR2) IS
        BEGIN
            INSERT INTO aceptaciones_legales (id_usuario, documento, version, ip, user_agent)
            SELECT v_id, p_documento, p_version, SUBSTR(p_ip, 1, 45), SUBSTR(p_user_agent, 1, 200)
              FROM dual
             WHERE NOT EXISTS (SELECT 1 FROM aceptaciones_legales
                                WHERE id_usuario = v_id AND documento = p_documento AND version = p_version);
            p_nuevas := p_nuevas + SQL%ROWCOUNT;
        END aceptar;
    BEGIN
        p_nuevas := 0;
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        v_usuario := pkg_seguridad.fn_usuario_actual;
        IF p_version_terminos IS NULL OR NOT REGEXP_LIKE(p_version_terminos, '^[0-9A-Za-z._-]{1,30}$')
           OR p_version_privacidad IS NULL OR NOT REGEXP_LIKE(p_version_privacidad, '^[0-9A-Za-z._-]{1,30}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La version de los documentos legales no es valida.');
        END IF;
        -- Bloquea la fila de la persona: dos aceptaciones simultaneas se turnan y la segunda ve lo que escribio la primera.
        SELECT id_usuario INTO v_id FROM usuarios_app WHERE usuario = v_usuario AND activo = 1 FOR UPDATE;
        aceptar('TERMINOS', p_version_terminos);
        aceptar('PRIVACIDAD', p_version_privacidad);
        IF p_nuevas > 0 THEN
            INSERT INTO eventos_acceso (usuario, evento, ip, user_agent, detalle)
            VALUES (SUBSTR(v_usuario, 1, 100), 'LEGAL_ACEPTADO', SUBSTR(p_ip, 1, 45), SUBSTR(p_user_agent, 1, 200),
                    SUBSTR('TERMINOS=' || p_version_terminos || ';PRIVACIDAD=' || p_version_privacidad, 1, 200));
        END IF;
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(pkg_errores.c_permiso_denegado, 'El usuario de la sesion no existe o esta inactivo.');
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_aceptar');
    END sp_aceptar;

END pkg_legal;
/
SHOW ERRORS

-- ---------- Permisos: la app ejecuta el paquete y lee el estado; ninguna tabla ----------
GRANT EXECUTE ON pkg_legal             TO __ROL_APP__;
GRANT SELECT  ON vw_aceptaciones_estado TO __ROL_APP__;
