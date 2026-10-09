package com.llanolat.sila.auditoria;

import com.llanolat.sila.auditoria.AuditoriaDtos.CambioAuditoria;
import com.llanolat.sila.auditoria.AuditoriaDtos.ErrorSistema;
import com.llanolat.sila.auditoria.AuditoriaDtos.EventoAcceso;
import com.llanolat.sila.infra.Page;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Auditoria y accesos: /api/v1/auditoria (solo ADMIN, lo exige la cadena de seguridad).
 * Ver docs/CONTRATO_BACKEND.md. Solo lectura: las bitacoras no se pueden modificar ni borrar.
 */
@RestController
@RequestMapping("/api/v1/auditoria")
class AuditoriaController {

    private final AuditoriaRepository repo;

    AuditoriaController(AuditoriaRepository repo) { this.repo = repo; }

    /** Quien entro, quien fallo, quien se bloqueo; con IP y navegador. */
    @GetMapping("/accesos")
    Page<EventoAcceso> accesos(
            @RequestParam(required = false) String usuario,
            @RequestParam(required = false) String evento,
            @RequestParam(required = false) String ip,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.accesos(usuario, evento, ip, desde, hasta, page, size, sort);
    }

    /** Cambios sensibles (precios, limites de credito, estados, roles...) con valor anterior y nuevo. */
    @GetMapping("/cambios")
    Page<CambioAuditoria> cambios(
            @RequestParam(required = false) String usuario,
            @RequestParam(required = false) String tabla,
            @RequestParam(required = false) String columna,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.cambios(usuario, tabla, columna, desde, hasta, page, size, sort);
    }

    /** Errores tecnicos registrados (el support_ref que ve el usuario es su id_log). */
    @GetMapping("/errores")
    Page<ErrorSistema> errores(
            @RequestParam(required = false) String usuario,
            @RequestParam(required = false) String unidad,
            @RequestParam(name = "codigo_error", required = false) Integer codigoError,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.errores(usuario, unidad, codigoError, desde, hasta, page, size, sort);
    }
}
