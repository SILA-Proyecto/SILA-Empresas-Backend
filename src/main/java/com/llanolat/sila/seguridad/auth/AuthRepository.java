package com.llanolat.sila.seguridad.auth;

import com.llanolat.sila.infra.SilaTemplate;
import java.sql.CallableStatement;
import java.sql.Types;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Llamadas a pkg_autenticacion. Corren SIN sesion de aplicacion: el login ocurre antes
 * de saber quien es la persona, y esos procedimientos no exigen rol.
 */
@Repository
class AuthRepository {

    private final SilaTemplate sila;
    private final JdbcClient jdbc;

    AuthRepository(SilaTemplate sila, JdbcClient jdbc) {
        this.sila = sila;
        this.jdbc = jdbc;
    }

    Optional<Credencial> porUsuario(String usuario) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_autenticacion.sp_obtener_credencial(?,?,?,?,?,?,?,?,?,?,?,?)}")) {
                s.setString(1, usuario);
                registrarSalidas(s, Types.NUMERIC);
                s.execute();
                long id = s.getLong(2);
                if (s.wasNull()) return Optional.empty();
                return Optional.of(leer(s, id, usuario, 3));
            }
        });
    }

    Optional<Credencial> porId(long idUsuario) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_autenticacion.sp_obtener_por_id(?,?,?,?,?,?,?,?,?,?,?,?)}")) {
                s.setLong(1, idUsuario);
                registrarSalidas(s, Types.VARCHAR);
                s.execute();
                String usuario = s.getString(2);
                if (usuario == null) return Optional.empty();
                return Optional.of(leer(s, idUsuario, usuario, 3));
            }
        });
    }

    /** Salidas comunes a ambos procedimientos; la primera es el id (por usuario) o el usuario (por id). */
    private static void registrarSalidas(CallableStatement s, int tipoPrimera) throws java.sql.SQLException {
        s.registerOutParameter(2, tipoPrimera);
        s.registerOutParameter(3, Types.VARCHAR);   // nombre
        s.registerOutParameter(4, Types.VARCHAR);   // email
        s.registerOutParameter(5, Types.VARCHAR);   // rol
        s.registerOutParameter(6, Types.VARCHAR);   // hash
        s.registerOutParameter(7, Types.NUMERIC);   // activo
        s.registerOutParameter(8, Types.NUMERIC);   // bloqueado_min
        s.registerOutParameter(9, Types.NUMERIC);   // debe_cambiar
        s.registerOutParameter(10, Types.NUMERIC);  // mfa_activo
        s.registerOutParameter(11, Types.VARCHAR);  // mfa_secreto
        s.registerOutParameter(12, Types.NUMERIC);  // mfa_ultimo_paso
    }

    private static Credencial leer(CallableStatement s, long id, String usuario, int desde) throws java.sql.SQLException {
        String nombre = s.getString(desde);
        String email = s.getString(desde + 1);
        String rol = s.getString(desde + 2);
        String hash = s.getString(desde + 3);
        boolean activo = s.getInt(desde + 4) == 1;
        int bloqueadoMin = s.getInt(desde + 5);
        boolean debeCambiar = s.getInt(desde + 6) == 1;
        boolean mfaActivo = s.getInt(desde + 7) == 1;
        String mfaSecreto = s.getString(desde + 8);
        long paso = s.getLong(desde + 9);
        Long mfaPaso = s.wasNull() ? null : paso;
        return new Credencial(id, usuario, nombre, email, rol, hash, activo, bloqueadoMin,
                              debeCambiar, mfaActivo, mfaSecreto, mfaPaso);
    }

    /** Devuelve los minutos de bloqueo que quedaron (0 = la cuenta no se bloqueo). */
    int loginFallido(String usuario, String motivo) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_autenticacion.sp_login_fallido(?,?,?)}")) {
                s.setString(1, usuario);
                s.setString(2, motivo);
                s.registerOutParameter(3, Types.NUMERIC);
                s.execute();
                return s.getInt(3);
            }
        });
    }

    void loginOk(long idUsuario) {
        sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_autenticacion.sp_login_ok(?)}")) {
                s.setLong(1, idUsuario);
                s.execute();
                return null;
            }
        });
    }

    void cambiarClave(long idUsuario, String hash) {
        sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_autenticacion.sp_cambiar_clave(?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, hash);
                s.execute();
                return null;
            }
        });
    }

    void actualizarPerfil(long idUsuario, String nombre, String email) {
        sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_perfil.sp_actualizar_mis_datos(?,?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, nombre);
                s.setString(3, email);
                s.execute();
                return null;
            }
        });
    }

    void mfaGuardarSecreto(long idUsuario, String secretoCifrado) {
        sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_autenticacion.sp_mfa_guardar_secreto(?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, secretoCifrado);
                s.execute();
                return null;
            }
        });
    }

    void mfaActivar(long idUsuario, long paso) {
        sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_autenticacion.sp_mfa_activar(?,?)}")) {
                s.setLong(1, idUsuario);
                s.setLong(2, paso);
                s.execute();
                return null;
            }
        });
    }

    /** false si el codigo (su paso de 30 s) ya se uso. */
    boolean mfaConsumirPaso(long idUsuario, long paso) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_autenticacion.sp_mfa_consumir_paso(?,?,?)}")) {
                s.setLong(1, idUsuario);
                s.setLong(2, paso);
                s.registerOutParameter(3, Types.NUMERIC);
                s.execute();
                return s.getInt(3) == 1;
            }
        });
    }

    void crearSesion(long idUsuario, String familia, String tokenHash, long segundos, String ip, String userAgent) {
        sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_autenticacion.sp_crear_sesion(?,?,?,?,?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, familia);
                s.setString(3, tokenHash);
                s.setLong(4, segundos);
                s.setString(5, ip);
                s.setString(6, userAgent);
                s.execute();
                return null;
            }
        });
    }

    record Rotacion(Long idUsuario, String estado, String familia) {}

    Rotacion rotarSesion(String hashViejo, String hashNuevo, long segundos, String ip, String userAgent) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_autenticacion.sp_rotar_sesion(?,?,?,?,?,?,?,?)}")) {
                s.setString(1, hashViejo);
                s.setString(2, hashNuevo);
                s.setLong(3, segundos);
                s.setString(4, ip);
                s.setString(5, userAgent);
                s.registerOutParameter(6, Types.NUMERIC);
                s.registerOutParameter(7, Types.VARCHAR);
                s.registerOutParameter(8, Types.VARCHAR);
                s.execute();
                long id = s.getLong(6);
                return new Rotacion(s.wasNull() ? null : id, s.getString(7), s.getString(8));
            }
        });
    }

    /** Cierra la sesion a la que pertenece ese token de renovacion; devuelve a quien y cual era (o null). */
    Rotacion revocarSesion(String tokenHash) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_autenticacion.sp_revocar_sesion(?,?,?)}")) {
                s.setString(1, tokenHash);
                s.registerOutParameter(2, Types.NUMERIC);
                s.registerOutParameter(3, Types.VARCHAR);
                s.execute();
                long id = s.getLong(2);
                return s.wasNull() ? null : new Rotacion(id, "OK", s.getString(3));
            }
        });
    }

    // ---------- codigos de respaldo del segundo factor ----------

    void reemplazarCodigosRespaldo(long idUsuario, List<String> hashes) {
        sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_respaldo_mfa.sp_reemplazar(?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, String.join(",", hashes));
                s.execute();
                return null;
            }
        });
    }

    record ConsumoRespaldo(boolean ok, int restantes) {}

    ConsumoRespaldo consumirCodigoRespaldo(long idUsuario, String hash) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_respaldo_mfa.sp_consumir(?,?,?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, hash);
                s.registerOutParameter(3, Types.NUMERIC);
                s.registerOutParameter(4, Types.NUMERIC);
                s.execute();
                return new ConsumoRespaldo(s.getInt(3) == 1, s.getInt(4));
            }
        });
    }

    int codigosRestantes(long idUsuario) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_respaldo_mfa.sp_restantes(?,?)}")) {
                s.setLong(1, idUsuario);
                s.registerOutParameter(2, Types.NUMERIC);
                s.execute();
                return s.getInt(2);
            }
        });
    }

    // ---------- sesiones ----------

    record Sesion(String familia, java.time.LocalDateTime iniciada, java.time.LocalDateTime ultimaActividad,
                  String ip, String userAgent) {}

    List<Sesion> sesionesActivas(long idUsuario) {
        return jdbc.sql("SELECT familia, iniciada, ultima_actividad, ip, user_agent FROM vw_sesiones_activas "
                      + "WHERE id_usuario = :id ORDER BY ultima_actividad DESC")
                   .param("id", idUsuario).query(Sesion.class).list();
    }

    int revocarFamilia(long idUsuario, String familia) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_sesiones.sp_revocar_familia(?,?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, familia);
                s.registerOutParameter(3, Types.NUMERIC);
                s.execute();
                return s.getInt(3);
            }
        });
    }

    /** Todas las sesiones de la persona menos {@code conservar} (null = todas). */
    int revocarTodas(long idUsuario, String conservar) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_sesiones.sp_revocar_todas(?,?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, conservar);
                s.registerOutParameter(3, Types.NUMERIC);
                s.execute();
                return s.getInt(3);
            }
        });
    }
}
