package com.llanolat.sila.seguridad;

import java.time.Duration;
import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Propiedades sila.seguridad.*. Los dos secretos llegan por variable de entorno
 * (SILA_JWT_SECRET, SILA_MFA_KEY), nunca en el repositorio.
 *
 * @param modo             "jwt" (produccion) o "desarrollo" (identidad por cabeceras X-Usuario / X-Rol)
 * @param jwtSecret        clave HMAC para firmar los JWT, en base64, minimo 32 bytes
 * @param mfaKey           clave AES-256 para cifrar el secreto TOTP en la base, en base64, 32 bytes
 * @param accesoTtl        vida del token de acceso
 * @param temporalTtl      vida de los tokens de un solo paso (MFA, cambio de clave)
 * @param refreshTtl       vida del token de renovacion (se renueva en cada uso)
 * @param cookieSecure     la cookie de renovacion solo viaja por HTTPS
 * @param mfaObligatorioRoles roles que no pueden entrar sin segundo factor
 */
@ConfigurationProperties(prefix = "sila.seguridad")
public record SeguridadProps(
        @DefaultValue("desarrollo") String modo,
        @DefaultValue("dev.local") String usuarioPorDefecto,
        @DefaultValue("OPERATIVO") String rolPorDefecto,
        String jwtSecret,
        String mfaKey,
        @DefaultValue("15m") Duration accesoTtl,
        @DefaultValue("5m") Duration temporalTtl,
        @DefaultValue("12h") Duration refreshTtl,
        @DefaultValue("true") boolean cookieSecure,
        @DefaultValue("ADMIN") List<String> mfaObligatorioRoles,
        @DefaultValue("sila") String emisor
) {
    public boolean modoJwt() {
        return "jwt".equalsIgnoreCase(modo);
    }
}
