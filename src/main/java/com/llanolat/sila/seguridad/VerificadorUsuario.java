package com.llanolat.sila.seguridad;

import com.llanolat.sila.infra.SilaTemplate;
import java.sql.CallableStatement;
import java.sql.Types;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Comprueba, en cada peticion con token de acceso, que la persona siga ACTIVA, conserve el
 * MISMO rol que dice su token y que su SESION no se haya cerrado. Asi desactivar a alguien o cambiarle el rol surte efecto en
 * segundos, sin esperar a que venza el token (15 min). Se cachea 30 s por usuario para no
 * consultar la base en cada llamada; los cambios hechos desde este mismo backend invalidan
 * la entrada al instante.
 *
 * Si la base no responde, falla CERRADO: sin poder verificar, no se deja pasar.
 */
@Component
public class VerificadorUsuario {

    private static final Logger log = LoggerFactory.getLogger(VerificadorUsuario.class);
    private static final long TTL_NANOS = 30_000_000_000L;

    private record Estado(boolean activo, String rol, boolean sesionAbierta, long expira) {}

    private final SilaTemplate sila;
    private final Map<String, Estado> cache = new ConcurrentHashMap<>();

    public VerificadorUsuario(SilaTemplate sila) { this.sila = sila; }

    /** true si la persona existe, esta activa, conserva el rol del token y su SESION sigue abierta. */
    public boolean vigente(long idUsuario, String rolDelToken, String sesion) {
        if (sesion == null || sesion.isBlank()) {
            return false;   // token sin sesion (anterior a este cambio): obliga a renovar
        }
        long ahora = System.nanoTime();
        String clave = idUsuario + ":" + sesion;
        Estado e = cache.get(clave);
        if (e == null || e.expira() < ahora) {
            try {
                e = consultar(idUsuario, sesion, ahora + TTL_NANOS);
            } catch (RuntimeException ex) {
                log.error("No se pudo verificar al usuario {}; se rechaza el token.", idUsuario, ex);
                return false;
            }
            cache.put(clave, e);
        }
        return e.activo() && e.sesionAbierta() && e.rol() != null && e.rol().equals(rolDelToken);
    }

    /** Llamar tras desactivar, activar, cambiar el rol o cerrar sesiones de alguien: afecta a todas sus sesiones. */
    public void invalidar(long idUsuario) {
        String prefijo = idUsuario + ":";
        cache.keySet().removeIf(k -> k.startsWith(prefijo));
    }

    /** Llamar tras cerrar UNA sesion. */
    public void invalidar(long idUsuario, String sesion) {
        cache.remove(idUsuario + ":" + sesion);
    }

    private Estado consultar(long idUsuario, String sesion, long expira) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_estado_usuario.sp_consultar(?,?,?,?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, sesion);
                s.registerOutParameter(3, Types.NUMERIC);
                s.registerOutParameter(4, Types.VARCHAR);
                s.registerOutParameter(5, Types.NUMERIC);
                s.execute();
                int activo = s.getInt(3);
                boolean existe = !s.wasNull();
                return new Estado(existe && activo == 1, s.getString(4), s.getInt(5) == 1, expira);
            }
        });
    }
}
