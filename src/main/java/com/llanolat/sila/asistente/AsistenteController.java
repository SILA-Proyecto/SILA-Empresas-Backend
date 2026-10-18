package com.llanolat.sila.asistente;

import com.llanolat.sila.asistente.AsistenteDtos.MensajeRequest;
import com.llanolat.sila.asistente.AsistenteDtos.Respuesta;
import com.llanolat.sila.infra.Peticion;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Chat de ayuda: /api/v1/asistente (cualquier usuario autenticado, ADMIN u OPERATIVO). */
@RestController
@RequestMapping("/api/v1/asistente")
class AsistenteController {

    private final AsistenteService service;

    AsistenteController(AsistenteService service) { this.service = service; }

    @PostMapping("/mensajes")
    Respuesta mensaje(@Valid @RequestBody MensajeRequest req, @AuthenticationPrincipal Jwt jwt,
                      HttpServletRequest http) {
        String texto = service.preguntar(jwt, req.mensaje().trim(), req.sesionId(),
                Peticion.ip(http), Peticion.agente(http));
        return new Respuesta(texto, req.sesionId());
    }
}
