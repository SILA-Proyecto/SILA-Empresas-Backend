package com.llanolat.sila.infra.idempotencia;

import com.llanolat.sila.infra.SilaTemplate;
import java.sql.CallableStatement;
import java.sql.Types;
import org.springframework.stereotype.Repository;

/** Llamadas a pkg_idempotencia (sin sesion de aplicacion: la identidad ya viene validada del token). */
@Repository
public class IdempotenciaRepository {

    public enum Resultado { NUEVA, EN_PROCESO, REPETIDA, CONFLICTO }

    public record Reserva(Resultado resultado, int http, String respuesta) {}

    private final SilaTemplate sila;

    public IdempotenciaRepository(SilaTemplate sila) { this.sila = sila; }

    Reserva reservar(String usuario, String clave, String huella) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_idempotencia.sp_reservar(?,?,?,?,?,?)}")) {
                s.setString(1, usuario);
                s.setString(2, clave);
                s.setString(3, huella);
                s.registerOutParameter(4, Types.VARCHAR);
                s.registerOutParameter(5, Types.NUMERIC);
                s.registerOutParameter(6, Types.CLOB);
                s.execute();
                return new Reserva(Resultado.valueOf(s.getString(4)), s.getInt(5), s.getString(6));
            }
        });
    }

    void completar(String usuario, String clave, int http, String respuesta) {
        sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_idempotencia.sp_completar(?,?,?,?)}")) {
                s.setString(1, usuario);
                s.setString(2, clave);
                s.setInt(3, http);
                s.setCharacterStream(4, new java.io.StringReader(respuesta), respuesta.length());
                s.execute();
                return null;
            }
        });
    }

    void liberar(String usuario, String clave) {
        sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_idempotencia.sp_liberar(?,?)}")) {
                s.setString(1, usuario);
                s.setString(2, clave);
                s.execute();
                return null;
            }
        });
    }
}
