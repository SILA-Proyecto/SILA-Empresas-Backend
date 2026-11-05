package com.llanolat.sila.legal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

class LegalPendienteFilterTest {

    @AfterEach
    void limpiar() { SecurityContextHolder.clearContext(); }

    /** Servicio de mentira: responde lo que se le diga (o falla) sin tocar la base. */
    private static LegalPendienteFilter con(Boolean alDia) {
        LegalService s = new LegalService(null, LegalServiceTest.PROPS) {
            @Override public boolean alDia(long idUsuario) {
                if (alDia == null) throw new IllegalStateException("la base no responde");
                return alDia;
            }
        };
        return new LegalPendienteFilter(s);
    }

    private static void sesion(String tipo, Object uid, String ambito) {
        Jwt.Builder b = Jwt.withTokenValue("t").header("alg", "HS256").subject("ana").issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(60)).claim("tipo", tipo).claim("rol", "ADMIN");
        if (uid != null) b.claim("uid", uid);
        if (ambito != null) b.claim("ambito", ambito);
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(b.build()));
    }

    private record Resultado(int estado, String cuerpo, boolean paso) {}

    private static Resultado llamar(LegalPendienteFilter f, String metodo, String uri) throws Exception {
        MockHttpServletRequest req = new MockHttpServletRequest(metodo, uri);
        MockHttpServletResponse res = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();
        f.doFilter(req, res, chain);
        return new Resultado(res.getStatus(), res.getContentAsString(), chain.getRequest() != null);
    }

    @Test
    void alDiaNoBloqueaNada() throws Exception {
        sesion("acceso", 5L, null);
        LegalPendienteFilter f = con(true);
        for (String ruta : new String[] {"/api/v1/ventas", "/api/v1/usuarios", "/api/v1/tablero", "/api/v1/empresa"}) {
            assertThat(llamar(f, "GET", ruta).paso()).as(ruta).isTrue();
        }
        assertThat(llamar(f, "POST", "/api/v1/ventas").paso()).isTrue();
    }

    @Test
    void pendienteDa403Con20022AToDoLoDemas() throws Exception {
        sesion("acceso", 5L, null);
        LegalPendienteFilter f = con(false);
        Resultado r = llamar(f, "GET", "/api/v1/ventas");
        assertThat(r.estado()).isEqualTo(403);
        assertThat(r.paso()).isFalse();
        assertThat(r.cuerpo()).contains("\"code\":20022").contains("aceptar");
        for (String[] p : new String[][] {{"POST", "/api/v1/ventas"}, {"GET", "/api/v1/usuarios"}, {"PUT", "/api/v1/empresa"},
                {"GET", "/api/v1/empresa"}, {"GET", "/api/v1/tablero"}, {"POST", "/api/v1/archivos"}, {"GET", "/api/v1/reportes/x"},
                {"DELETE", "/api/v1/fotos/3"}, {"PUT", "/api/v1/fotos/yo"}, {"POST", "/api/v1/empresa/publica"},
                {"GET", "/api/v1/legalx"}, {"GET", "/api/v1/authx"}, {"GET", "/actuator/info"}, {"GET", "/api/v1/"}}) {
            assertThat(llamar(f, p[0], p[1]).estado()).as(p[0] + " " + p[1]).isEqualTo(403);
        }
    }

    @Test
    void pendienteSoloPuedeUsarLoNecesarioParaAceptar() throws Exception {
        sesion("acceso", 5L, null);
        LegalPendienteFilter f = con(false);
        for (String[] p : new String[][] {{"GET", "/api/v1/legal/vigentes"}, {"GET", "/api/v1/legal/estado"}, {"POST", "/api/v1/legal/aceptar"},
                {"GET", "/api/v1/auth/yo"}, {"POST", "/api/v1/auth/logout"}, {"POST", "/api/v1/auth/cambiar-clave"},
                {"POST", "/api/v1/auth/mfa/activar"}, {"POST", "/api/v1/auth/login"}, {"POST", "/api/v1/auth/refresh"},
                {"GET", "/api/v1/empresa/publica"}, {"GET", "/api/v1/empresa/logo"}, {"GET", "/api/v1/fotos/yo"},
                {"GET", "/actuator/health"}, {"GET", "/actuator/health/liveness"}, {"OPTIONS", "/api/v1/ventas"}}) {
            assertThat(llamar(f, p[0], p[1]).paso()).as(p[0] + " " + p[1]).isTrue();
        }
    }

    @Test
    void tambienBloqueaAlTokenDeSoloLecturaDelAsistente() throws Exception {
        sesion("acceso", 5L, "lectura");
        Resultado r = llamar(con(false), "GET", "/api/v1/ventas");
        assertThat(r.estado()).isEqualTo(403);
        assertThat(r.cuerpo()).contains("\"code\":20022");
    }

    @Test
    void sinSesionOConTokenTemporalDejaALaCadena() throws Exception {
        LegalPendienteFilter f = con(false);
        assertThat(llamar(f, "GET", "/api/v1/ventas").paso()).as("anonimo -> la cadena da 401").isTrue();
        sesion("mfa", 5L, null);
        assertThat(llamar(f, "GET", "/api/v1/ventas").paso()).as("token temporal -> la cadena da 403").isTrue();
    }

    @Test
    void tokenDeAccesoSinUidFallaCerrado() throws Exception {
        sesion("acceso", null, null);
        Resultado r = llamar(con(true), "GET", "/api/v1/ventas");
        assertThat(r.estado()).isEqualTo(403);
        assertThat(r.cuerpo()).contains("\"code\":20022");
    }

    @Test
    void siNoSePuedeComprobarFallaCerradoConUn503() throws Exception {
        sesion("acceso", 5L, null);
        Resultado r = llamar(con(null), "GET", "/api/v1/ventas");
        assertThat(r.estado()).isEqualTo(503);
        assertThat(r.paso()).isFalse();
        assertThat(r.cuerpo()).contains("\"code\":20019").doesNotContain("la base no responde");
    }
}
