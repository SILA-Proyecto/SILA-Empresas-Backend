package com.llanolat.sila.empresa;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Bloquea las rutas de los modulos apagados con 403 / 20020 MODULO_INACTIVO, para TODOS los tokens (incluido el de solo
 * lectura del asistente: n8n tampoco las ve). Va despues de autenticar: quien no tiene sesion sigue recibiendo 401,
 * y asi no se averigua que modulos tiene una empresa sin iniciar sesion (salvo las rutas publicas de un modulo, como
 * el retorno de Drive). No es un componente de Spring: se registra solo en la cadena de seguridad.
 * El mapa ruta -> modulo esta en {@link MapaModulos}.
 */
public class ModuloFilter extends OncePerRequestFilter {

    private final EmpresaService empresa;

    public ModuloFilter(EmpresaService empresa) {
        this.empresa = empresa;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        if ("OPTIONS".equals(req.getMethod())) {
            chain.doFilter(req, res);
            return;
        }
        Optional<MapaModulos.Regla> regla = MapaModulos.de(req.getMethod(), req.getRequestURI());
        if (regla.isEmpty() || regla.get().modulo() == null) {
            chain.doFilter(req, res);
            return;
        }
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        boolean conSesion = auth != null && auth.isAuthenticated() && !(auth instanceof AnonymousAuthenticationToken);
        if (!conSesion && !regla.get().publica()) {
            chain.doFilter(req, res);   // sin sesion: la cadena responde 401
            return;
        }
        if (empresa.activo(regla.get().modulo())) {
            chain.doFilter(req, res);
            return;
        }
        res.setStatus(HttpServletResponse.SC_FORBIDDEN);
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        res.setCharacterEncoding(StandardCharsets.UTF_8.name());
        res.getWriter().write("{\"code\":20020,\"message\":\"" + EmpresaService.MENSAJE_INACTIVO + "\"}");
    }
}
