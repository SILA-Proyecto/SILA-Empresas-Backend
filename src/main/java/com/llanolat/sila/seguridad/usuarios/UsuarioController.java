package com.llanolat.sila.seguridad.usuarios;

import com.llanolat.sila.infra.Page;
import com.llanolat.sila.seguridad.usuarios.UsuarioDtos.ActualizarUsuarioRequest;
import com.llanolat.sila.seguridad.usuarios.UsuarioDtos.CambiarEstadoRequest;
import com.llanolat.sila.seguridad.usuarios.UsuarioDtos.CrearUsuarioRequest;
import com.llanolat.sila.seguridad.usuarios.UsuarioDtos.UsuarioConClaveTemporal;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * Administracion de usuarios: /api/v1/usuarios. TODO es ADMIN (la cadena de seguridad lo
 * exige y, ademas, cada procedimiento de pkg_usuarios lo verifica en la base).
 * Ver docs/CONTRATO_BACKEND.md.
 */
@RestController
@RequestMapping("/api/v1/usuarios")
class UsuarioController {

    private final UsuarioService service;

    UsuarioController(UsuarioService service) { this.service = service; }

    @GetMapping
    Page<UsuarioDto> listar(
            @RequestParam(required = false) String texto,
            @RequestParam(required = false) Boolean activo,
            @RequestParam(required = false) String rol,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return service.listar(texto, activo, rol, page, size, sort);
    }

    @GetMapping("/{id}")
    UsuarioDto obtener(@PathVariable long id) {
        return service.obtener(id);
    }

    /** Crea el usuario con una clave temporal (se devuelve una sola vez); debe cambiarla al entrar. */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    UsuarioConClaveTemporal crear(@Valid @RequestBody CrearUsuarioRequest r) {
        return service.crear(r);
    }

    @PutMapping("/{id}")
    UsuarioDto actualizar(@PathVariable long id, @Valid @RequestBody ActualizarUsuarioRequest r) {
        return service.actualizar(id, r);
    }

    /** No borra: activa o desactiva (desactivar cierra sus sesiones). */
    @PatchMapping("/{id}/estado")
    UsuarioDto estado(@PathVariable long id, @Valid @RequestBody CambiarEstadoRequest r) {
        return service.cambiarEstado(id, r.activo());
    }

    @PostMapping("/{id}/desbloquear")
    UsuarioDto desbloquear(@PathVariable long id) {
        return service.desbloquear(id);
    }

    @PostMapping("/{id}/restablecer-clave")
    UsuarioConClaveTemporal restablecerClave(@PathVariable long id) {
        return service.restablecerClave(id);
    }

    /** Sesiones abiertas de esa persona (desde donde y desde cuando). */
    @GetMapping("/{id}/sesiones")
    java.util.List<UsuarioRepository.SesionActiva> sesiones(@PathVariable long id) {
        return service.sesiones(id);
    }

    /** Cierra todas las sesiones de esa persona (su token de acceso deja de servir en segundos). */
    @PostMapping("/{id}/cerrar-sesiones")
    UsuarioDto cerrarSesiones(@PathVariable long id) {
        return service.cerrarSesiones(id);
    }

    @PostMapping("/{id}/restablecer-mfa")
    UsuarioDto restablecerMfa(@PathVariable long id) {
        return service.restablecerMfa(id);
    }
}
