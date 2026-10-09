package com.llanolat.sila.seguridad;

import com.llanolat.sila.infra.SilaTemplate;
import java.sql.CallableStatement;
import java.time.Duration;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Registra los eventos de acceso (quien, que, desde que IP y navegador) en la bitacora de Oracle
 * (eventos_acceso, solo insercion) y en el log del servidor. Nunca lanza: un fallo al registrar no
 * debe tumbar un login. Los intentos con usuarios inexistentes se limitan por IP para que nadie
 * pueda inflar la bitacora probando nombres.
 */
@Component
public class AccesoRegistrador {

    private static final Logger log = LoggerFactory.getLogger("sila.acceso");

    private final SilaTemplate sila;
    private final LimiteTasa limite;

    public AccesoRegistrador(SilaTemplate sila, LimiteTasa limite) {
        this.sila = sila;
        this.limite = limite;
    }

    public void registrar(String usuario, String evento, String ip, String userAgent, String detalle) {
        String u = limpiar(usuario, 100);
        String i = limpiar(ip, 45);
        String d = limpiar(detalle, 200);
        // Un nombre inventado por un atacante se ve en el log, pero no llena la tabla sin limite.
        boolean guardarEnBd = !"USUARIO_DESCONOCIDO".equals(evento) || limite.permitir("evt-desconocido:" + i, 20, Duration.ofHours(1));
        log.info("acceso evento={} usuario={} ip={} detalle={}", evento, u, i, d);
        if (!guardarEnBd) {
            return;
        }
        try {
            sila.ejecutarSinSesion(c -> {
                try (CallableStatement s = c.prepareCall("{call pkg_accesos.sp_registrar(?,?,?,?,?)}")) {
                    s.setString(1, u);
                    s.setString(2, evento);
                    s.setString(3, i);
                    s.setString(4, limpiar(userAgent, 200));
                    s.setString(5, d);
                    s.execute();
                    return null;
                }
            });
        } catch (RuntimeException e) {
            log.error("No se pudo registrar el evento de acceso {}", evento, e);
        }
    }

    /** Quita saltos de linea y caracteres de control (evita falsificar lineas del log) y acota el largo. */
    static String limpiar(String texto, int max) {
        if (texto == null) {
            return null;
        }
        String t = texto.replaceAll("[\\p{Cntrl}]", " ").trim();
        return t.length() > max ? t.substring(0, max) : t;
    }
}
