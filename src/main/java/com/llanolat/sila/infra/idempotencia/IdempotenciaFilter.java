package com.llanolat.sila.infra.idempotencia;

import com.llanolat.sila.infra.idempotencia.IdempotenciaRepository.Reserva;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Set;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;

/**
 * Idempotency-Key: si el cliente repite una escritura (reintento de red, doble clic) con la
 * misma clave y el mismo contenido, se devuelve la respuesta de la primera vez en lugar de
 * ejecutarla de nuevo (una venta, un abono o una factura NO se duplican).
 *
 *  - Aplica a POST/PUT/PATCH/DELETE de /api/v1, menos /auth y /usuarios (sus respuestas llevan claves).
 *  - La clave es opcional, salvo en las rutas de {@link IdempotenciaProps#obligatoriaEn()}.
 *  - La clave es por usuario. Misma clave con otro contenido -> 422; misma clave aun en curso -> 409.
 *  - Solo se guardan respuestas EXITOSAS (2xx); si falla, la clave se libera para reintentar.
 *
 * Va DESPUES de la autorizacion (ya se sabe quien es y que puede hacer), y no es un bean:
 * lo crea la cadena de seguridad para que Spring no lo registre dos veces.
 */
public class IdempotenciaFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(IdempotenciaFilter.class);
    private static final Pattern CLAVE = Pattern.compile("^[A-Za-z0-9_.:-]{8,100}$");
    private static final Set<String> METODOS = Set.of("POST", "PUT", "PATCH", "DELETE");

    private final IdempotenciaRepository repo;
    private final IdempotenciaProps props;

    public IdempotenciaFilter(IdempotenciaRepository repo, IdempotenciaProps props) {
        this.repo = repo;
        this.props = props;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        String ruta = req.getRequestURI();
        return !METODOS.contains(req.getMethod())
                || !ruta.startsWith("/api/v1/")
                || ruta.startsWith("/api/v1/auth")
                || ruta.startsWith("/api/v1/usuarios");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String clave = req.getHeader("Idempotency-Key");
        boolean obligatoria = props.obligatoriaEn().stream().anyMatch(req.getRequestURI()::startsWith);

        if (clave == null || clave.isBlank()) {
            if (obligatoria) {
                error(res, 400, 20001, "Falta la cabecera Idempotency-Key en esta operacion.");
                return;
            }
            chain.doFilter(req, res);
            return;
        }
        if (!CLAVE.matcher(clave).matches()) {
            error(res, 400, 20001, "Idempotency-Key invalida: 8 a 100 caracteres (letras, numeros, . _ : -).");
            return;
        }
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof Jwt jwt)) {
            chain.doFilter(req, res);
            return;
        }
        String usuario = jwt.getSubject();

        byte[] cuerpo = req.getInputStream().readNBytes(props.maxBytes() + 1);
        if (cuerpo.length > props.maxBytes()) {
            error(res, 413, 20001, "El cuerpo de la solicitud es demasiado grande.");
            return;
        }
        String huella = huella(req, cuerpo);

        Reserva reserva = repo.reservar(usuario, clave, huella);
        switch (reserva.resultado()) {
            case REPETIDA -> {
                res.setStatus(reserva.http());
                res.setContentType(MediaType.APPLICATION_JSON_VALUE);
                res.setCharacterEncoding(StandardCharsets.UTF_8.name());
                res.setHeader("Idempotency-Replayed", "true");
                if (reserva.respuesta() != null) {
                    res.getWriter().write(reserva.respuesta());
                }
                return;
            }
            case EN_PROCESO -> {
                error(res, 409, 20016, "Hay otra solicitud con la misma Idempotency-Key en proceso. Espere un momento.");
                return;
            }
            case CONFLICTO -> {
                error(res, 422, 20017, "Esa Idempotency-Key ya se uso con una solicitud distinta.");
                return;
            }
            default -> { /* NUEVA: se ejecuta */ }
        }

        ContentCachingResponseWrapper envuelta = new ContentCachingResponseWrapper(res);
        boolean guardada = false;
        try {
            chain.doFilter(new CuerpoCacheado(req, cuerpo), envuelta);
            int estado = envuelta.getStatus();
            if (estado >= 200 && estado < 300) {
                repo.completar(usuario, clave, estado,
                        new String(envuelta.getContentAsByteArray(), StandardCharsets.UTF_8));
                guardada = true;
            }
        } finally {
            if (!guardada) {
                try {
                    repo.liberar(usuario, clave);
                } catch (RuntimeException e) {
                    log.error("No se pudo liberar la Idempotency-Key tras un fallo.", e);
                }
            }
            envuelta.copyBodyToResponse();
        }
    }

    private static String huella(HttpServletRequest req, byte[] cuerpo) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            md.update((req.getMethod() + " " + req.getRequestURI() + "?" + req.getQueryString() + "\n")
                    .getBytes(StandardCharsets.UTF_8));
            md.update(cuerpo);
            return HexFormat.of().formatHex(md.digest());
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static void error(HttpServletResponse res, int http, int code, String message) throws IOException {
        res.setStatus(http);
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        res.setCharacterEncoding(StandardCharsets.UTF_8.name());
        res.getWriter().write("{\"code\":" + code + ",\"message\":\"" + message + "\"}");
    }

    /** La peticion con el cuerpo que ya se leyo, para que el controlador pueda leerlo de nuevo. */
    private static final class CuerpoCacheado extends HttpServletRequestWrapper {
        private final byte[] cuerpo;

        CuerpoCacheado(HttpServletRequest req, byte[] cuerpo) {
            super(req);
            this.cuerpo = cuerpo;
        }

        @Override
        public ServletInputStream getInputStream() {
            ByteArrayInputStream in = new ByteArrayInputStream(cuerpo);
            return new ServletInputStream() {
                @Override public int read() { return in.read(); }
                @Override public boolean isFinished() { return in.available() == 0; }
                @Override public boolean isReady() { return true; }
                @Override public void setReadListener(ReadListener l) { /* sincrono */ }
            };
        }

        @Override
        public BufferedReader getReader() {
            String enc = getCharacterEncoding() == null ? "UTF-8" : getCharacterEncoding();
            return new BufferedReader(new InputStreamReader(getInputStream(), java.nio.charset.Charset.forName(enc)));
        }
    }
}
