-- =====================================================================
-- 16 - Vistas de lectura para Gastos y Documentos
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Reejecutable.
-- La escritura ya existe: pkg_finanzas.sp_registrar_gasto (OPERATIVO) y pkg_documentos.
-- Faltaba poder LISTAR cada gasto y cada documento (las vistas previas solo resumen).
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

CREATE OR REPLACE VIEW vw_gastos AS
SELECT g.id_gasto, g.id_periodo, p.anio, p.mes, p.quincena, g.id_categoria, c.nombre AS categoria,
       g.fecha_gasto, g.concepto, g.monto, g.usuario_registro, g.fecha_registro
  FROM gastos_operativos g
  JOIN periodos_quincena p ON p.id_periodo = g.id_periodo
  JOIN categorias_gasto c ON c.id_categoria = g.id_categoria
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_documentos AS
SELECT id_documento, tipo_entidad, id_entidad, nombre_archivo, mime_type, drive_url, checksum_sha256,
       estado_carga, intentos, ultimo_error, usuario_carga, fecha_registro, fecha_carga
  FROM documentos_repositorio
WITH READ ONLY;

GRANT SELECT ON vw_gastos     TO __ROL_APP__;
GRANT SELECT ON vw_documentos TO __ROL_APP__;

SHOW ERRORS
