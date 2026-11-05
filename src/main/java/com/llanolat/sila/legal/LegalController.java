package com.llanolat.sila.legal;

import static com.llanolat.sila.infra.Peticion.agente;
import static com.llanolat.sila.infra.Peticion.ip;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.legal.LegalService.Aceptado;
import com.llanolat.sila.legal.LegalService.Estado;
import com.llanolat.sila.legal.LegalService.Vigente;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * /api/v1/legal: que version de los terminos y de la politica de privacidad rige y si la persona de la sesion ya las aceptó.
 * El TEXTO lo muestra el dashboard; aqui solo se registra la aceptacion (tabla aceptaciones_legales, de solo insercion).
 * Las aceptaciones las ve SOLO el dueno del sistema (sql/legal.sh): el ADMIN de la empresa no tiene endpoint para eso.
 * Mientras una persona no este al dia, {@link LegalPendienteFilter} le responde 403 / 20022 en todo lo demas. Ver docs/CONTRATO_EMPRESA.md.
 */
@RestController
@RequestMapping("/api/v1/legal")
public class LegalController {

    public record VigentesDto(List<Vigente> documentos) {}

    public record AceptadoDto(@NotBlank @Size(max = 20) String documento, @NotBlank @Size(max = 30) String version) {}

    public record AceptarRequest(@NotEmpty @Size(max = 10) List<@Valid AceptadoDto> aceptaciones) {}

    private final LegalService servicio;

    public LegalController(LegalService servicio) {
        this.servicio = servicio;
    }

    /** SIN sesion (la pantalla de login enlaza los documentos): que version rige de cada uno. */
    @GetMapping("/vigentes")
    public ResponseEntity<VigentesDto> vigentes() {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new VigentesDto(servicio.vigentes()));
    }

    /** Cualquier usuario autenticado: sus propias aceptaciones frente a lo vigente. */
    @GetMapping("/estado")
    public ResponseEntity<Estado> estado(@AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(servicio.estado(idUsuario(jwt)));
    }

    /**
     * Cualquier usuario autenticado. Exige LOS DOS documentos en la version vigente; la persona sale del token, nunca del cuerpo.
     * IP y navegador los toma el servidor. Idempotente. Devuelve el estado resultante.
     */
    @PostMapping("/aceptar")
    public ResponseEntity<Estado> aceptar(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody AceptarRequest r, HttpServletRequest req) {
        List<Aceptado> enviados = r.aceptaciones().stream().map(a -> new Aceptado(a.documento(), a.version())).toList();
        Estado e = servicio.aceptar(idUsuario(jwt), enviados, ip(req), agente(req));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(e);
    }

    private static long idUsuario(Jwt jwt) {
        if (jwt != null && jwt.getClaim("uid") instanceof Number n) {
            return n.longValue();
        }
        throw SilaException.de(SilaException.PERMISO_DENEGADO, "No hay una sesion valida.");
    }
}
