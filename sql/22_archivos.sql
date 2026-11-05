-- =====================================================================
-- 22 - Archivos: PDF de comprobantes congelados, archivos subidos por el ADMIN y carpetas virtuales
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1, DESPUES de 02, 16 y 19. Reejecutable.
--
--  * documentos_repositorio pasa a ser el registro central de archivos FISICOS (y la cola de Drive):
--      - origen COMPROBANTE: PDF generado por el sistema para VENTA, ABONO, PAGO_PROVEEDOR, COMPRA o GASTO.
--        Un solo PDF por comprobante y version: ORIGINAL (se congela al registrar) y, si se anula, ANULADO
--        (segundo PDF con marca de agua; apunta al original, que NO se toca).
--      - origen ADMIN: archivo subido por el ADMIN (PDF, JPG o PNG, max 10 MB) a una carpeta manual.
--      - ruta_interna: nombre opaco (32 hex aleatorios) del archivo cifrado en disco. Nunca sale del backend.
--      - La base solo guarda metadatos. Los bytes viven cifrados en disco (paso 2, backend).
--  * Nada se borra ni se edita: un trigger bloquea DELETE y cualquier cambio de las columnas de identidad.
--    Solo cambian los campos de Drive (estado_carga, drive_*, intentos...) y el archivado (ADMIN, con motivo).
--  * carpetas_archivos: carpetas MANUALES (solo ADMIN) para sus archivos subidos. Las carpetas de comprobantes
--    son VIRTUALES (vw_archivos_ubicaciones): un PDF aparece en varias sin duplicarse.
--  * accesos_documentos: bitacora de solo insercion de quien vio, descargo o descifro, y con que tipo de clave
--    (la clave NUNCA se guarda). Tambien registra subidas, archivados y subidas rechazadas.
--  * pkg_archivos: toda la escritura. Los PDF legados de facturacion (FACTURA, NOTA_CREDITO) no se tocan.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            -- ya existe: tabla/indice (955), columna (1430), PK/UK (2260/2261), nombre de restriccion (2264),
            -- FK (2275), indice (1408), ya es NULL (1451), restriccion inexistente al borrar (2443)
            IF SQLCODE NOT IN (-955, -1430, -2260, -2261, -2264, -2275, -1408, -1451, -2443) THEN RAISE; END IF;
    END;
    -- Un CHECK se borra y se vuelve a crear: asi el script se puede reejecutar con la regla corregida.
    PROCEDURE regla(p_tabla IN VARCHAR2, p_nombre IN VARCHAR2, p_condicion IN VARCHAR2) IS
    BEGIN
        ejecutar('ALTER TABLE ' || p_tabla || ' DROP CONSTRAINT ' || p_nombre);
        ejecutar('ALTER TABLE ' || p_tabla || ' ADD CONSTRAINT ' || p_nombre || ' CHECK (' || p_condicion || ')');
    END;
BEGIN
    -- ---------- carpetas manuales ----------
    ejecutar(q'~
CREATE TABLE carpetas_archivos (
    id_carpeta       NUMBER GENERATED ALWAYS AS IDENTITY,
    id_padre         NUMBER,
    nombre           VARCHAR2(80 CHAR)  NOT NULL,
    usuario_creacion VARCHAR2(100 CHAR) NOT NULL,
    fecha_creacion   TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    archivada        NUMBER(1)          DEFAULT 0 NOT NULL,
    motivo_archivo   VARCHAR2(255 CHAR),
    usuario_archivo  VARCHAR2(100 CHAR),
    fecha_archivo    TIMESTAMP,
    CONSTRAINT pk_carpetas_archivos PRIMARY KEY (id_carpeta),
    CONSTRAINT fk_carpetas_padre FOREIGN KEY (id_padre) REFERENCES carpetas_archivos (id_carpeta)
)~');
    regla('carpetas_archivos', 'ck_carpetas_nombre',
          q'~nombre = TRIM(nombre) AND INSTR(nombre, '/') = 0 AND INSTR(nombre, '\') = 0 AND NOT REGEXP_LIKE(nombre, '[[:cntrl:]]')~');
    regla('carpetas_archivos', 'ck_carpetas_archivo',
          '(archivada = 0 AND motivo_archivo IS NULL AND usuario_archivo IS NULL AND fecha_archivo IS NULL) OR ' ||
          '(archivada = 1 AND motivo_archivo IS NOT NULL AND usuario_archivo IS NOT NULL AND fecha_archivo IS NOT NULL)');
    -- Mismo nombre solo una vez por carpeta (sin distinguir mayusculas); una archivada libera su nombre.
    ejecutar('CREATE UNIQUE INDEX uk_carpetas_nombre ON carpetas_archivos ' ||
             '(NVL(id_padre, 0), LOWER(nombre), CASE WHEN archivada = 0 THEN 0 ELSE id_carpeta END)');
    ejecutar('CREATE INDEX ix_carpetas_padre ON carpetas_archivos (id_padre)');

    -- ---------- documentos_repositorio: columnas nuevas ----------
    ejecutar('ALTER TABLE documentos_repositorio ADD (origen VARCHAR2(11 CHAR) DEFAULT ''COMPROBANTE'' NOT NULL)');
    ejecutar('ALTER TABLE documentos_repositorio ADD (version VARCHAR2(8 CHAR) DEFAULT ''ORIGINAL'' NOT NULL)');
    ejecutar('ALTER TABLE documentos_repositorio ADD (id_documento_original NUMBER)');
    ejecutar('ALTER TABLE documentos_repositorio ADD (ruta_interna VARCHAR2(64 CHAR))');
    ejecutar('ALTER TABLE documentos_repositorio ADD (tamano_bytes NUMBER(10))');
    ejecutar('ALTER TABLE documentos_repositorio ADD (id_carpeta NUMBER)');
    ejecutar('ALTER TABLE documentos_repositorio ADD (archivado NUMBER(1) DEFAULT 0 NOT NULL)');
    ejecutar('ALTER TABLE documentos_repositorio ADD (motivo_archivo VARCHAR2(255 CHAR))');
    ejecutar('ALTER TABLE documentos_repositorio ADD (usuario_archivo VARCHAR2(100 CHAR))');
    ejecutar('ALTER TABLE documentos_repositorio ADD (fecha_archivo TIMESTAMP)');
    -- Un archivo subido por el ADMIN no pertenece a ninguna entidad.
    ejecutar('ALTER TABLE documentos_repositorio MODIFY (id_entidad NULL)');

    ejecutar('ALTER TABLE documentos_repositorio ADD CONSTRAINT fk_documentos_original ' ||
             'FOREIGN KEY (id_documento_original) REFERENCES documentos_repositorio (id_documento)');
    ejecutar('ALTER TABLE documentos_repositorio ADD CONSTRAINT fk_documentos_carpeta ' ||
             'FOREIGN KEY (id_carpeta) REFERENCES carpetas_archivos (id_carpeta)');
    ejecutar('ALTER TABLE documentos_repositorio ADD CONSTRAINT uk_documentos_ruta UNIQUE (ruta_interna)');

    regla('documentos_repositorio', 'ck_documentos_tipo',
          q'~tipo_entidad IN ('FACTURA', 'NOTA_CREDITO', 'VENTA', 'ABONO', 'PAGO_PROVEEDOR', 'COMPRA', 'GASTO', 'ARCHIVO')~');
    regla('documentos_repositorio', 'ck_documentos_mime',
          q'~mime_type IN ('application/pdf', 'image/jpeg', 'image/png')~');
    regla('documentos_repositorio', 'ck_documentos_origen', q'~origen IN ('COMPROBANTE', 'ADMIN')~');
    regla('documentos_repositorio', 'ck_documentos_version', q'~version IN ('ORIGINAL', 'ANULADO')~');
    regla('documentos_repositorio', 'ck_documentos_ruta',
          q'~ruta_interna IS NULL OR REGEXP_LIKE(ruta_interna, '^[a-f0-9]{32}$')~');
    regla('documentos_repositorio', 'ck_documentos_tamano',
          'tamano_bytes IS NULL OR tamano_bytes BETWEEN 1 AND 10485760');
    -- Forma segun el origen. Los comprobantes son siempre PDF; lo subido por el ADMIN no tiene entidad ni version.
    regla('documentos_repositorio', 'ck_documentos_forma',
          q'~(origen = 'COMPROBANTE' AND tipo_entidad <> 'ARCHIVO' AND id_entidad IS NOT NULL AND id_carpeta IS NULL AND mime_type = 'application/pdf')
          OR (origen = 'ADMIN' AND tipo_entidad = 'ARCHIVO' AND id_entidad IS NULL AND version = 'ORIGINAL' AND id_documento_original IS NULL
              AND ruta_interna IS NOT NULL AND tamano_bytes IS NOT NULL AND checksum_sha256 IS NOT NULL)~');
    -- ANULADO siempre cuelga de su original; un ORIGINAL no tiene padre.
    regla('documentos_repositorio', 'ck_documentos_anulado',
          q'~(version = 'ORIGINAL' AND id_documento_original IS NULL) OR (version = 'ANULADO' AND id_documento_original IS NOT NULL AND origen = 'COMPROBANTE')~');
    regla('documentos_repositorio', 'ck_documentos_archivado',
          q'~(archivado = 0 AND motivo_archivo IS NULL AND usuario_archivo IS NULL AND fecha_archivo IS NULL)
          OR (archivado = 1 AND origen = 'ADMIN' AND motivo_archivo IS NOT NULL AND usuario_archivo IS NOT NULL AND fecha_archivo IS NOT NULL)~');

    -- Un solo PDF por comprobante y version (los registros legados sin archivo quedan fuera).
    ejecutar('CREATE UNIQUE INDEX uk_documentos_comprobante ON documentos_repositorio ' ||
             q'~(CASE WHEN origen = 'COMPROBANTE' AND ruta_interna IS NOT NULL THEN tipo_entidad || ':' || TO_CHAR(id_entidad) || ':' || version END)~');
    ejecutar('CREATE INDEX ix_documentos_carpeta ON documentos_repositorio (id_carpeta)');
    ejecutar('CREATE INDEX ix_documentos_original ON documentos_repositorio (id_documento_original)');

    -- ---------- bitacora de accesos a documentos ----------
    ejecutar(q'~
CREATE TABLE accesos_documentos (
    id_acceso     NUMBER GENERATED ALWAYS AS IDENTITY,
    fecha         TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    id_documento  NUMBER,
    usuario       VARCHAR2(100 CHAR) NOT NULL,
    accion        VARCHAR2(20 CHAR)  NOT NULL,
    modo_clave    VARCHAR2(10 CHAR),
    ip            VARCHAR2(45 CHAR),
    user_agent    VARCHAR2(200 CHAR),
    detalle       VARCHAR2(300 CHAR),
    CONSTRAINT pk_accesos_documentos PRIMARY KEY (id_acceso),
    CONSTRAINT fk_accesos_documento FOREIGN KEY (id_documento) REFERENCES documentos_repositorio (id_documento)
)~');
    regla('accesos_documentos', 'ck_accesos_accion',
          q'~accion IN ('VER', 'DESCARGAR', 'DESCIFRAR', 'SUBIR', 'ARCHIVAR', 'CARPETA_CREAR', 'CARPETA_ARCHIVAR', 'SUBIDA_RECHAZADA')~');
    -- Descargar exige declarar con que clave se protegio la copia (solo el tipo, nunca la clave).
    regla('accesos_documentos', 'ck_accesos_clave',
          q'~(accion = 'DESCARGAR' AND modo_clave IN ('DOCUMENTO', 'ESCRITA', 'ALEATORIA')) OR (accion <> 'DESCARGAR' AND modo_clave IS NULL)~');
    ejecutar('CREATE INDEX ix_accesos_doc_documento ON accesos_documentos (id_documento, fecha)');
    ejecutar('CREATE INDEX ix_accesos_doc_usuario ON accesos_documentos (usuario, fecha)');
END;
/

COMMENT ON TABLE carpetas_archivos IS 'Carpetas manuales (solo ADMIN) para los archivos que sube; no se borran ni se renombran, se archivan';
COMMENT ON TABLE accesos_documentos IS 'Bitacora de solo insercion: quien vio, descargo o descifro un documento, con que tipo de clave, desde que IP';
COMMENT ON COLUMN documentos_repositorio.origen IS 'COMPROBANTE (PDF generado por el sistema) o ADMIN (archivo subido)';
COMMENT ON COLUMN documentos_repositorio.version IS 'ORIGINAL (congelado al registrar) o ANULADO (segundo PDF con marca de agua)';
COMMENT ON COLUMN documentos_repositorio.id_documento_original IS 'Solo en la version ANULADO: el PDF original, que no se toca';
COMMENT ON COLUMN documentos_repositorio.ruta_interna IS 'Nombre opaco del archivo cifrado en disco; nunca se muestra al cliente';
COMMENT ON COLUMN documentos_repositorio.checksum_sha256 IS 'SHA-256 del contenido SIN cifrar (en registros nuevos); en los legados, de lo subido a Drive';
COMMENT ON COLUMN documentos_repositorio.tamano_bytes IS 'Tamano del contenido sin cifrar (maximo 10 MB)';
COMMENT ON COLUMN documentos_repositorio.id_carpeta IS 'Carpeta manual (solo archivos subidos por el ADMIN); NULL = raiz';
COMMENT ON COLUMN documentos_repositorio.archivado IS '1 = archivado por el ADMIN con motivo; solo aplica a lo que el ADMIN subio';

-- ---------- Integridad polimorfica: ahora tambien los cinco comprobantes ----------
CREATE OR REPLACE TRIGGER trg_documentos_valida_entidad
BEFORE INSERT ON documentos_repositorio
FOR EACH ROW
DECLARE
    v_existe NUMBER := 0;
BEGIN
    IF :NEW.tipo_entidad = 'ARCHIVO' THEN
        RETURN;   -- archivo subido por el ADMIN: sin entidad (lo exige ck_documentos_forma)
    ELSIF :NEW.tipo_entidad = 'FACTURA' THEN
        SELECT COUNT(*) INTO v_existe FROM facturas WHERE id_factura = :NEW.id_entidad;
    ELSIF :NEW.tipo_entidad = 'NOTA_CREDITO' THEN
        SELECT COUNT(*) INTO v_existe FROM facturas_notas_credito WHERE id_nota = :NEW.id_entidad;
    ELSIF :NEW.tipo_entidad = 'VENTA' THEN
        SELECT COUNT(*) INTO v_existe FROM ventas WHERE id_venta = :NEW.id_entidad;
    ELSIF :NEW.tipo_entidad = 'ABONO' THEN
        SELECT COUNT(*) INTO v_existe FROM abonos_cartera WHERE id_recibo = :NEW.id_entidad AND ROWNUM = 1;
    ELSIF :NEW.tipo_entidad = 'PAGO_PROVEEDOR' THEN
        SELECT COUNT(*) INTO v_existe FROM pagos_proveedor WHERE id_pago = :NEW.id_entidad;
    ELSIF :NEW.tipo_entidad = 'COMPRA' THEN
        SELECT COUNT(*) INTO v_existe FROM compras_insumo WHERE id_compra = :NEW.id_entidad;
    ELSIF :NEW.tipo_entidad = 'GASTO' THEN
        SELECT COUNT(*) INTO v_existe FROM gastos_operativos WHERE id_gasto = :NEW.id_entidad;
    END IF;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe,
            'La entidad referenciada (' || :NEW.tipo_entidad || ' ' || :NEW.id_entidad || ') no existe.');
    END IF;
END trg_documentos_valida_entidad;
/

-- ---------- Lo escrito no se borra ni se edita ----------
CREATE OR REPLACE TRIGGER trg_documentos_inmutable
BEFORE UPDATE ON documentos_repositorio
FOR EACH ROW
DECLARE
    FUNCTION cambia(a IN VARCHAR2, b IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN RETURN NOT (a = b OR (a IS NULL AND b IS NULL)); END;
    FUNCTION cambia(a IN NUMBER, b IN NUMBER) RETURN BOOLEAN IS
    BEGIN RETURN NOT (a = b OR (a IS NULL AND b IS NULL)); END;
    FUNCTION cambia(a IN TIMESTAMP, b IN TIMESTAMP) RETURN BOOLEAN IS
    BEGIN RETURN NOT (a = b OR (a IS NULL AND b IS NULL)); END;
BEGIN
    -- Siempre inmutables
    IF cambia(:OLD.tipo_entidad, :NEW.tipo_entidad) OR cambia(:OLD.id_entidad, :NEW.id_entidad)
       OR cambia(:OLD.nombre_archivo, :NEW.nombre_archivo) OR cambia(:OLD.mime_type, :NEW.mime_type)
       OR cambia(:OLD.origen, :NEW.origen) OR cambia(:OLD.version, :NEW.version)
       OR cambia(:OLD.id_documento_original, :NEW.id_documento_original)
       OR cambia(:OLD.id_carpeta, :NEW.id_carpeta)
       OR cambia(:OLD.usuario_carga, :NEW.usuario_carga) OR cambia(:OLD.fecha_registro, :NEW.fecha_registro) THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Un documento no se modifica.');
    END IF;
    -- Una vez puestos (los registros legados nacieron sin ellos), no cambian
    IF (:OLD.ruta_interna IS NOT NULL AND cambia(:OLD.ruta_interna, :NEW.ruta_interna))
       OR (:OLD.tamano_bytes IS NOT NULL AND cambia(:OLD.tamano_bytes, :NEW.tamano_bytes))
       OR (:OLD.checksum_sha256 IS NOT NULL AND cambia(:OLD.checksum_sha256, :NEW.checksum_sha256)) THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Un documento no se modifica.');
    END IF;
    -- El archivado es de una sola vía
    IF :OLD.archivado = 1 AND (:NEW.archivado = 0 OR cambia(:OLD.motivo_archivo, :NEW.motivo_archivo)
                               OR cambia(:OLD.usuario_archivo, :NEW.usuario_archivo)
                               OR cambia(:OLD.fecha_archivo, :NEW.fecha_archivo)) THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Un documento archivado no se desarchiva.');
    END IF;
END trg_documentos_inmutable;
/

CREATE OR REPLACE TRIGGER trg_documentos_nodelete
BEFORE DELETE ON documentos_repositorio
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Un documento no se borra: se archiva.');
END trg_documentos_nodelete;
/

CREATE OR REPLACE TRIGGER trg_carpetas_inmutable
BEFORE UPDATE ON carpetas_archivos
FOR EACH ROW
DECLARE
    FUNCTION cambia(a IN VARCHAR2, b IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN RETURN NOT (a = b OR (a IS NULL AND b IS NULL)); END;
    FUNCTION cambia(a IN NUMBER, b IN NUMBER) RETURN BOOLEAN IS
    BEGIN RETURN NOT (a = b OR (a IS NULL AND b IS NULL)); END;
    FUNCTION cambia(a IN TIMESTAMP, b IN TIMESTAMP) RETURN BOOLEAN IS
    BEGIN RETURN NOT (a = b OR (a IS NULL AND b IS NULL)); END;
BEGIN
    IF cambia(:OLD.id_padre, :NEW.id_padre) OR cambia(:OLD.nombre, :NEW.nombre)
       OR cambia(:OLD.usuario_creacion, :NEW.usuario_creacion) OR cambia(:OLD.fecha_creacion, :NEW.fecha_creacion) THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Una carpeta no se renombra ni se mueve.');
    END IF;
    IF :OLD.archivada = 1 AND (:NEW.archivada = 0 OR cambia(:OLD.motivo_archivo, :NEW.motivo_archivo)
                               OR cambia(:OLD.usuario_archivo, :NEW.usuario_archivo)
                               OR cambia(:OLD.fecha_archivo, :NEW.fecha_archivo)) THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Una carpeta archivada no se desarchiva.');
    END IF;
END trg_carpetas_inmutable;
/

CREATE OR REPLACE TRIGGER trg_carpetas_nodelete
BEFORE DELETE ON carpetas_archivos
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Una carpeta no se borra: se archiva.');
END trg_carpetas_nodelete;
/

CREATE OR REPLACE TRIGGER trg_ro_accesos_documentos
BEFORE UPDATE OR DELETE ON accesos_documentos
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'La bitacora de accesos a documentos es de solo insercion.');
END trg_ro_accesos_documentos;
/

-- ---------- Vistas ----------
-- Un renglon por archivo fisico, con los datos del comprobante cuando lo hay. ruta_interna es SOLO para el backend:
-- el DTO que va al dashboard no debe incluirla.
CREATE OR REPLACE VIEW vw_archivos AS
SELECT d.id_documento, d.origen, d.tipo_entidad, d.id_entidad, d.version, d.id_documento_original,
       d.nombre_archivo, d.mime_type, d.tamano_bytes, d.checksum_sha256, d.ruta_interna,
       d.id_carpeta, f.nombre AS carpeta,
       d.archivado, d.motivo_archivo, d.usuario_archivo, d.fecha_archivo,
       d.estado_carga AS estado_drive, d.fecha_carga AS fecha_drive, d.intentos, d.ultimo_error,
       d.usuario_carga, d.fecha_registro,
       c.numero, c.sentido, c.fecha AS fecha_comprobante, c.monto,
       c.id_tercero, c.tercero_tipo, c.tercero, c.estado AS estado_comprobante,
       c.id_periodo, p.anio, p.mes, p.quincena
  FROM documentos_repositorio d
  LEFT JOIN vw_comprobantes c ON d.origen = 'COMPROBANTE' AND c.tipo = d.tipo_entidad AND c.id_documento = d.id_entidad
  LEFT JOIN periodos_quincena p ON p.id_periodo = c.id_periodo
  LEFT JOIN carpetas_archivos f ON f.id_carpeta = d.id_carpeta
 WHERE d.ruta_interna IS NOT NULL
WITH READ ONLY;

-- Carpetas virtuales de los comprobantes: en que "carpetas" aparece cada PDF. Tres arboles que se solapan:
--   TIPO:      Ventas / 2026 / Enero - quincena 1
--   CLIENTE:   Clientes / <cliente> / 2026
--   PROVEEDOR: Proveedores / <proveedor> / 2026
-- nN_clave sirve para navegar y ordenar (texto estable); nN es lo que se muestra.
CREATE OR REPLACE VIEW vw_archivos_ubicaciones AS
SELECT a.id_documento, 'TIPO' AS arbol,
       a.tipo_entidad AS n1_clave,
       CASE a.tipo_entidad WHEN 'VENTA' THEN 'Ventas' WHEN 'ABONO' THEN 'Abonos'
            WHEN 'PAGO_PROVEEDOR' THEN 'Pagos a proveedores' WHEN 'COMPRA' THEN 'Compras'
            WHEN 'GASTO' THEN 'Gastos' ELSE a.tipo_entidad END AS n1,
       TO_CHAR(a.anio) AS n2_clave, TO_CHAR(a.anio) AS n2,
       LPAD(a.mes, 2, '0') || '-' || a.quincena AS n3_clave,
       INITCAP(TRIM(TO_CHAR(TO_DATE(a.mes, 'MM'), 'Month', 'NLS_DATE_LANGUAGE=SPANISH'))) || ' - quincena ' || a.quincena AS n3
  FROM vw_archivos a
 WHERE a.origen = 'COMPROBANTE'
UNION ALL
SELECT a.id_documento, 'CLIENTE', 'CLIENTE', 'Clientes',
       TO_CHAR(a.id_tercero), a.tercero,
       TO_CHAR(a.anio), TO_CHAR(a.anio)
  FROM vw_archivos a
 WHERE a.origen = 'COMPROBANTE' AND a.tercero_tipo = 'CLIENTE' AND a.id_tercero IS NOT NULL   -- compras sin proveedor: no tienen carpeta de tercero
UNION ALL
SELECT a.id_documento, 'PROVEEDOR', 'PROVEEDOR', 'Proveedores',
       TO_CHAR(a.id_tercero), a.tercero,
       TO_CHAR(a.anio), TO_CHAR(a.anio)
  FROM vw_archivos a
 WHERE a.origen = 'COMPROBANTE' AND a.tercero_tipo = 'PROVEEDOR' AND a.id_tercero IS NOT NULL   -- compras sin proveedor: no tienen carpeta de tercero
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_carpetas_archivos AS
SELECT c.id_carpeta, c.id_padre, c.nombre, LTRIM(SYS_CONNECT_BY_PATH(c.nombre, '/'), '/') AS ruta, LEVEL AS nivel,
       c.archivada, c.motivo_archivo, c.usuario_archivo, c.fecha_archivo,
       c.usuario_creacion, c.fecha_creacion,
       (SELECT COUNT(*) FROM documentos_repositorio d WHERE d.id_carpeta = c.id_carpeta AND d.archivado = 0) AS n_archivos,
       (SELECT COUNT(*) FROM carpetas_archivos h WHERE h.id_padre = c.id_carpeta AND h.archivada = 0) AS n_subcarpetas
  FROM carpetas_archivos c
 START WITH c.id_padre IS NULL
CONNECT BY PRIOR c.id_carpeta = c.id_padre
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_accesos_documentos AS
SELECT x.id_acceso, x.fecha, x.id_documento, d.nombre_archivo, d.tipo_entidad, d.id_entidad, d.version,
       x.usuario, x.accion, x.modo_clave, x.ip, x.user_agent, x.detalle
  FROM accesos_documentos x
  LEFT JOIN documentos_repositorio d ON d.id_documento = x.id_documento
WITH READ ONLY;

-- Comprobantes que aun no tienen su PDF (el backend los genera: reintento si fallo al registrar).
-- OJO: incluye tambien los movimientos ANTERIORES a esta funcion; el backend debe filtrar por fecha de corte.
CREATE OR REPLACE VIEW vw_comprobantes_sin_pdf AS
SELECT c.tipo, c.id_documento AS id_entidad, c.numero, c.fecha, c.estado, 'ORIGINAL' AS version_faltante
  FROM vw_comprobantes c
 WHERE c.estado = 'VIGENTE'
   AND NOT EXISTS (SELECT 1 FROM documentos_repositorio d
                    WHERE d.origen = 'COMPROBANTE' AND d.ruta_interna IS NOT NULL AND d.version = 'ORIGINAL'
                      AND d.tipo_entidad = c.tipo AND d.id_entidad = c.id_documento)
UNION ALL
SELECT c.tipo, c.id_documento, c.numero, c.fecha, c.estado, 'ANULADO'
  FROM vw_comprobantes c
 WHERE c.estado = 'ANULADO'
   AND EXISTS (SELECT 1 FROM documentos_repositorio d
                WHERE d.origen = 'COMPROBANTE' AND d.ruta_interna IS NOT NULL AND d.version = 'ORIGINAL'
                  AND d.tipo_entidad = c.tipo AND d.id_entidad = c.id_documento)
   AND NOT EXISTS (SELECT 1 FROM documentos_repositorio d
                    WHERE d.origen = 'COMPROBANTE' AND d.ruta_interna IS NOT NULL AND d.version = 'ANULADO'
                      AND d.tipo_entidad = c.tipo AND d.id_entidad = c.id_documento)
WITH READ ONLY;

-- ---------- pkg_archivos ----------
CREATE OR REPLACE PACKAGE pkg_archivos AUTHID DEFINER AS
    c_nivel_maximo  CONSTANT PLS_INTEGER := 5;          -- profundidad maxima de carpetas manuales
    c_tamano_maximo CONSTANT PLS_INTEGER := 10485760;   -- 10 MB

    -- PDF de un comprobante, ya generado y cifrado por el backend. OPERATIVO.
    -- ORIGINAL: el comprobante debe estar VIGENTE. ANULADO: debe estar ANULADO y tener ORIGINAL.
    PROCEDURE sp_registrar_comprobante(
        p_tipo        IN  VARCHAR2,
        p_id_entidad  IN  NUMBER,
        p_version     IN  VARCHAR2,
        p_nombre      IN  VARCHAR2,
        p_ruta        IN  VARCHAR2,
        p_tamano      IN  NUMBER,
        p_sha256      IN  VARCHAR2,
        p_id_documento OUT NUMBER
    );
    -- Archivo subido por el ADMIN (ya escaneado, validado y cifrado por el backend). p_id_carpeta NULL = raiz.
    PROCEDURE sp_registrar_subida(
        p_nombre       IN  VARCHAR2,
        p_mime         IN  VARCHAR2,
        p_ruta         IN  VARCHAR2,
        p_tamano       IN  NUMBER,
        p_sha256       IN  VARCHAR2,
        p_id_carpeta   IN  NUMBER,
        p_id_documento OUT NUMBER,
        p_ip           IN  VARCHAR2 DEFAULT NULL,
        p_user_agent   IN  VARCHAR2 DEFAULT NULL
    );
    PROCEDURE sp_archivar_documento(
        p_id_documento IN NUMBER, p_motivo IN VARCHAR2,
        p_ip IN VARCHAR2 DEFAULT NULL, p_user_agent IN VARCHAR2 DEFAULT NULL
    );
    PROCEDURE sp_crear_carpeta(
        p_id_padre IN NUMBER, p_nombre IN VARCHAR2, p_id_carpeta OUT NUMBER,
        p_ip IN VARCHAR2 DEFAULT NULL, p_user_agent IN VARCHAR2 DEFAULT NULL
    );
    -- Solo si no tiene archivos ni subcarpetas activas.
    PROCEDURE sp_archivar_carpeta(
        p_id_carpeta IN NUMBER, p_motivo IN VARCHAR2,
        p_ip IN VARCHAR2 DEFAULT NULL, p_user_agent IN VARCHAR2 DEFAULT NULL
    );
    -- Lecturas (VER, DESCARGAR, DESCIFRAR) y subidas rechazadas. El backend lo llama ANTES de entregar los bytes.
    -- p_modo_clave solo en DESCARGAR: DOCUMENTO, ESCRITA o ALEATORIA (el tipo, nunca la clave).
    PROCEDURE sp_registrar_acceso(
        p_id_documento IN NUMBER,
        p_accion       IN VARCHAR2,
        p_modo_clave   IN VARCHAR2,
        p_detalle      IN VARCHAR2,
        p_ip           IN VARCHAR2,
        p_user_agent   IN VARCHAR2
    );
END pkg_archivos;
/
CREATE OR REPLACE PACKAGE BODY pkg_archivos AS

    PROCEDURE pr_log(p_id_documento IN NUMBER, p_accion IN VARCHAR2, p_modo IN VARCHAR2, p_detalle IN VARCHAR2,
                     p_ip IN VARCHAR2, p_ua IN VARCHAR2) IS
    BEGIN
        INSERT INTO accesos_documentos (id_documento, usuario, accion, modo_clave, ip, user_agent, detalle)
        VALUES (p_id_documento, pkg_seguridad.fn_usuario_actual, p_accion, p_modo,
                SUBSTR(p_ip, 1, 45), SUBSTR(p_ua, 1, 200), SUBSTR(p_detalle, 1, 300));
    END pr_log;

    PROCEDURE pr_validar_binario(p_ruta IN VARCHAR2, p_tamano IN NUMBER, p_sha256 IN VARCHAR2) IS
    BEGIN
        IF p_ruta IS NULL OR NOT REGEXP_LIKE(p_ruta, '^[a-f0-9]{32}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Ruta interna invalida.');
        END IF;
        IF p_tamano IS NULL OR p_tamano < 1 OR p_tamano > c_tamano_maximo OR p_tamano <> TRUNC(p_tamano) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'El archivo debe pesar entre 1 byte y ' || (c_tamano_maximo / 1048576) || ' MB.');
        END IF;
        IF p_sha256 IS NULL OR NOT REGEXP_LIKE(p_sha256, '^[A-Fa-f0-9]{64}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Huella SHA-256 invalida.');
        END IF;
    END pr_validar_binario;

    -- Nombre que se MUESTRA (jamas toca el disco): sin separadores de ruta ni caracteres de control.
    FUNCTION fn_nombre_visible(p_nombre IN VARCHAR2) RETURN VARCHAR2 IS
        v VARCHAR2(255 CHAR) := TRIM(p_nombre);
    BEGIN
        IF v IS NULL OR LENGTH(v) < 3 OR LENGTH(v) > 255 OR INSTR(v, '/') > 0 OR INSTR(v, '\') > 0
           OR REGEXP_LIKE(v, '[[:cntrl:]]') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Nombre de archivo invalido (3 a 255 caracteres, sin barras ni caracteres de control).');
        END IF;
        RETURN v;
    END fn_nombre_visible;

    PROCEDURE sp_registrar_comprobante(
        p_tipo IN VARCHAR2, p_id_entidad IN NUMBER, p_version IN VARCHAR2, p_nombre IN VARCHAR2,
        p_ruta IN VARCHAR2, p_tamano IN NUMBER, p_sha256 IN VARCHAR2, p_id_documento OUT NUMBER
    ) IS
        v_estado   VARCHAR2(10);
        v_original NUMBER;
        v_nombre   VARCHAR2(255 CHAR);
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_tipo IS NULL OR p_tipo NOT IN ('VENTA', 'ABONO', 'PAGO_PROVEEDOR', 'COMPRA', 'GASTO')
           OR p_id_entidad IS NULL OR p_version IS NULL OR p_version NOT IN ('ORIGINAL', 'ANULADO') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Tipo, entidad o version invalidos.');
        END IF;
        v_nombre := fn_nombre_visible(p_nombre);
        IF NOT REGEXP_LIKE(LOWER(v_nombre), '\.pdf$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Un comprobante es un archivo .pdf.');
        END IF;
        pr_validar_binario(p_ruta, p_tamano, p_sha256);

        BEGIN
            SELECT estado INTO v_estado FROM vw_comprobantes WHERE tipo = p_tipo AND id_documento = p_id_entidad;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe,
                    'El comprobante (' || p_tipo || ' ' || p_id_entidad || ') no existe.');
        END;

        IF p_version = 'ORIGINAL' THEN
            IF v_estado <> 'VIGENTE' THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                    'El PDF original se genera al registrar; este comprobante ya esta anulado.');
            END IF;
            v_original := NULL;
        ELSE
            IF v_estado <> 'ANULADO' THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'Solo un comprobante anulado tiene version ANULADO.');
            END IF;
            BEGIN
                SELECT id_documento INTO v_original FROM documentos_repositorio
                 WHERE origen = 'COMPROBANTE' AND ruta_interna IS NOT NULL AND version = 'ORIGINAL'
                   AND tipo_entidad = p_tipo AND id_entidad = p_id_entidad;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                        'No hay PDF original de este comprobante: la version ANULADO cuelga de el.');
            END;
        END IF;

        INSERT INTO documentos_repositorio (tipo_entidad, id_entidad, nombre_archivo, mime_type, origen, version,
                                            id_documento_original, ruta_interna, tamano_bytes, checksum_sha256,
                                            usuario_carga)
        VALUES (p_tipo, p_id_entidad, v_nombre, 'application/pdf', 'COMPROBANTE', p_version,
                v_original, p_ruta, p_tamano, LOWER(p_sha256), pkg_seguridad.fn_usuario_actual)
        RETURNING id_documento INTO p_id_documento;
        COMMIT;
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK;
            p_id_documento := NULL;
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'Ese comprobante ya tiene su PDF ' || p_version || ' (o la ruta interna ya existe).');
        WHEN OTHERS THEN
            p_id_documento := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_comprobante', p_tipo || ' id=' || p_id_entidad);
    END sp_registrar_comprobante;

    PROCEDURE sp_registrar_subida(
        p_nombre IN VARCHAR2, p_mime IN VARCHAR2, p_ruta IN VARCHAR2, p_tamano IN NUMBER, p_sha256 IN VARCHAR2,
        p_id_carpeta IN NUMBER, p_id_documento OUT NUMBER, p_ip IN VARCHAR2 DEFAULT NULL, p_user_agent IN VARCHAR2 DEFAULT NULL
    ) IS
        v_nombre   VARCHAR2(255 CHAR);
        v_archivada NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        v_nombre := fn_nombre_visible(p_nombre);
        IF p_mime IS NULL OR p_mime NOT IN ('application/pdf', 'image/jpeg', 'image/png') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Solo se admiten PDF, JPG y PNG.');
        END IF;
        -- La extension debe corresponder al tipo real (el backend ya verifico los primeros bytes)
        IF NOT ((p_mime = 'application/pdf' AND REGEXP_LIKE(LOWER(v_nombre), '\.pdf$'))
             OR (p_mime = 'image/jpeg'      AND REGEXP_LIKE(LOWER(v_nombre), '\.(jpg|jpeg)$'))
             OR (p_mime = 'image/png'       AND REGEXP_LIKE(LOWER(v_nombre), '\.png$'))) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La extension no corresponde al tipo de archivo.');
        END IF;
        pr_validar_binario(p_ruta, p_tamano, p_sha256);

        IF p_id_carpeta IS NOT NULL THEN
            BEGIN
                SELECT archivada INTO v_archivada FROM carpetas_archivos WHERE id_carpeta = p_id_carpeta FOR UPDATE WAIT 10;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La carpeta no existe.');
            END;
            IF v_archivada = 1 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La carpeta esta archivada.');
            END IF;
        END IF;

        INSERT INTO documentos_repositorio (tipo_entidad, id_entidad, nombre_archivo, mime_type, origen, version,
                                            ruta_interna, tamano_bytes, checksum_sha256, id_carpeta, usuario_carga)
        VALUES ('ARCHIVO', NULL, v_nombre, p_mime, 'ADMIN', 'ORIGINAL',
                p_ruta, p_tamano, LOWER(p_sha256), p_id_carpeta, pkg_seguridad.fn_usuario_actual)
        RETURNING id_documento INTO p_id_documento;
        pr_log(p_id_documento, 'SUBIR', NULL, v_nombre, p_ip, p_user_agent);
        COMMIT;
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK;
            p_id_documento := NULL;
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La ruta interna ya existe.');
        WHEN OTHERS THEN
            p_id_documento := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_subida', 'carpeta=' || p_id_carpeta);
    END sp_registrar_subida;

    PROCEDURE sp_archivar_documento(p_id_documento IN NUMBER, p_motivo IN VARCHAR2, p_ip IN VARCHAR2 DEFAULT NULL,
                                    p_user_agent IN VARCHAR2 DEFAULT NULL) IS
        v_origen    VARCHAR2(11);
        v_archivado NUMBER;
        v_motivo    VARCHAR2(255 CHAR) := TRIM(p_motivo);
        v_usuario   VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_documento IS NULL OR v_motivo IS NULL OR LENGTH(v_motivo) < 5 OR LENGTH(v_motivo) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El motivo es obligatorio (5 a 255 caracteres).');
        END IF;
        BEGIN
            SELECT origen, archivado INTO v_origen, v_archivado FROM documentos_repositorio
             WHERE id_documento = p_id_documento AND ruta_interna IS NOT NULL FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El documento no existe.');
        END;
        IF v_origen <> 'ADMIN' THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'Los comprobantes del sistema nunca se archivan ni se borran.');
        END IF;
        IF v_archivado = 1 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'El documento ya esta archivado.');
        END IF;
        UPDATE documentos_repositorio
           SET archivado = 1, motivo_archivo = v_motivo, usuario_archivo = v_usuario,
               fecha_archivo = CAST(SYSTIMESTAMP AS TIMESTAMP)
         WHERE id_documento = p_id_documento;
        pr_log(p_id_documento, 'ARCHIVAR', NULL, v_motivo, p_ip, p_user_agent);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_archivar_documento', 'id_documento=' || p_id_documento);
    END sp_archivar_documento;

    PROCEDURE sp_crear_carpeta(p_id_padre IN NUMBER, p_nombre IN VARCHAR2, p_id_carpeta OUT NUMBER,
                               p_ip IN VARCHAR2 DEFAULT NULL, p_user_agent IN VARCHAR2 DEFAULT NULL) IS
        v_nombre    VARCHAR2(80 CHAR) := TRIM(p_nombre);
        v_archivada NUMBER;
        v_nivel     PLS_INTEGER := 0;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF v_nombre IS NULL OR LENGTH(v_nombre) > 80 OR INSTR(v_nombre, '/') > 0 OR INSTR(v_nombre, '\') > 0
           OR REGEXP_LIKE(v_nombre, '[[:cntrl:]]') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Nombre de carpeta invalido (1 a 80 caracteres, sin barras ni caracteres de control).');
        END IF;
        IF p_id_padre IS NOT NULL THEN
            BEGIN
                SELECT archivada INTO v_archivada FROM carpetas_archivos WHERE id_carpeta = p_id_padre FOR UPDATE WAIT 10;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La carpeta padre no existe.');
            END;
            IF v_archivada = 1 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La carpeta padre esta archivada.');
            END IF;
            SELECT COUNT(*) INTO v_nivel FROM carpetas_archivos START WITH id_carpeta = p_id_padre
            CONNECT BY id_carpeta = PRIOR id_padre;
            IF v_nivel >= c_nivel_maximo THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                    'Maximo ' || c_nivel_maximo || ' niveles de carpetas.');
            END IF;
        END IF;
        INSERT INTO carpetas_archivos (id_padre, nombre, usuario_creacion)
        VALUES (p_id_padre, v_nombre, pkg_seguridad.fn_usuario_actual)
        RETURNING id_carpeta INTO p_id_carpeta;
        pr_log(NULL, 'CARPETA_CREAR', NULL, 'id=' || p_id_carpeta || '; ' || v_nombre, p_ip, p_user_agent);
        COMMIT;
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK;
            p_id_carpeta := NULL;
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'Ya existe una carpeta con ese nombre ahi.');
        WHEN OTHERS THEN
            p_id_carpeta := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_carpeta', 'padre=' || p_id_padre);
    END sp_crear_carpeta;

    PROCEDURE sp_archivar_carpeta(p_id_carpeta IN NUMBER, p_motivo IN VARCHAR2, p_ip IN VARCHAR2 DEFAULT NULL,
                                  p_user_agent IN VARCHAR2 DEFAULT NULL) IS
        v_archivada NUMBER;
        v_n         NUMBER;
        v_motivo    VARCHAR2(255 CHAR) := TRIM(p_motivo);
        v_usuario   VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_carpeta IS NULL OR v_motivo IS NULL OR LENGTH(v_motivo) < 5 OR LENGTH(v_motivo) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El motivo es obligatorio (5 a 255 caracteres).');
        END IF;
        BEGIN
            SELECT archivada INTO v_archivada FROM carpetas_archivos WHERE id_carpeta = p_id_carpeta FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La carpeta no existe.');
        END;
        IF v_archivada = 1 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La carpeta ya esta archivada.');
        END IF;
        SELECT (SELECT COUNT(*) FROM documentos_repositorio WHERE id_carpeta = p_id_carpeta AND archivado = 0)
             + (SELECT COUNT(*) FROM carpetas_archivos WHERE id_padre = p_id_carpeta AND archivada = 0)
          INTO v_n FROM dual;
        IF v_n > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'La carpeta tiene archivos o subcarpetas activas: archivelos primero.');
        END IF;
        UPDATE carpetas_archivos
           SET archivada = 1, motivo_archivo = v_motivo, usuario_archivo = v_usuario,
               fecha_archivo = CAST(SYSTIMESTAMP AS TIMESTAMP)
         WHERE id_carpeta = p_id_carpeta;
        pr_log(NULL, 'CARPETA_ARCHIVAR', NULL, 'id=' || p_id_carpeta || '; ' || v_motivo, p_ip, p_user_agent);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_archivar_carpeta', 'id_carpeta=' || p_id_carpeta);
    END sp_archivar_carpeta;

    PROCEDURE sp_registrar_acceso(p_id_documento IN NUMBER, p_accion IN VARCHAR2, p_modo_clave IN VARCHAR2,
                                  p_detalle IN VARCHAR2, p_ip IN VARCHAR2, p_user_agent IN VARCHAR2) IS
    BEGIN
        IF p_accion IS NULL OR p_accion NOT IN ('VER', 'DESCARGAR', 'DESCIFRAR', 'SUBIDA_RECHAZADA') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Accion de acceso invalida.');
        END IF;
        -- Solo el ADMIN sube; lo demas lo hacen ADMIN y OPERATIVO
        pkg_seguridad.sp_exigir_rol(CASE WHEN p_accion = 'SUBIDA_RECHAZADA' THEN pkg_seguridad.c_rol_admin
                                         ELSE pkg_seguridad.c_rol_operativo END);
        IF p_accion = 'DESCARGAR' AND (p_modo_clave IS NULL OR p_modo_clave NOT IN ('DOCUMENTO', 'ESCRITA', 'ALEATORIA')) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'La descarga debe declarar el tipo de clave: DOCUMENTO, ESCRITA o ALEATORIA.');
        END IF;
        IF p_accion <> 'DESCARGAR' AND p_modo_clave IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Solo la descarga lleva tipo de clave.');
        END IF;
        IF p_accion IN ('VER', 'DESCARGAR') AND p_id_documento IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Falta el documento.');
        END IF;
        pr_log(p_id_documento, p_accion, p_modo_clave, p_detalle, p_ip, p_user_agent);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_acceso', p_accion || ' doc=' || p_id_documento);
    END sp_registrar_acceso;

END pkg_archivos;
/

-- ---------- Permisos ----------
GRANT EXECUTE ON pkg_archivos TO __ROL_APP__;
GRANT SELECT ON vw_archivos              TO __ROL_APP__;
GRANT SELECT ON vw_archivos_ubicaciones  TO __ROL_APP__;
GRANT SELECT ON vw_carpetas_archivos     TO __ROL_APP__;
GRANT SELECT ON vw_accesos_documentos    TO __ROL_APP__;
GRANT SELECT ON vw_comprobantes_sin_pdf  TO __ROL_APP__;

-- Lo que depende de documentos_repositorio queda invalido al alterar la tabla: compilarlo ya.
ALTER VIEW vw_documentos COMPILE;
ALTER VIEW vw_documentos_pendientes_carga COMPILE;
ALTER VIEW vw_notificaciones COMPILE;
ALTER PACKAGE pkg_documentos COMPILE BODY;

-- Verificacion: todo debe estar VALID
SELECT object_name, object_type, status FROM user_objects
 WHERE status <> 'VALID' AND object_name IN
   ('PKG_ARCHIVOS', 'PKG_DOCUMENTOS', 'VW_DOCUMENTOS', 'VW_DOCUMENTOS_PENDIENTES_CARGA', 'VW_NOTIFICACIONES', 'VW_ARCHIVOS', 'VW_ARCHIVOS_UBICACIONES', 'VW_CARPETAS_ARCHIVOS', 'VW_ACCESOS_DOCUMENTOS',
    'VW_COMPROBANTES_SIN_PDF', 'TRG_DOCUMENTOS_VALIDA_ENTIDAD', 'TRG_DOCUMENTOS_INMUTABLE', 'TRG_DOCUMENTOS_NODELETE',
    'TRG_CARPETAS_INMUTABLE', 'TRG_CARPETAS_NODELETE', 'TRG_RO_ACCESOS_DOCUMENTOS');
SHOW ERRORS
