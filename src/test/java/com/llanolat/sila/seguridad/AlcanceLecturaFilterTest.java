package com.llanolat.sila.seguridad;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.servlet.FilterChain;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import tools.jackson.databind.json.JsonMapper;

class AlcanceLecturaFilterTest {

    private final AlcanceLecturaFilter filtro = new AlcanceLecturaFilter(JsonMapper.builder().build());

    @AfterEach
    void limpiar() {
        SecurityContextHolder.clearContext();
    }

    private static void entrar(String ambito) {
        Jwt.Builder b = Jwt.withTokenValue("t").header("alg", "HS256").subject("ana")
                .issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(60)).claim("tipo", "acceso").claim("rol", "ADMIN");
        if (ambito != null) {
            b.claim("ambito", ambito);
        }
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(b.build()));
    }

    private MockHttpServletResponse correr(String metodo, String uri, String cuerpo) throws Exception {
        MockHttpServletRequest req = new MockHttpServletRequest(metodo, uri);
        req.setRequestURI(uri);
        MockHttpServletResponse res = new MockHttpServletResponse();
        FilterChain cadena = (rq, rs) -> {
            rs.setContentType("application/json");
            rs.getOutputStream().write(cuerpo.getBytes(StandardCharsets.UTF_8));
        };
        filtro.doFilter(req, res, cadena);
        return res;
    }

    @Test
    void unTokenNormalPasaIntactoConSusDatosPersonales() throws Exception {
        entrar(null);
        MockHttpServletResponse res = correr("POST", "/api/v1/usuarios", "{\"telefono\":\"3001\"}");
        assertThat(res.getStatus()).isEqualTo(200);
        assertThat(res.getContentAsString()).contains("telefono");
    }

    @Test
    void elTokenDeLecturaSoloConsultaRutasDeNegocio() throws Exception {
        entrar("lectura");
        assertThat(correr("POST", "/api/v1/ventas", "{}").getStatus()).isEqualTo(403);
        assertThat(correr("PATCH", "/api/v1/catalogos/clientes/1", "{}").getStatus()).isEqualTo(403);
        assertThat(correr("GET", "/api/v1/usuarios", "[]").getStatus()).isEqualTo(403);
        assertThat(correr("GET", "/api/v1/auditoria/accesos", "[]").getStatus()).isEqualTo(403);
        assertThat(correr("GET", "/api/v1/archivos/1/contenido", "[]").getStatus()).isEqualTo(403);
        assertThat(correr("GET", "/api/v1/asistente/mensajes", "[]").getStatus()).isEqualTo(403);
        assertThat(correr("GET", "/api/v1/ventasx", "[]").getStatus()).isEqualTo(403);
        assertThat(correr("GET", "/api/v1/ventas", "[]").getStatus()).isEqualTo(200);
        assertThat(correr("GET", "/api/v1/cartera/clientes", "[]").getStatus()).isEqualTo(200);
    }

    @Test
    void laRespuestaAlAsistenteNoLlevaDatosPersonales() throws Exception {
        entrar("lectura");
        MockHttpServletResponse res = correr("GET", "/api/v1/catalogos/clientes",
                "{\"content\":[{\"nombre\":\"Ana\",\"telefono\":\"300\",\"email\":\"a@b.co\",\"numero_documento\":\"12\","
                        + "\"saldo\":5,\"hijo\":{\"direccion\":\"x\",\"nit\":\"9\"}}]}");
        String cuerpo = res.getContentAsString();
        assertThat(cuerpo).contains("Ana").contains("saldo");
        assertThat(cuerpo).doesNotContain("telefono").doesNotContain("email").doesNotContain("numero_documento")
                .doesNotContain("direccion").doesNotContain("nit");
    }
}
