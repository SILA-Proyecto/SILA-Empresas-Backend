package com.llanolat.sila.seguridad;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Set;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.node.ObjectNode;

/**
 * Limita lo que puede hacer el token de SOLO LECTURA que recibe el asistente (claim ambito=lectura):
 *  - solo consultas GET sobre una lista cerrada de rutas de negocio (nada de usuarios, auditoria, archivos ni login);
 *  - en las respuestas quita los datos personales de contacto (documento, telefono, correo, direccion): el asistente no
 *    los necesita para responder y el modelo de lenguaje puede estar fuera del servidor.
 * Los permisos por rol siguen aplicando despues: un OPERATIVO no ve con el asistente nada que no vea en el dashboard.
 * No es un componente de Spring: se registra solo en la cadena de seguridad, para no filtrar el resto del trafico.
 */
public class AlcanceLecturaFilter extends OncePerRequestFilter {

    public static final String AMBITO = "lectura";

    private static final List<String> RUTAS = List.of(
            "/api/v1/catalogos", "/api/v1/ventas", "/api/v1/precios-cliente", "/api/v1/cartera",
            "/api/v1/cuentas-proveedores", "/api/v1/acopio", "/api/v1/produccion", "/api/v1/periodos",
            "/api/v1/insumos", "/api/v1/inventario", "/api/v1/finanzas", "/api/v1/comprobantes",
            "/api/v1/tablero", "/api/v1/reportes", "/api/v1/notificaciones", "/api/v1/parametros");

    /** Claves JSON (snake_case) que se eliminan de toda respuesta al asistente, a cualquier profundidad. */
    private static final Set<String> PERSONALES = Set.of(
            "tipo_documento", "numero_documento", "nit", "telefono", "email", "direccion");

    private final JsonMapper json;

    public AlcanceLecturaFilter(JsonMapper json) {
        this.json = json;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (!(auth != null && auth.getPrincipal() instanceof Jwt jwt && AMBITO.equals(jwt.getClaimAsString("ambito")))) {
            chain.doFilter(req, res);
            return;
        }
        if (!"GET".equals(req.getMethod()) || !permitida(req.getRequestURI())) {
            res.setStatus(HttpServletResponse.SC_FORBIDDEN);
            res.setContentType(MediaType.APPLICATION_JSON_VALUE);
            res.setCharacterEncoding(StandardCharsets.UTF_8.name());
            res.getWriter().write("{\"code\":20008,\"message\":\"El asistente solo puede consultar informacion del negocio.\"}");
            return;
        }
        ContentCachingResponseWrapper envuelta = new ContentCachingResponseWrapper(res);
        try {
            chain.doFilter(req, envuelta);
            String tipo = envuelta.getContentType();
            if (tipo != null && tipo.startsWith(MediaType.APPLICATION_JSON_VALUE) && envuelta.getContentSize() > 0) {
                byte[] limpio = sinPersonales(envuelta.getContentAsByteArray());
                envuelta.resetBuffer();
                envuelta.getOutputStream().write(limpio);
            }
        } finally {
            envuelta.copyBodyToResponse();
        }
    }

    static boolean permitida(String uri) {
        for (String r : RUTAS) {
            if (uri.equals(r) || uri.startsWith(r + "/")) {
                return true;
            }
        }
        return false;
    }

    private byte[] sinPersonales(byte[] cuerpo) {
        JsonNode raiz = json.readTree(cuerpo);
        quitar(raiz);
        return json.writeValueAsBytes(raiz);
    }

    private static void quitar(JsonNode nodo) {
        if (nodo instanceof ObjectNode obj) {
            obj.remove(PERSONALES);
        }
        for (JsonNode hijo : nodo) {
            quitar(hijo);
        }
    }
}
