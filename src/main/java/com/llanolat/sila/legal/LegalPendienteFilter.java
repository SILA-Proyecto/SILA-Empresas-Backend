package com.llanolat.sila.legal;

import com.llanolat.sila.infra.SilaException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Quien no ha aceptado los terminos y la politica de privacidad VIGENTES recibe 403 / 20022 LEGAL_PENDIENTE en toda la API
 * salvo en una lista cerrada de rutas (todo lo demas queda bloqueado por defecto): /auth/** (entrar, salir, cambiar la clave,
 * el segundo factor, /auth/yo), /legal/**, el nombre y el logo del login, la propia foto y /actuator/health.
 * Solo mira tokens de ACCESO (tambien el del asistente: n8n no ve datos de quien no ha aceptado); sin sesion responde la
 * cadena (401). Si no se puede comprobar, falla CERRADO: 503 / 20019, nunca deja pasar. Va despues de autenticar.
 * No es un componente de Spring: se registra solo en la cadena de seguridad en modo jwt (en modo desarrollo no aplica).
 */
public class LegalPendienteFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger("sila.legal");

    private final LegalService legal;

    public LegalPendienteFilter(LegalService legal) {
        this.legal = legal;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        if (permitida(req.getMethod(), req.getRequestURI())) {
            chain.doFilter(req, res);
            return;
        }
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (!(auth != null && auth.getPrincipal() instanceof Jwt jwt && "acceso".equals(jwt.getClaimAsString("tipo")))) {
            chain.doFilter(req, res);   // sin sesion o token temporal: la cadena responde (401 / 403)
            return;
        }
        try {
            if (jwt.getClaim("uid") instanceof Number uid && legal.alDia(uid.longValue())) {
                chain.doFilter(req, res);
                return;
            }
        } catch (RuntimeException e) {
            log.error("No se pudo comprobar la aceptacion legal; se rechaza la peticion.", e);
            escribir(res, HttpServletResponse.SC_SERVICE_UNAVAILABLE, SilaException.SERVICIO_NO_DISPONIBLE,
                    "No se pudo comprobar la aceptación de los términos. Intente de nuevo en un momento.");
            return;
        }
        escribir(res, HttpServletResponse.SC_FORBIDDEN, SilaException.LEGAL_PENDIENTE, LegalService.MENSAJE_PENDIENTE);
    }

    /** Lo unico que una persona sin aceptar puede usar. Todo lo demas, bloqueado. */
    static boolean permitida(String metodo, String uri) {
        if ("OPTIONS".equals(metodo)) return true;
        if (uri.equals("/actuator/health") || uri.startsWith("/actuator/health/")) return true;
        if (uri.startsWith("/api/v1/auth/") || uri.equals("/api/v1/legal") || uri.startsWith("/api/v1/legal/")) return true;
        return "GET".equals(metodo) && (uri.equals("/api/v1/empresa/publica") || uri.equals("/api/v1/empresa/logo")
                || uri.equals("/api/v1/fotos/yo"));
    }

    private static void escribir(HttpServletResponse res, int http, int code, String mensaje) throws IOException {
        res.setStatus(http);
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        res.setCharacterEncoding(StandardCharsets.UTF_8.name());
        res.getWriter().write("{\"code\":" + code + ",\"message\":\"" + mensaje + "\"}");
    }
}
