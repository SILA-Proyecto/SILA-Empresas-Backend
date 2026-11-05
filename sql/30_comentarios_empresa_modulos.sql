-- =====================================================================
-- 30 - Comentarios de documentacion en las tablas de empresa, modulos y version del esquema
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Lo aplica migrar.sh. Reejecutable (COMMENT reemplaza el anterior).
-- Es el primer script que se agrego DESPUES de tener version_esquema: solo documenta, no cambia datos ni estructura.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

COMMENT ON TABLE empresa IS 'Datos de la empresa (una sola fila). Los cambia el dueno del sistema con sql/empresa.sh; la app solo lee vw_empresa.';
COMMENT ON TABLE modulos IS 'Catalogo de modulos y su estado (activo) para esta empresa. Los cambia el dueno con sql/modulos.sh; la app solo lee vw_modulos.';
COMMENT ON COLUMN modulos.nucleo IS '1 = del nucleo: siempre activo, no se puede apagar.';
COMMENT ON COLUMN modulos.activo IS '0 = apagado: sus rutas dan 403/20020 y la base tambien se niega (pkg_modulos).';
COMMENT ON TABLE version_esquema IS 'Scripts de sql/ aplicados a esta base (solo insercion). Lo escribe migrar.sh; huella = SHA-256 del archivo original.';
COMMENT ON COLUMN version_esquema.origen IS 'EJECUTADO = migrar.sh lo corrio; LINEA_BASE = la base ya existia y solo se registro.';

SELECT object_name, object_type, status FROM user_objects
 WHERE status <> 'VALID' AND object_name IN ('EMPRESA', 'MODULOS', 'VERSION_ESQUEMA');
SHOW ERRORS
