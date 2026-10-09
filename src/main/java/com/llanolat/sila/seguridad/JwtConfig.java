package com.llanolat.sila.seguridad;

import com.nimbusds.jose.jwk.source.ImmutableSecret;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;

/** Firma y validacion de los JWT (HS256) con la clave SILA_JWT_SECRET. */
@Configuration
public class JwtConfig {

    @Bean
    SecretKey claveJwt(SeguridadProps props) {
        return new SecretKeySpec(Claves.decodificar(props.jwtSecret(), "SILA_JWT_SECRET", 32), "HmacSHA256");
    }

    @Bean
    JwtEncoder jwtEncoder(SecretKey claveJwt) {
        return new NimbusJwtEncoder(new ImmutableSecret<>(claveJwt));
    }

    @Bean
    JwtDecoder jwtDecoder(SecretKey claveJwt, SeguridadProps props, VerificadorUsuario verificador) {
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withSecretKey(claveJwt)
                .macAlgorithm(MacAlgorithm.HS256)
                .build();
        // Firma + expiracion (con su tolerancia por defecto) + emisor.
        OAuth2TokenValidator<Jwt> vigencia = jwt -> {
            // Solo los tokens de ACCESO: los temporales del login se validan por si mismos.
            if (!"acceso".equals(jwt.getClaimAsString("tipo"))) {
                return OAuth2TokenValidatorResult.success();
            }
            Object uid = jwt.getClaim("uid");
            if (uid instanceof Number id && verificador.vigente(id.longValue(), jwt.getClaimAsString("rol"), jwt.getClaimAsString("sid"))) {
                return OAuth2TokenValidatorResult.success();
            }
            return OAuth2TokenValidatorResult.failure(
                    new OAuth2Error("invalid_token", "Sesion cerrada, usuario inactivo o rol cambiado.", null));
        };
        OAuth2TokenValidator<Jwt> validador = new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(props.emisor()), vigencia);
        decoder.setJwtValidator(validador);
        return decoder;
    }
}
