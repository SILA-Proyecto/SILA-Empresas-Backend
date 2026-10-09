package com.llanolat.sila.seguridad.usuarios;

import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.SilaTemplate;
import com.llanolat.sila.infra.Texto;
import java.sql.CallableStatement;
import java.sql.Types;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Lectura de vw_usuarios y escritura por pkg_usuarios (todo ADMIN: lo exige la base). */
@Repository
class UsuarioRepository {

    private static final String COLUMNAS = """
            id_usuario, usuario, nombre, email, rol, activo, debe_cambiar_clave, mfa_activo,
            bloqueado, bloqueado_minutos, ultimo_login, fecha_cambio_clave, fecha_creacion""";

    private static final Map<String, String> ORDEN = Map.of(
            "id_usuario", "id_usuario", "usuario", "usuario", "nombre", "nombre", "email", "email",
            "rol", "rol", "activo", "activo", "ultimo_login", "ultimo_login", "fecha_creacion", "fecha_creacion");

    private final SilaTemplate sila;
    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    UsuarioRepository(SilaTemplate sila, ConsultaPaginada paginada, JdbcClient jdbc) {
        this.sila = sila;
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    Page<UsuarioDto> listar(String texto, Boolean activo, String rol, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (texto != null && !texto.isBlank()) {
            f.cuando("(" + Texto.comoSinAcentos("nombre") + " OR LOWER(usuario) LIKE '%' || LOWER(:q) || '%'"
                    + " OR LOWER(email) LIKE '%' || LOWER(:q) || '%')")
             .param("q", texto.trim())
             .param("conAcento", Texto.ACENTOS)
             .param("sinAcento", Texto.SIN_ACENTOS);
        }
        if (activo != null) {
            f.cuando("activo = :activo").param("activo", activo ? 1 : 0);
        }
        if (rol != null && !rol.isBlank()) {
            f.cuando("rol = :rol").param("rol", rol.trim().toUpperCase());
        }
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN, "nombre,asc", "id_usuario");
        return paginada.consultar(COLUMNAS, "vw_usuarios", f, pag, UsuarioDto.class);
    }

    Optional<UsuarioDto> porId(long id) {
        return jdbc.sql("SELECT " + COLUMNAS + " FROM vw_usuarios WHERE id_usuario = :id")
                   .param("id", id).query(UsuarioDto.class).optional();
    }

    long crear(String usuario, String nombre, String email, String rol, String hashTemporal) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_usuarios.sp_crear_usuario(?,?,?,?,?,?)}")) {
                s.setString(1, usuario);
                s.setString(2, nombre);
                s.setString(3, email);
                s.setString(4, rol);
                s.setString(5, hashTemporal);
                s.registerOutParameter(6, Types.NUMERIC);
                s.execute();
                return s.getLong(6);
            }
        });
    }

    void actualizar(long id, String nombre, String email, String rol) {
        llamar("{call pkg_usuarios.sp_actualizar_usuario(?,?,?,?)}", s -> {
            s.setLong(1, id);
            s.setString(2, nombre);
            s.setString(3, email);
            s.setString(4, rol);
        });
    }

    void cambiarEstado(long id, boolean activo) {
        llamar("{call pkg_usuarios.sp_cambiar_estado(?,?)}", s -> {
            s.setLong(1, id);
            s.setInt(2, activo ? 1 : 0);
        });
    }

    void desbloquear(long id) {
        llamar("{call pkg_usuarios.sp_desbloquear(?)}", s -> s.setLong(1, id));
    }

    void restablecerClave(long id, String hashTemporal) {
        llamar("{call pkg_usuarios.sp_restablecer_clave(?,?)}", s -> {
            s.setLong(1, id);
            s.setString(2, hashTemporal);
        });
    }

    void restablecerMfa(long id) {
        llamar("{call pkg_usuarios.sp_restablecer_mfa(?)}", s -> s.setLong(1, id));
    }

    void cerrarSesiones(long id) {
        llamar("{call pkg_usuarios.sp_cerrar_sesiones(?)}", s -> s.setLong(1, id));
    }

    record SesionActiva(String familia, java.time.LocalDateTime iniciada, java.time.LocalDateTime ultimaActividad,
                        String ip, String userAgent) {}

    java.util.List<SesionActiva> sesionesActivas(long id) {
        return jdbc.sql("SELECT familia, iniciada, ultima_actividad, ip, user_agent FROM vw_sesiones_activas "
                      + "WHERE id_usuario = :id ORDER BY ultima_actividad DESC")
                   .param("id", id).query(SesionActiva.class).list();
    }

    @FunctionalInterface
    private interface Parametros {
        void poner(CallableStatement s) throws java.sql.SQLException;
    }

    private void llamar(String sql, Parametros parametros) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(sql)) {
                parametros.poner(s);
                s.execute();
                return null;
            }
        });
    }
}
