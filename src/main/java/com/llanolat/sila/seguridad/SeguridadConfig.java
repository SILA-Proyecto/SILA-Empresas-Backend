package com.llanolat.sila.seguridad;

import com.llanolat.sila.infra.idempotencia.IdempotenciaFilter;
import com.llanolat.sila.infra.idempotencia.IdempotenciaProps;
import com.llanolat.sila.infra.idempotencia.IdempotenciaRepository;
import jakarta.servlet.http.HttpServletResponse;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.security.web.access.intercept.AuthorizationFilter;
import org.springframework.security.web.header.writers.ReferrerPolicyHeaderWriter.ReferrerPolicy;

/**
 * Cadena de seguridad HTTP. Sin sesion de servidor, sin CSRF de formulario (la API usa
 * token en cabecera; la cookie de renovacion se protege con SameSite=Strict y la
 * comprobacion de Origin en AuthController).
 *
 * modo=jwt: todo exige un token de ACCESO salvo el login; /usuarios exige ADMIN.
 * modo=desarrollo: nada se exige (la identidad viene de cabeceras); existe solo para
 * poder trabajar mientras el dashboard no tenga su pantalla de login.
 */
@Configuration
@EnableWebSecurity
public class SeguridadConfig {

    private static final String AUTH = "/api/v1/auth";

    @Bean
    @ConditionalOnProperty(name = "sila.seguridad.modo", havingValue = "jwt")
    SecurityFilterChain cadenaJwt(HttpSecurity http, IdempotenciaRepository idempotencia,
                                  IdempotenciaProps idempotenciaProps) throws Exception {
        comun(http);
        http.addFilterAfter(new IdempotenciaFilter(idempotencia, idempotenciaProps), AuthorizationFilter.class);
        http.authorizeHttpRequests(a -> a
                .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                .requestMatchers(HttpMethod.POST, AUTH + "/login", AUTH + "/refresh", AUTH + "/logout").permitAll()
                .requestMatchers(HttpMethod.POST, AUTH + "/mfa/verificar", AUTH + "/mfa/respaldo").hasAuthority("TIPO_MFA")
                .requestMatchers(HttpMethod.POST, AUTH + "/mfa/configurar", AUTH + "/mfa/activar")
                    .hasAnyAuthority("TIPO_MFA_ENROLAR", "TIPO_ACCESO")
                .requestMatchers(HttpMethod.POST, AUTH + "/cambiar-clave")
                    .hasAnyAuthority("TIPO_CAMBIAR_CLAVE", "TIPO_ACCESO")
                .requestMatchers("/api/v1/usuarios/**", "/api/v1/auditoria/**").hasRole("ADMIN")
                // Escrituras reservadas a ADMIN. La base las verifica igual; esto responde antes y de forma uniforme.
                .requestMatchers(HttpMethod.POST, "/api/v1/periodos/**").hasRole("ADMIN")
                .requestMatchers(HttpMethod.PATCH, "/api/v1/periodos/**", "/api/v1/catalogos/**").hasRole("ADMIN")
                .requestMatchers(HttpMethod.POST, "/api/v1/catalogos/productos").hasRole("ADMIN")
                .requestMatchers(HttpMethod.POST, "/api/v1/ventas/*/anular", "/api/v1/cartera/castigos").hasRole("ADMIN")
                .requestMatchers(HttpMethod.PUT, "/api/v1/precios-cliente", "/api/v1/parametros/*").hasRole("ADMIN")
                .requestMatchers(HttpMethod.PATCH, "/api/v1/precios-cliente/**").hasRole("ADMIN")
                .requestMatchers(HttpMethod.POST, "/api/v1/acopio/precios", "/api/v1/acopio/pagos", "/api/v1/acopio/pagos/*/anular").hasRole("ADMIN")
                .requestMatchers("/actuator/health", "/actuator/health/**").permitAll()
                .anyRequest().hasAuthority("TIPO_ACCESO"));
        return http.build();
    }

    @Bean
    @ConditionalOnProperty(name = "sila.seguridad.modo", havingValue = "desarrollo", matchIfMissing = true)
    SecurityFilterChain cadenaDesarrollo(HttpSecurity http) throws Exception {
        comun(http);
        http.authorizeHttpRequests(a -> a.anyRequest().permitAll());
        return http.build();
    }

    private void comun(HttpSecurity http) throws Exception {
        http.csrf(c -> c.disable())
            .cors(Customizer.withDefaults())
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .headers(h -> h
                .contentSecurityPolicy(csp -> csp.policyDirectives("default-src 'none'; frame-ancestors 'none'"))
                .referrerPolicy(r -> r.policy(ReferrerPolicy.NO_REFERRER)))
            .exceptionHandling(e -> e.authenticationEntryPoint(noAutenticado()).accessDeniedHandler(sinPermiso()))
            .oauth2ResourceServer(o -> o
                .jwt(j -> j.jwtAuthenticationConverter(convertidor()))
                .authenticationEntryPoint(noAutenticado())
                .accessDeniedHandler(sinPermiso()));
    }

    /**
     * "tipo" -> TIPO_ACCESO, TIPO_MFA...; el rol (ROLE_ADMIN / ROLE_OPERATIVO) solo se
     * concede a los tokens de ACCESO, de modo que un token temporal nunca pase por ADMIN.
     */
    private JwtAuthenticationConverter convertidor() {
        JwtAuthenticationConverter c = new JwtAuthenticationConverter();
        c.setJwtGrantedAuthoritiesConverter(jwt -> {
            List<GrantedAuthority> a = new ArrayList<>();
            String tipo = jwt.getClaimAsString("tipo");
            if (tipo != null) {
                a.add(new SimpleGrantedAuthority("TIPO_" + tipo.toUpperCase()));
                String rol = jwt.getClaimAsString("rol");
                if ("acceso".equals(tipo) && rol != null) {
                    a.add(new SimpleGrantedAuthority("ROLE_" + rol));
                }
            }
            return a;
        });
        return c;
    }

    private AuthenticationEntryPoint noAutenticado() {
        return (req, res, ex) -> escribir(res, HttpServletResponse.SC_UNAUTHORIZED, 20013,
                "Sesion no valida o vencida. Inicie sesion de nuevo.");
    }

    private AccessDeniedHandler sinPermiso() {
        return (req, res, ex) -> escribir(res, HttpServletResponse.SC_FORBIDDEN, 20008,
                "No tiene permiso para esta operacion.");
    }

    /** Mismo formato que el resto de errores del API: {code, message}. */
    private static void escribir(HttpServletResponse res, int http, int code, String message) throws java.io.IOException {
        res.setStatus(http);
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        res.setCharacterEncoding(StandardCharsets.UTF_8.name());
        res.getWriter().write("{\"code\":" + code + ",\"message\":\"" + message + "\"}");
    }
}
