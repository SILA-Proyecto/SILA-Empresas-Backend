package com.llanolat.sila.infra;

import com.llanolat.sila.seguridad.SeguridadProps;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * CORS para el dashboard Angular. Spring Security lo aplica antes de autenticar, asi que
 * el preflight (OPTIONS) nunca exige token.
 *
 * allowCredentials: la cookie de renovacion viaja solo con credenciales, por lo que el
 * origen debe ser EXACTO (nunca "*"). Authorization lleva el token de acceso;
 * Idempotency-Key la manda el dashboard en cada escritura. X-Usuario / X-Rol son la
 * identidad del modo desarrollo y solo se permiten en ese modo.
 */
@Configuration
public class CorsConfig {

    @Bean
    CorsConfigurationSource corsConfigurationSource(
            @Value("${sila.cors.origenes:http://localhost:4200}") String[] origenes,
            SeguridadProps props) {
        List<String> cabeceras = new ArrayList<>(List.of("Content-Type", "Accept", "Authorization", "Idempotency-Key"));
        if (!props.modoJwt()) {
            cabeceras.addAll(List.of("X-Usuario", "X-Rol"));
        }
        CorsConfiguration c = new CorsConfiguration();
        c.setAllowedOrigins(Arrays.asList(origenes));
        c.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        c.setAllowedHeaders(cabeceras);
        c.setAllowCredentials(true);
        c.setMaxAge(3600L);
        UrlBasedCorsConfigurationSource fuente = new UrlBasedCorsConfigurationSource();
        fuente.registerCorsConfiguration("/api/**", c);
        return fuente;
    }
}
