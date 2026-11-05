package com.llanolat.sila.empresa;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class EstadoEmpresaFilterTest {

    /** Empresa de mentira, suspendida o no (sin tocar la base). */
    private static EstadoEmpresaFilter con(boolean suspendida) {
        EmpresaService e = new EmpresaService(null, null, Duration.ZERO) {
            @Override public boolean suspendida() { return suspendida; }
        };
        return new EstadoEmpresaFilter(e);
    }

    private record Resultado(int estado, String cuerpo, boolean paso) {}

    private static Resultado llamar(EstadoEmpresaFilter f, String metodo, String uri) throws Exception {
        MockHttpServletRequest req = new MockHttpServletRequest(metodo, uri);
        MockHttpServletResponse res = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();
        f.doFilter(req, res, chain);
        return new Resultado(res.getStatus(), res.getContentAsString(), chain.getRequest() != null);
    }

    @Test
    void activaNoBloqueaNada() throws Exception {
        EstadoEmpresaFilter f = con(false);
        for (String ruta : new String[] {"/api/v1/ventas", "/api/v1/auth/login", "/api/v1/empresa", "/api/v1/tablero"}) {
            assertThat(llamar(f, "GET", ruta).paso()).as(ruta).isTrue();
        }
        assertThat(llamar(f, "POST", "/api/v1/auth/login").paso()).isTrue();
    }

    @Test
    void suspendidaDa403Con20021ATodo() throws Exception {
        EstadoEmpresaFilter f = con(true);
        Resultado r = llamar(f, "POST", "/api/v1/auth/login");
        assertThat(r.estado()).isEqualTo(403);
        assertThat(r.paso()).isFalse();
        assertThat(r.cuerpo()).contains("\"code\":20021").contains("suspendido");
        for (String[] p : new String[][] {{"POST", "/api/v1/auth/refresh"}, {"GET", "/api/v1/ventas"}, {"GET", "/api/v1/empresa"},
                {"PUT", "/api/v1/empresa/logo"}, {"DELETE", "/api/v1/empresa/logo"}, {"GET", "/api/v1/auth/yo"},
                {"POST", "/api/v1/ventas"}, {"GET", "/api/v1/empresa/publica/"}, {"GET", "/actuator/info"}}) {
            assertThat(llamar(f, p[0], p[1]).estado()).as(p[0] + " " + p[1]).isEqualTo(403);
        }
    }

    @Test
    void suspendidaDejaVerElLoginYCerrarSesion() throws Exception {
        EstadoEmpresaFilter f = con(true);
        assertThat(llamar(f, "GET", "/api/v1/empresa/publica").paso()).isTrue();
        assertThat(llamar(f, "GET", "/api/v1/empresa/logo").paso()).isTrue();
        assertThat(llamar(f, "POST", "/api/v1/auth/logout").paso()).isTrue();
        assertThat(llamar(f, "GET", "/actuator/health").paso()).isTrue();
        assertThat(llamar(f, "GET", "/actuator/health/liveness").paso()).isTrue();
        assertThat(llamar(f, "OPTIONS", "/api/v1/ventas").paso()).isTrue();
    }
}
