package com.llanolat.sila.seguridad;

import java.util.Arrays;
import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/**
 * Cinturon de seguridad: el modo "desarrollo" (identidad por cabeceras, cualquiera
 * puede ser ADMIN) NO puede arrancar con un perfil de produccion, y el modo debe ser
 * uno conocido. Un error de configuracion no debe dejar el sistema abierto.
 */
@Component
public class ValidadorModoSeguridad {

    private static final Set<String> PERFILES_PRODUCCION = Set.of("prod", "produccion", "production");

    public ValidadorModoSeguridad(SeguridadProps props, Environment env) {
        String modo = props.modo() == null ? "" : props.modo().toLowerCase();
        if (!modo.equals("jwt") && !modo.equals("desarrollo")) {
            throw new IllegalStateException("sila.seguridad.modo debe ser 'jwt' o 'desarrollo', no '" + props.modo() + "'.");
        }
        boolean perfilProduccion = Arrays.stream(env.getActiveProfiles())
                .anyMatch(p -> PERFILES_PRODUCCION.contains(p.toLowerCase()));
        if (modo.equals("desarrollo") && perfilProduccion) {
            throw new IllegalStateException("MODO DESARROLLO PROHIBIDO EN PRODUCCION: con un perfil de produccion "
                    + "activo, sila.seguridad.modo debe ser 'jwt'.");
        }
    }
}
