package com.llanolat.sila.legal;

import com.llanolat.sila.infra.SilaTemplate;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Lee vw_aceptaciones_estado (lo minimo: sin IP ni navegador) y escribe SOLO por pkg_legal.sp_aceptar, que toma la persona de
 * la sesion de aplicacion: nadie acepta por otro. La app no tiene permiso sobre la tabla.
 */
@Repository
public class LegalRepository {

    /** Una aceptacion ya registrada (de cualquier version). */
    public record Aceptacion(String documento, String version, LocalDateTime fecha) {}

    private final SilaTemplate sila;
    private final JdbcClient jdbc;

    LegalRepository(SilaTemplate sila, JdbcClient jdbc) {
        this.sila = sila;
        this.jdbc = jdbc;
    }

    List<Aceptacion> deUsuario(long idUsuario) {
        return jdbc.sql("SELECT documento, version, fecha FROM vw_aceptaciones_estado WHERE id_usuario = :id")
                .param("id", idUsuario)
                .query((rs, i) -> new Aceptacion(rs.getString(1), rs.getString(2), rs.getTimestamp(3).toLocalDateTime()))
                .list();
    }

    /** Escribe las que falten en una sola transaccion y devuelve cuantas eran nuevas (0, 1 o 2). */
    int aceptar(String versionTerminos, String versionPrivacidad, String ip, String userAgent) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_legal.sp_aceptar(?,?,?,?,?)}")) {
                s.setString(1, versionTerminos);
                s.setString(2, versionPrivacidad);
                s.setString(3, ip);
                s.setString(4, userAgent);
                s.registerOutParameter(5, Types.INTEGER);
                s.execute();
                return s.getInt(5);
            }
        });
    }
}
