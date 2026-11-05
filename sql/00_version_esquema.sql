-- =====================================================================
-- 00 - Version del esquema: que scripts tiene aplicados esta base
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Lo aplica migrar.sh (es el primero). Reejecutable.
--
--  * version_esquema: una fila por script aplicado (numero y nombre del archivo, huella SHA-256, origen, cuando, quien y
--    cuanto tardo). La escribe SOLO migrar.sh, como dueno. Es de solo insercion (como las demas bitacoras): un trigger
--    impide editar o borrar filas.
--  * origen: EJECUTADO (migrar.sh lo corrio) o LINEA_BASE (la base ya existia y se registro sin ejecutar).
--  * huella: SHA-256 del archivo ORIGINAL (con los __marcadores__, antes de sustituirlos). Se eligio el original y no el
--    renderizado porque el original es identico en todas las empresas: sirve para comparar versiones entre empresas y para
--    detectar que alguien edito un script ya aplicado, sin que el nombre del esquema cambie la huella.
--  * vw_version_esquema: lectura para la app (GET /api/v1/empresa muestra la ultima version).
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-955, -1430, -2260, -2261, -2264, -2275) THEN RAISE; END IF;
    END;
BEGIN
    ejecutar(q'~
CREATE TABLE version_esquema (
    id_version  NUMBER GENERATED ALWAYS AS IDENTITY,
    numero      NUMBER(4)          NOT NULL,
    nombre      VARCHAR2(120 CHAR) NOT NULL,
    huella      CHAR(64 CHAR)      NOT NULL,
    origen      VARCHAR2(12 CHAR)  DEFAULT 'EJECUTADO' NOT NULL,
    aplicado_en TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    usuario     VARCHAR2(100 CHAR) NOT NULL,
    duracion_ms NUMBER(10),
    CONSTRAINT pk_version_esquema PRIMARY KEY (id_version),
    CONSTRAINT uk_version_esquema_nombre UNIQUE (nombre),
    CONSTRAINT ck_version_esquema_origen CHECK (origen IN ('EJECUTADO', 'LINEA_BASE')),
    CONSTRAINT ck_version_esquema_huella CHECK (REGEXP_LIKE(huella, '^[0-9a-f]{64}$'))
)~');
END;
/

CREATE OR REPLACE TRIGGER trg_version_esquema_inmutable
BEFORE UPDATE OR DELETE ON version_esquema
BEGIN
    RAISE_APPLICATION_ERROR(-20011, 'version_esquema es de solo insercion: lo escribe migrar.sh y no se edita ni se borra.');
END trg_version_esquema_inmutable;
/

CREATE OR REPLACE VIEW vw_version_esquema AS
SELECT numero, nombre, huella, origen, aplicado_en, usuario, duracion_ms
  FROM version_esquema
WITH READ ONLY;

GRANT SELECT ON vw_version_esquema TO __ROL_APP__;

SELECT object_name, object_type, status FROM user_objects
 WHERE status <> 'VALID' AND object_name IN ('VERSION_ESQUEMA', 'TRG_VERSION_ESQUEMA_INMUTABLE', 'VW_VERSION_ESQUEMA');
SHOW ERRORS
