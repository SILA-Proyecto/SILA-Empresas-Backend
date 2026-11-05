package com.llanolat.sila.fotos;

import com.llanolat.sila.archivos.Imagenes.Imagen;
import com.llanolat.sila.infra.SilaTemplate;
import java.sql.Blob;
import java.sql.CallableStatement;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Lectura de vw_usuario_foto y escritura por pkg_fotos: la base saca de la sesion de quien sube la foto (nadie sube la de
 * otro) y exige ADMIN para quitar la ajena.
 */
@Repository
public class FotoRepository {

    public record Foto(byte[] contenido, String tipo, String sha256) {}

    private final SilaTemplate sila;
    private final JdbcClient jdbc;

    FotoRepository(SilaTemplate sila, JdbcClient jdbc) {
        this.sila = sila;
        this.jdbc = jdbc;
    }

    Optional<Foto> de(long idUsuario) {
        return jdbc.sql("SELECT contenido, tipo, sha256 FROM vw_usuario_foto WHERE id_usuario = :id")
                .param("id", idUsuario)
                .query((rs, i) -> new Foto(rs.getBytes(1), rs.getString(2), rs.getString(3))).optional();
    }

    /** Primeros 16 caracteres de la huella (cambia con la foto), o vacio si no tiene. */
    public Optional<String> version(long idUsuario) {
        return jdbc.sql("SELECT SUBSTR(sha256, 1, 16) FROM vw_usuario_foto WHERE id_usuario = :id")
                .param("id", idUsuario).query(String.class).optional();
    }

    void fijarMia(Imagen img) {
        sila.ejecutar(c -> {
            Blob blob = c.createBlob();
            try (CallableStatement s = c.prepareCall("{call pkg_fotos.sp_fijar_mi_foto(?,?,?)}")) {
                blob.setBytes(1, img.contenido());
                s.setBlob(1, blob);
                s.setString(2, img.tipo());
                s.setString(3, img.sha256());
                s.execute();
                return null;
            } finally {
                blob.free();
            }
        });
    }

    void quitar(long idUsuario) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_fotos.sp_quitar_foto(?)}")) {
                s.setLong(1, idUsuario);
                s.execute();
                return null;
            }
        });
    }
}
