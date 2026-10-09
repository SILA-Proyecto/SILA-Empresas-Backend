package com.llanolat.sila.infra;

import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.springframework.web.context.annotation.RequestScope;

/**
 * Identidad tomada de las cabeceras X-Usuario y X-Rol.
 *
 * ATENCION: esto es SOLO para desarrollo. Cualquiera puede mandar
 * "X-Rol: ADMIN" y la base de datos le creera, porque confia en el backend.
 * Se activa unicamente con sila.seguridad.modo=desarrollo y debe
 * reemplazarse por la version que lee el JWT antes de salir a produccion.
 */
@Component
@RequestScope
@ConditionalOnProperty(name = "sila.seguridad.modo", havingValue = "desarrollo")
public class IdentidadDesdeCabecera implements Identidad {

    private static final Logger log = LoggerFactory.getLogger(IdentidadDesdeCabecera.class);

    private final HttpServletRequest request;
    private final String usuarioPorDefecto;
    private final String rolPorDefecto;

    public IdentidadDesdeCabecera(HttpServletRequest request,
                                  @Value("${sila.seguridad.usuario-por-defecto:dev.local}") String usuarioPorDefecto,
                                  @Value("${sila.seguridad.rol-por-defecto:OPERATIVO}") String rolPorDefecto) {
        this.request = request;
        this.usuarioPorDefecto = usuarioPorDefecto;
        this.rolPorDefecto = rolPorDefecto;
        log.warn("MODO DESARROLLO: la identidad se toma de las cabeceras X-Usuario/X-Rol. "
               + "No usar en produccion.");
    }

    @Override
    public String usuario() {
        String v = request.getHeader("X-Usuario");
        return (v == null || v.isBlank()) ? usuarioPorDefecto : v.trim();
    }

    @Override
    public String rol() {
        String v = request.getHeader("X-Rol");
        return (v == null || v.isBlank()) ? rolPorDefecto : v.trim().toUpperCase();
    }
}
