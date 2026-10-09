package com.llanolat.sila.seguridad;

import com.llanolat.sila.infra.Identidad;
import com.llanolat.sila.infra.SilaException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;
import org.springframework.web.context.annotation.RequestScope;

/**
 * Identidad tomada del JWT ya validado (firma, expiracion, emisor) por Spring Security.
 * Reemplaza a IdentidadDesdeCabecera cuando sila.seguridad.modo=jwt: el cliente ya no
 * puede afirmar quien es ni su rol. Solo un token de ACCESO sirve; los temporales no.
 */
@Component
@RequestScope
@ConditionalOnProperty(name = "sila.seguridad.modo", havingValue = "jwt")
public class IdentidadDesdeJwt implements Identidad {

    private final Jwt jwt;

    public IdentidadDesdeJwt() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof Jwt token)
                || !"acceso".equals(token.getClaimAsString("tipo"))) {
            throw SilaException.de(SilaException.PERMISO_DENEGADO, "No hay una sesion valida.");
        }
        this.jwt = token;
    }

    @Override
    public String usuario() {
        return jwt.getSubject();
    }

    @Override
    public String rol() {
        return jwt.getClaimAsString("rol");
    }
}
