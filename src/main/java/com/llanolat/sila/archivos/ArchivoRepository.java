package com.llanolat.sila.archivos;

import com.llanolat.sila.archivos.Archivos.AccesoDocumento;
import com.llanolat.sila.archivos.Archivos.Archivo;
import com.llanolat.sila.archivos.Archivos.Carpeta;
import com.llanolat.sila.archivos.Archivos.Entrada;
import com.llanolat.sila.archivos.Archivos.Interno;
import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Identidad;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.SilaTemplate;
import com.llanolat.sila.infra.SilaTemplate.Operacion;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Acceso a datos de archivos: escritura por pkg_archivos (la base valida roles y reglas) y lectura por vistas.
 * Los metodos con {@code sistema} corren con la identidad de sistema (sin peticion HTTP); los demas, con la de quien
 * hace la peticion.
 */
@Repository
public class ArchivoRepository {

    /** Columnas publicas de vw_archivos (sin ruta_interna), con alias de tabla "a". */
    static final String COLUMNAS = """
            a.id_documento, a.origen, a.tipo_entidad, a.id_entidad, a.version, a.id_documento_original,
            a.nombre_archivo, a.mime_type, a.tamano_bytes, a.checksum_sha256, a.id_carpeta, a.carpeta,
            a.archivado, a.motivo_archivo, a.usuario_archivo, a.fecha_archivo,
            a.estado_drive, a.fecha_drive, a.usuario_carga, a.fecha_registro,
            NVL(a.fecha_comprobante, TRUNC(a.fecha_registro)) AS fecha, a.numero, a.sentido, a.monto,
            a.id_tercero, a.tercero_tipo, a.tercero, a.estado_comprobante, a.id_periodo, a.anio, a.mes, a.quincena""";

    private static final Map<String, String> ORDEN = Map.of(
            "fecha", "NVL(a.fecha_comprobante, TRUNC(a.fecha_registro))", "nombre", "a.nombre_archivo",
            "tamano", "a.tamano_bytes", "monto", "a.monto", "tercero", "a.tercero", "numero", "a.numero",
            "fecha_registro", "a.fecha_registro", "id", "a.id_documento");

    private static final String INTERNO = """
            SELECT id_documento, ruta_interna, mime_type, nombre_archivo, checksum_sha256, origen, tipo_entidad, id_entidad,
                   version, id_tercero, tercero_tipo, tercero, archivado FROM vw_archivos""";

    private final SilaTemplate sila;
    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public ArchivoRepository(SilaTemplate sila, ConsultaPaginada paginada, JdbcClient jdbc) {
        this.sila = sila;
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    private <T> T correr(String sistema, Operacion<T> op) {
        return sistema == null ? sila.ejecutar(op) : sila.ejecutarComo(sistema, Identidad.ROL_OPERATIVO, op);
    }

    // ------------------------------------------------------------- escritura

    /** @param sistema usuario de sistema, o null para usar la identidad de la peticion */
    public long registrarComprobante(String sistema, String tipo, long idEntidad, String version, String nombre,
                                     String ruta, long tamano, String sha256) {
        return correr(sistema, c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_archivos.sp_registrar_comprobante(?,?,?,?,?,?,?,?)}")) {
                s.setString(1, tipo);
                s.setLong(2, idEntidad);
                s.setString(3, version);
                s.setString(4, nombre);
                s.setString(5, ruta);
                s.setLong(6, tamano);
                s.setString(7, sha256);
                s.registerOutParameter(8, Types.NUMERIC);
                s.execute();
                return s.getLong(8);
            }
        });
    }

    public long registrarSubida(String nombre, String mime, String ruta, long tamano, String sha256, Long idCarpeta,
                                String ip, String userAgent) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_archivos.sp_registrar_subida(?,?,?,?,?,?,?,?,?)}")) {
                s.setString(1, nombre);
                s.setString(2, mime);
                s.setString(3, ruta);
                s.setLong(4, tamano);
                s.setString(5, sha256);
                if (idCarpeta == null) s.setNull(6, Types.NUMERIC); else s.setLong(6, idCarpeta);
                s.registerOutParameter(7, Types.NUMERIC);
                s.setString(8, ip);
                s.setString(9, userAgent);
                s.execute();
                return s.getLong(7);
            }
        });
    }

    public void archivarDocumento(long id, String motivo, String ip, String userAgent) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_archivos.sp_archivar_documento(?,?,?,?)}")) {
                s.setLong(1, id);
                s.setString(2, motivo);
                s.setString(3, ip);
                s.setString(4, userAgent);
                s.execute();
                return null;
            }
        });
    }

    public long crearCarpeta(Long idPadre, String nombre, String ip, String userAgent) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_archivos.sp_crear_carpeta(?,?,?,?,?)}")) {
                if (idPadre == null) s.setNull(1, Types.NUMERIC); else s.setLong(1, idPadre);
                s.setString(2, nombre);
                s.registerOutParameter(3, Types.NUMERIC);
                s.setString(4, ip);
                s.setString(5, userAgent);
                s.execute();
                return s.getLong(3);
            }
        });
    }

    public void archivarCarpeta(long id, String motivo, String ip, String userAgent) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_archivos.sp_archivar_carpeta(?,?,?,?)}")) {
                s.setLong(1, id);
                s.setString(2, motivo);
                s.setString(3, ip);
                s.setString(4, userAgent);
                s.execute();
                return null;
            }
        });
    }

    /** accion: VER | DESCARGAR | DESCIFRAR | SUBIDA_RECHAZADA. modoClave solo en DESCARGAR. */
    public void registrarAcceso(Long idDocumento, String accion, String modoClave, String detalle, String ip, String userAgent) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_archivos.sp_registrar_acceso(?,?,?,?,?,?)}")) {
                if (idDocumento == null) s.setNull(1, Types.NUMERIC); else s.setLong(1, idDocumento);
                s.setString(2, accion);
                s.setString(3, modoClave);
                s.setString(4, detalle);
                s.setString(5, ip);
                s.setString(6, userAgent);
                s.execute();
                return null;
            }
        });
    }

    /** Envio a Drive (proceso de sistema): marca el archivo como subido. */
    public void marcarSubido(String sistema, long id, String driveFileId, String driveUrl, String checksum) {
        correr(sistema, c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_documentos.sp_marcar_subido(?,?,?,?)}")) {
                s.setLong(1, id);
                s.setString(2, driveFileId);
                s.setString(3, driveUrl);
                s.setString(4, checksum);
                s.execute();
                return null;
            }
        });
    }

    public void marcarErrorDrive(String sistema, long id, String mensaje) {
        correr(sistema, c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_documentos.sp_marcar_error(?,?)}")) {
                s.setLong(1, id);
                s.setString(2, mensaje);
                s.execute();
                return null;
            }
        });
    }

    // --------------------------------------------------------------- lectura

    public Optional<Archivo> archivo(long id) {
        return jdbc.sql("SELECT " + COLUMNAS + " FROM vw_archivos a WHERE a.id_documento = :id")
                   .param("id", id).query(Archivo.class).optional();
    }

    Optional<Interno> interno(long id) {
        return jdbc.sql(INTERNO + " WHERE id_documento = :id").param("id", id).query(Interno.class).optional();
    }

    Optional<Interno> internoPorRuta(String ruta) {
        return jdbc.sql(INTERNO + " WHERE ruta_interna = :ruta").param("ruta", ruta).query(Interno.class).optional();
    }

    /** Los PDF de un comprobante: el original y, si se anulo, la version ANULADO. */
    public List<Archivo> deComprobante(String tipo, long idEntidad) {
        return jdbc.sql("SELECT " + COLUMNAS + " FROM vw_archivos a WHERE a.origen = 'COMPROBANTE' AND a.tipo_entidad = :t"
                        + " AND a.id_entidad = :id ORDER BY a.id_documento")
                   .param("t", tipo).param("id", idEntidad).query(Archivo.class).list();
    }

    public Page<Archivo> listar(String origen, String tipo, Boolean archivado, String estadoDrive, Long idCarpeta,
                                String version, String texto, LocalDate desde, LocalDate hasta,
                                Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (hay(origen)) f.cuando("a.origen = :origen").param("origen", origen.trim().toUpperCase());
        if (hay(tipo)) f.cuando("a.tipo_entidad = :tipo").param("tipo", tipo.trim().toUpperCase());
        if (archivado != null) f.cuando("a.archivado = :arch").param("arch", archivado ? 1 : 0);
        if (hay(estadoDrive)) f.cuando("a.estado_drive = :drive").param("drive", estadoDrive.trim().toUpperCase());
        if (idCarpeta != null) f.cuando("a.id_carpeta = :carpeta").param("carpeta", idCarpeta);
        if (hay(version)) f.cuando("a.version = :version").param("version", version.trim().toUpperCase());
        if (desde != null) f.cuando("NVL(a.fecha_comprobante, TRUNC(a.fecha_registro)) >= :f_desde").param("f_desde", desde);
        if (hasta != null) f.cuando("NVL(a.fecha_comprobante, TRUNC(a.fecha_registro)) <= :f_hasta").param("f_hasta", hasta);
        if (hay(texto)) {
            f.cuando("(LOWER(a.nombre_archivo) LIKE :q OR LOWER(a.numero) LIKE :q OR LOWER(a.tercero) LIKE :q)")
             .param("q", "%" + texto.trim().toLowerCase().replace("%", "").replace("_", "") + "%");
        }
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN, "fecha,desc", "a.id_documento");
        return paginada.consultar(COLUMNAS, "vw_archivos a", f, pag, Archivo.class);
    }

    // ----------------------------------------------------------- explorador

    /** Cuantos archivos hay en cada arbol virtual y en las carpetas manuales (para la raiz del explorador). */
    public Map<String, Long> conteoPorArbol() {
        Map<String, Long> r = new java.util.LinkedHashMap<>();
        r.put("TIPO", 0L); r.put("CLIENTE", 0L); r.put("PROVEEDOR", 0L); r.put("MANUAL", 0L);
        jdbc.sql("SELECT arbol, COUNT(*) FROM vw_archivos_ubicaciones GROUP BY arbol")
            .query((rs, n) -> { r.put(rs.getString(1), rs.getLong(2)); return null; }).list();
        r.put("MANUAL", jdbc.sql("SELECT COUNT(*) FROM vw_archivos WHERE origen = 'ADMIN' AND archivado = 0")
                            .query(Long.class).single());
        return r;
    }

    /**
     * Subcarpetas virtuales: agrupa por la columna del nivel siguiente. {@code claveCol}/{@code nombreCol} son nombres
     * de columna fijos del backend; {@code condiciones} compara las columnas ya fijadas por la ruta.
     */
    public List<Entrada> subcarpetasVirtuales(String arbol, String claveCol, String nombreCol, List<String> columnasFijas,
                                              List<String> valoresFijos, boolean ordenDescendente) {
        StringBuilder sql = new StringBuilder("SELECT " + claveCol + ", " + nombreCol + ", COUNT(*) FROM vw_archivos_ubicaciones WHERE arbol = :arbol");
        Map<String, Object> p = new java.util.HashMap<>();
        p.put("arbol", arbol);
        for (int i = 0; i < columnasFijas.size(); i++) {
            sql.append(" AND ").append(columnasFijas.get(i)).append(" = :v").append(i);
            p.put("v" + i, valoresFijos.get(i));
        }
        sql.append(" GROUP BY ").append(claveCol).append(", ").append(nombreCol)
           .append(" ORDER BY ").append(ordenDescendente ? claveCol + " DESC" : "LOWER(" + nombreCol + ") ASC");
        return jdbc.sql(sql.toString()).params(p)
                   .query((rs, n) -> new Entrada(rs.getString(1), rs.getString(2), rs.getLong(3))).list();
    }

    /** Archivos de una carpeta virtual (todas las columnas de la ruta fijadas). */
    public Page<Archivo> archivosVirtuales(String arbol, List<String> columnasFijas, List<String> valoresFijos,
                                           Integer page, Integer size, String sort) {
        Filtro f = new Filtro().cuando("u.arbol = :arbol").param("arbol", arbol);
        for (int i = 0; i < columnasFijas.size(); i++) {
            f.cuando("u." + columnasFijas.get(i) + " = :v" + i).param("v" + i, valoresFijos.get(i));
        }
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN, "fecha,desc", "a.id_documento");
        return paginada.consultar(COLUMNAS, "vw_archivos a JOIN vw_archivos_ubicaciones u ON u.id_documento = a.id_documento",
                f, pag, Archivo.class);
    }

    /** Nombres de la ruta (migas de pan) de una carpeta virtual: una fila cualquiera que la cumpla. */
    public Optional<String[]> nombresDeRuta(String arbol, List<String> columnasFijas, List<String> valoresFijos) {
        StringBuilder sql = new StringBuilder("SELECT n1, n2, n3 FROM vw_archivos_ubicaciones WHERE arbol = :arbol");
        Map<String, Object> p = new java.util.HashMap<>();
        p.put("arbol", arbol);
        for (int i = 0; i < columnasFijas.size(); i++) {
            sql.append(" AND ").append(columnasFijas.get(i)).append(" = :v").append(i);
            p.put("v" + i, valoresFijos.get(i));
        }
        sql.append(" FETCH FIRST 1 ROWS ONLY");
        return jdbc.sql(sql.toString()).params(p)
                   .query((rs, n) -> new String[] {rs.getString(1), rs.getString(2), rs.getString(3)}).optional();
    }

    public List<Carpeta> carpetasManuales(Long idPadre, boolean incluirArchivadas) {
        String sql = "SELECT id_carpeta, id_padre, nombre, ruta, nivel, archivada, motivo_archivo, usuario_archivo, fecha_archivo,"
                   + " usuario_creacion, fecha_creacion, n_archivos, n_subcarpetas FROM vw_carpetas_archivos WHERE "
                   + (idPadre == null ? "id_padre IS NULL" : "id_padre = :padre")
                   + (incluirArchivadas ? "" : " AND archivada = 0") + " ORDER BY LOWER(nombre)";
        var q = jdbc.sql(sql);
        if (idPadre != null) q = q.param("padre", idPadre);
        return q.query(Carpeta.class).list();
    }

    public Optional<Carpeta> carpeta(long id) {
        return jdbc.sql("SELECT id_carpeta, id_padre, nombre, ruta, nivel, archivada, motivo_archivo, usuario_archivo, fecha_archivo,"
                      + " usuario_creacion, fecha_creacion, n_archivos, n_subcarpetas FROM vw_carpetas_archivos WHERE id_carpeta = :id")
                   .param("id", id).query(Carpeta.class).optional();
    }

    public Page<Archivo> archivosDeCarpetaManual(Long idCarpeta, boolean incluirArchivados, Integer page, Integer size, String sort) {
        Filtro f = new Filtro().cuando("a.origen = 'ADMIN'");
        if (idCarpeta == null) f.cuando("a.id_carpeta IS NULL"); else f.cuando("a.id_carpeta = :carpeta").param("carpeta", idCarpeta);
        if (!incluirArchivados) f.cuando("a.archivado = 0");
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN, "fecha_registro,desc", "a.id_documento");
        return paginada.consultar(COLUMNAS, "vw_archivos a", f, pag, Archivo.class);
    }

    // ----------------------------------------------------------- bitacora

    public Page<AccesoDocumento> accesos(Long idDocumento, String usuario, String accion, Integer page, Integer size) {
        Filtro f = new Filtro();
        if (idDocumento != null) f.cuando("id_documento = :doc").param("doc", idDocumento);
        if (hay(usuario)) f.cuando("usuario = :usuario").param("usuario", usuario.trim());
        if (hay(accion)) f.cuando("accion = :accion").param("accion", accion.trim().toUpperCase());
        Paginacion pag = Paginacion.de(page, size, "fecha,desc", Map.of("fecha", "fecha"), "fecha,desc", "id_acceso");
        return paginada.consultar("id_acceso, fecha, id_documento, nombre_archivo, tipo_entidad, id_entidad, version, usuario,"
                + " accion, modo_clave, ip, user_agent, detalle", "vw_accesos_documentos", f, pag, AccesoDocumento.class);
    }

    // ------------------------------------------------------------- terceros

    /** Numero de documento registrado del cliente o proveedor (para la clave "documento de identidad"). */
    public Optional<String> numeroDocumentoDeTercero(String terceroTipo, long idTercero) {
        String sql = "CLIENTE".equals(terceroTipo)
                ? "SELECT numero_documento FROM vw_clientes WHERE id_cliente = :id AND UPPER(nombre) <> 'CONSUMIDOR FINAL'"
                : "SELECT numero_documento FROM vw_proveedores WHERE id_proveedor = :id";
        return jdbc.sql(sql).param("id", idTercero).query(String.class).optional();
    }

    // ----------------------------------------------------- reintento y Drive

    /** Fecha del movimiento mas antiguo que ya tiene PDF de comprobante: marca desde cuando el sistema genera PDF. */
    public Optional<LocalDate> fechaPrimerPdf() {
        return jdbc.sql("SELECT MIN(fecha_comprobante) FROM vw_archivos WHERE origen = 'COMPROBANTE'")
                   .query((rs, n) -> rs.getDate(1) == null ? null : rs.getDate(1).toLocalDate())
                   .list().stream().filter(java.util.Objects::nonNull).findFirst();
    }

    /** Comprobantes sin PDF desde la fecha de corte: [tipo, id, version]. */
    public List<String[]> sinPdf(LocalDate corte, int limite) {
        return jdbc.sql("SELECT tipo, id_entidad, version_faltante FROM vw_comprobantes_sin_pdf WHERE fecha >= :corte"
                      + " ORDER BY fecha, tipo, id_entidad FETCH FIRST :n ROWS ONLY")
                   .param("corte", corte).param("n", limite)
                   .query((rs, n) -> new String[] {rs.getString(1), String.valueOf(rs.getLong(2)), rs.getString(3)}).list();
    }

    /** Archivos que faltan por enviar a Drive: [id, ruta, checksum]. */
    public List<String[]> pendientesDrive(int limite) {
        return jdbc.sql("SELECT id_documento, ruta_interna, checksum_sha256 FROM vw_archivos"
                      + " WHERE estado_drive IN ('PENDIENTE', 'ERROR') ORDER BY id_documento FETCH FIRST :n ROWS ONLY")
                   .param("n", limite)
                   .query((rs, n) -> new String[] {String.valueOf(rs.getLong(1)), rs.getString(2), rs.getString(3)}).list();
    }

    /** [pendientes (PENDIENTE), con error (ERROR), subidos (SUBIDO)]. */
    public long[] conteoDrive() {
        long[] r = new long[3];
        jdbc.sql("SELECT estado_drive, COUNT(*) FROM vw_archivos GROUP BY estado_drive").query((rs, n) -> {
            switch (rs.getString(1)) {
                case "PENDIENTE" -> r[0] = rs.getLong(2);
                case "ERROR" -> r[1] = rs.getLong(2);
                case "SUBIDO" -> r[2] = rs.getLong(2);
                default -> { }
            }
            return null;
        }).list();
        return r;
    }

    private static boolean hay(String s) { return s != null && !s.isBlank(); }
}
