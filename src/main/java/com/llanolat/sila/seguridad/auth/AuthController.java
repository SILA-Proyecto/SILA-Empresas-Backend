package com.llanolat.sila.seguridad.auth;

import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.seguridad.SeguridadProps;
import com.llanolat.sila.seguridad.auth.AuthDtos.ActualizarPerfilRequest;
import com.llanolat.sila.seguridad.auth.AuthDtos.AuthResponse;
import com.llanolat.sila.seguridad.auth.AuthDtos.CambiarClaveRequest;
import com.llanolat.sila.seguridad.auth.AuthDtos.CodigoRequest;
import com.llanolat.sila.seguridad.auth.AuthDtos.CodigosRespaldo;
import com.llanolat.sila.seguridad.auth.AuthDtos.EstadoRespaldo;
import com.llanolat.sila.seguridad.auth.AuthDtos.RegenerarRespaldoRequest;
import com.llanolat.sila.seguridad.auth.AuthDtos.RespaldoRequest;
import com.llanolat.sila.seguridad.auth.AuthDtos.SesionDto;
import com.llanolat.sila.seguridad.auth.AuthDtos.SesionesCerradas;
import com.llanolat.sila.seguridad.auth.AuthDtos.LoginRequest;
import com.llanolat.sila.seguridad.auth.AuthDtos.MfaConfig;
import com.llanolat.sila.seguridad.auth.AuthDtos.UsuarioSesion;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import java.time.Duration;
import java.util.Arrays;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * Contrato del dashboard para autenticacion: /api/v1/auth. Ver docs/CONTRATO_BACKEND.md.
 *
 * El token de renovacion viaja SOLO en la cookie "sila_refresh" (httpOnly, SameSite=Strict,
 * limitada a /api/v1/auth): el JavaScript de la pagina nunca lo ve. El token de acceso va en
 * el cuerpo y el dashboard lo guarda solo en memoria.
 */
@RestController
@RequestMapping("/api/v1/auth")
class AuthController {

    static final String COOKIE = "sila_refresh";
    private static final String RUTA_COOKIE = "/api/v1/auth";

    private final AuthService service;
    private final SeguridadProps props;
    private final List<String> origenes;

    AuthController(AuthService service, SeguridadProps props,
                   @Value("${sila.cors.origenes:http://localhost:4200}") String[] origenes) {
        this.service = service;
        this.props = props;
        this.origenes = Arrays.asList(origenes);
    }

    @PostMapping("/login")
    ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest r, HttpServletRequest req) {
        return responder(service.login(r.usuario(), r.clave(), ip(req), agente(req)));
    }

    /** Token temporal tipo "mfa" en Authorization. */
    @PostMapping("/mfa/verificar")
    ResponseEntity<AuthResponse> verificarMfa(@AuthenticationPrincipal Jwt jwt,
                                              @Valid @RequestBody CodigoRequest r, HttpServletRequest req) {
        return responder(service.verificarMfa(jwt, r.codigo(), ip(req), agente(req)));
    }

    /** Token temporal tipo "mfa": entrar con un codigo de respaldo cuando no se tiene el telefono. */
    @PostMapping("/mfa/respaldo")
    ResponseEntity<AuthResponse> usarRespaldo(@AuthenticationPrincipal Jwt jwt,
                                              @Valid @RequestBody RespaldoRequest r, HttpServletRequest req) {
        return responder(service.usarCodigoRespaldo(jwt, r.codigoRespaldo(), ip(req), agente(req)));
    }

    /** Token de acceso + clave actual: genera 10 codigos nuevos (los anteriores dejan de servir). Se muestran una vez. */
    @PostMapping("/mfa/respaldo/regenerar")
    CodigosRespaldo regenerarRespaldo(@AuthenticationPrincipal Jwt jwt,
                                      @Valid @RequestBody RegenerarRespaldoRequest r, HttpServletRequest req) {
        return new CodigosRespaldo(service.regenerarCodigosRespaldo(jwt, r.claveActual(), r.codigo(), ip(req), agente(req)));
    }

    /** Cuantos codigos de respaldo sin usar quedan. */
    @GetMapping("/mfa/respaldo")
    EstadoRespaldo estadoRespaldo(@AuthenticationPrincipal Jwt jwt) {
        return new EstadoRespaldo(service.codigosRespaldoRestantes(jwt));
    }

    /** Token temporal "mfa_enrolar" o token de acceso. Devuelve el secreto y el URI para el QR. */
    @PostMapping("/mfa/configurar")
    MfaConfig configurarMfa(@AuthenticationPrincipal Jwt jwt) {
        return service.configurarMfa(jwt);
    }

    @PostMapping("/mfa/activar")
    ResponseEntity<AuthResponse> activarMfa(@AuthenticationPrincipal Jwt jwt,
                                            @Valid @RequestBody CodigoRequest r, HttpServletRequest req) {
        return responder(service.activarMfa(jwt, r.codigo(), ip(req), agente(req)));
    }

    /** Token temporal "cambiar_clave" o token de acceso. Pide siempre la clave actual. */
    @PostMapping("/cambiar-clave")
    ResponseEntity<AuthResponse> cambiarClave(@AuthenticationPrincipal Jwt jwt,
                                              @Valid @RequestBody CambiarClaveRequest r, HttpServletRequest req) {
        return responder(service.cambiarClave(jwt, r.claveActual(), r.claveNueva(), r.codigo(), ip(req), agente(req)));
    }

    @PostMapping("/refresh")
    ResponseEntity<AuthResponse> refresh(@CookieValue(name = COOKIE, required = false) String cookie,
                                         HttpServletRequest req, HttpServletResponse res) {
        verificarOrigen(req);
        try {
            return responder(service.renovar(cookie, ip(req), agente(req)));
        } catch (SilaException e) {
            // Un token de renovacion rechazado no sirve de nada: se borra la cookie.
            res.addHeader(HttpHeaders.SET_COOKIE, borrarCookie().toString());
            throw e;
        }
    }

    @PostMapping("/logout")
    ResponseEntity<Void> logout(@CookieValue(name = COOKIE, required = false) String cookie, HttpServletRequest req) {
        verificarOrigen(req);
        service.cerrarSesion(cookie, ip(req), agente(req));
        return ResponseEntity.noContent().header(HttpHeaders.SET_COOKIE, borrarCookie().toString()).build();
    }

    // ---------- mis sesiones ----------

    @GetMapping("/sesiones")
    List<SesionDto> sesiones(@AuthenticationPrincipal Jwt jwt) {
        return service.sesiones(jwt);
    }

    /** Cierra una de MIS sesiones (puede ser la actual). */
    @DeleteMapping("/sesiones/{familia}")
    ResponseEntity<Void> cerrarSesion(@AuthenticationPrincipal Jwt jwt, @PathVariable String familia,
                                      HttpServletRequest req) {
        service.cerrarUnaSesion(jwt, familia, ip(req), agente(req));
        return ResponseEntity.noContent().build();
    }

    /** Cierra todas MIS sesiones menos esta. */
    @PostMapping("/sesiones/cerrar-otras")
    SesionesCerradas cerrarOtras(@AuthenticationPrincipal Jwt jwt, HttpServletRequest req) {
        return new SesionesCerradas(service.cerrarSesiones(jwt, true, ip(req), agente(req)));
    }

    /** Cierra todas MIS sesiones, incluida esta: hay que iniciar sesion de nuevo. */
    @PostMapping("/sesiones/cerrar-todas")
    SesionesCerradas cerrarTodas(@AuthenticationPrincipal Jwt jwt, HttpServletRequest req) {
        return new SesionesCerradas(service.cerrarSesiones(jwt, false, ip(req), agente(req)));
    }

    /** Quien soy: datos de la sesion actual (token de acceso). */
    @GetMapping("/yo")
    UsuarioSesion yo(@AuthenticationPrincipal Jwt jwt) {
        return service.yo(jwt);
    }

    /** Editar mi nombre y correo. Exige el codigo del segundo factor; rol, usuario y estado no se tocan. */
    @PutMapping("/yo")
    UsuarioSesion actualizarYo(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody ActualizarPerfilRequest r,
                               HttpServletRequest req) {
        return service.actualizarPerfil(jwt, r.nombre(), r.email(), r.codigo(), ip(req), agente(req));
    }

    // ---------- utilidades ----------

    private ResponseEntity<AuthResponse> responder(AuthService.Resultado r) {
        ResponseEntity.BodyBuilder b = ResponseEntity.ok().header(HttpHeaders.CACHE_CONTROL, "no-store");
        if (r.refreshToken() != null) {
            b.header(HttpHeaders.SET_COOKIE, cookie(r.refreshToken()).toString());
        }
        return b.body(r.cuerpo());
    }

    private ResponseCookie cookie(String valor) {
        return ResponseCookie.from(COOKIE, valor)
                .httpOnly(true).secure(props.cookieSecure()).sameSite("Strict")
                .path(RUTA_COOKIE).maxAge(props.refreshTtl()).build();
    }

    private ResponseCookie borrarCookie() {
        return ResponseCookie.from(COOKIE, "")
                .httpOnly(true).secure(props.cookieSecure()).sameSite("Strict")
                .path(RUTA_COOKIE).maxAge(Duration.ZERO).build();
    }

    /**
     * Defensa contra CSRF en los endpoints que usan la cookie: si el navegador declara un
     * Origin, tiene que ser el del dashboard. (Sin Origin no es un navegador: no hay CSRF.)
     */
    private void verificarOrigen(HttpServletRequest req) {
        String origen = req.getHeader("Origin");
        if (origen != null && !origenes.contains(origen)) {
            throw SilaException.de(SilaException.PERMISO_DENEGADO, "Origen no permitido.");
        }
    }

    private static String ip(HttpServletRequest req) {
        return req.getRemoteAddr();
    }

    private static String agente(HttpServletRequest req) {
        String ua = req.getHeader("User-Agent");
        return ua == null ? null : ua.replaceAll("[\\r\\n]", " ");
    }
}
