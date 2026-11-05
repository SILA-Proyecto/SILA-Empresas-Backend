package com.llanolat.sila.empresa;

import com.llanolat.sila.infra.SilaException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Set;
import org.springframework.http.MediaType;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Empresa SUSPENDIDA por el dueno (sql/empresa.sh suspender): 403 / 20021 EMPRESA_SUSPENDIDA a TODO, con o sin sesion
 * (login, refresh, tokens vigentes y el del asistente), salvo lo que necesita la pantalla de login para mostrar el aviso:
 * GET /empresa/publica, GET /empresa/logo, el logout (para borrar la cookie) y /actuator/health.
 * Va antes de autenticar (y despues de CORS, para que el navegador pueda leer la respuesta). El estado viene de la copia de
 * EmpresaService (30 s): la suspension se nota en menos de un minuto; la base ademas se niega al instante (pkg_seguridad).
 * No es un componente de Spring: se registra solo en la cadena de seguridad.
 */
public class EstadoEmpresaFilter extends OncePerRequestFilter {

    private static final Set<String> GET_PERMITIDOS = Set.of("/api/v1/empresa/publica", "/api/v1/empresa/logo");

    private final EmpresaService empresa;

    public EstadoEmpresaFilter(EmpresaService empresa) {
        this.empresa = empresa;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        if (permitida(req.getMethod(), req.getRequestURI()) || !empresa.suspendida()) {
            chain.doFilter(req, res);
            return;
        }
        res.setStatus(HttpServletResponse.SC_FORBIDDEN);
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        res.setCharacterEncoding(StandardCharsets.UTF_8.name());
        res.getWriter().write("{\"code\":" + SilaException.EMPRESA_SUSPENDIDA + ",\"message\":\"" + EmpresaService.MENSAJE_SUSPENDIDA + "\"}");
    }

    static boolean permitida(String metodo, String uri) {
        if ("OPTIONS".equals(metodo)) return true;
        if (uri.equals("/actuator/health") || uri.startsWith("/actuator/health/")) return true;
        if ("POST".equals(metodo) && uri.equals("/api/v1/auth/logout")) return true;
        return "GET".equals(metodo) && GET_PERMITIDOS.contains(uri);
    }
}
