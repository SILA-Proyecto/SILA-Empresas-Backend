package com.llanolat.sila.seguridad.auth;

import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/**
 * Pide de nuevo el segundo factor (codigo de la app de autenticacion o uno de respaldo) para una accion sensible de la
 * sesion abierta: crear usuarios, cambiar roles, restablecer claves o el segundo factor de otra persona. Usa las mismas
 * reglas que "Mi cuenta": un codigo de la app sirve una sola vez, los de respaldo se gastan y los intentos se limitan.
 */
@Component
public class ConfirmacionSegundoFactor {

    private final AuthService auth;

    ConfirmacionSegundoFactor(AuthService auth) { this.auth = auth; }

    public void exigir(Jwt jwt, String codigo, String ip, String userAgent) {
        auth.confirmarAccion(jwt, codigo, ip, userAgent);
    }
}
