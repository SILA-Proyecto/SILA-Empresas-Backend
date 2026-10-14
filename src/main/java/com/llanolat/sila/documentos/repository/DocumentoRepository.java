package com.llanolat.sila.documentos.repository;

import com.llanolat.sila.documentos.dto.DocumentosDtos.Documento;
import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.SilaTemplate;
import java.sql.CallableStatement;
import java.sql.Types;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Documentos: escritura por pkg_documentos (rol OPERATIVO) y lectura por vw_documentos. */
@Repository
public class DocumentoRepository {

    private static final String COLUMNAS = """
            id_documento, tipo_entidad, id_entidad, nombre_archivo, mime_type, drive_url, checksum_sha256,
            estado_carga, intentos, ultimo_error, usuario_carga, fecha_registro, fecha_carga""";
    private static final Map<String, String> ORDEN = Map.of(
            "id_documento", "id_documento", "tipo_entidad", "tipo_entidad", "nombre_archivo", "nombre_archivo",
            "estado_carga", "estado_carga", "fecha_registro", "fecha_registro", "fecha_carga", "fecha_carga");

    private final SilaTemplate sila;
    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public DocumentoRepository(SilaTemplate sila, ConsultaPaginada paginada, JdbcClient jdbc) {
        this.sila = sila;
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    public long registrarPendiente(String tipoEntidad, long idEntidad, String nombre, String mimeType) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_documentos.sp_registrar_pendiente(?,?,?,?,?)}")) {
                s.setString(1, tipoEntidad);
                s.setLong(2, idEntidad);
                s.setString(3, nombre);
                s.setString(4, mimeType);
                s.registerOutParameter(5, Types.NUMERIC);
                s.execute();
                return s.getLong(5);
            }
        });
    }

    public void marcarSubido(long id, String driveFileId, String driveUrl, String checksum) {
        sila.ejecutar(c -> {
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

    public void marcarError(long id, String mensaje) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_documentos.sp_marcar_error(?,?)}")) {
                s.setLong(1, id);
                s.setString(2, mensaje);
                s.execute();
                return null;
            }
        });
    }

    public Optional<Documento> documento(long id) {
        return jdbc.sql("SELECT " + COLUMNAS + " FROM vw_documentos WHERE id_documento = :id")
                   .param("id", id).query(Documento.class).optional();
    }

    public Page<Documento> documentos(String tipoEntidad, Long idEntidad, String estado,
                                      Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (tipoEntidad != null && !tipoEntidad.isBlank()) f.cuando("tipo_entidad = :tipo").param("tipo", tipoEntidad.trim().toUpperCase());
        if (idEntidad != null) f.cuando("id_entidad = :idEntidad").param("idEntidad", idEntidad);
        if (estado != null && !estado.isBlank()) f.cuando("estado_carga = :estado").param("estado", estado.trim().toUpperCase());
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN, "fecha_registro,desc", "id_documento");
        return paginada.consultar(COLUMNAS, "vw_documentos", f, pag, Documento.class);
    }
}
