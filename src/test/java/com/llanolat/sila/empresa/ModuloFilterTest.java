package com.llanolat.sila.empresa;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.Set;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.context.SecurityContextHolder;

class ModuloFilterTest {

    /** Empresa de mentira con los modulos que se le indiquen apagados (sin tocar la base). */
    private static ModuloFilter con(Set<String> apagados) {
        EmpresaService e = new EmpresaService(null, null, Duration.ZERO) {
            @Override public boolean activo(String codigo) { return !apagados.contains(codigo); }
        };
        return new ModuloFilter(e);
    }

    private record Resultado(int estado, String cuerpo, boolean paso) {}

    private static Resultado llamar(ModuloFilter f, String metodo, String uri) throws Exception {
        MockHttpServletRequest req = new MockHttpServletRequest(metodo, uri);
        MockHttpServletResponse res = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();
        f.doFilter(req, res, chain);
        return new Resultado(res.getStatus(), res.getContentAsString(), chain.getRequest() != null);
    }

    private static void iniciarSesion() {
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("ana", "n/a", AuthorityUtils.createAuthorityList("TIPO_ACCESO", "ROLE_ADMIN")));
    }

    @AfterEach
    void limpiar() { SecurityContextHolder.clearContext(); }

    @Test
    void rutaDeModuloApagadoDa403Con20020() throws Exception {
        iniciarSesion();
        ModuloFilter f = con(Set.of("PRECIOS_CLIENTE", "MARGEN"));
        Resultado r = llamar(f, "GET", "/api/v1/precios-cliente");
        assertThat(r.estado()).isEqualTo(403);
        assertThat(r.paso()).isFalse();
        assertThat(r.cuerpo()).contains("\"code\":20020").contains("Esta función no está activa para su empresa.");
        assertThat(llamar(f, "GET", "/api/v1/reportes/margen").estado()).isEqualTo(403);
    }

    @Test
    void rutaDeModuloActivoPasa() throws Exception {
        iniciarSesion();
        ModuloFilter f = con(Set.of("PRECIOS_CLIENTE"));
        assertThat(llamar(f, "GET", "/api/v1/cartera/clientes").paso()).isTrue();
        assertThat(llamar(f, "GET", "/api/v1/reportes/margen").paso()).isTrue();
    }

    @Test
    void elNucleoNuncaSeBloquea() throws Exception {
        iniciarSesion();
        // aunque (por error) todo estuviera apagado
        ModuloFilter f = con(Set.of("CREDITO", "PRECIOS_CLIENTE", "CALIDAD_LECHE", "MARGEN", "ARCHIVOS", "ASISTENTE"));
        for (String ruta : new String[] {"/api/v1/ventas", "/api/v1/tablero", "/api/v1/notificaciones", "/api/v1/empresa",
                "/api/v1/archivos/comprobante/VENTA/1", "/api/v1/archivos/9", "/api/v1/cuentas-proveedores/precios"}) {
            assertThat(llamar(f, "GET", ruta).paso()).as(ruta).isTrue();
        }
    }

    @Test
    void sinSesionSigueElFlujoNormalYDaria401() throws Exception {
        // La cadena de seguridad responde 401; el filtro no revela que modulos tiene la empresa.
        ModuloFilter f = con(Set.of("CREDITO"));
        Resultado r = llamar(f, "GET", "/api/v1/cartera/clientes");
        assertThat(r.paso()).isTrue();
        assertThat(r.estado()).isEqualTo(200);
    }

    @Test
    void elRetornoPublicoDeDriveSiSeBloquea() throws Exception {
        ModuloFilter f = con(Set.of("ARCHIVOS"));
        Resultado r = llamar(f, "GET", "/api/v1/archivos/drive/callback");
        assertThat(r.estado()).isEqualTo(403);
        assertThat(r.cuerpo()).contains("20020");
    }

    @Test
    void tambienBloqueaAlTokenDeSoloLectura() throws Exception {
        // El filtro no distingue tokens: el del asistente (ambito=lectura) es una sesion mas.
        iniciarSesion();
        ModuloFilter f = con(Set.of("CREDITO"));
        assertThat(llamar(f, "GET", "/api/v1/cartera/resumen").estado()).isEqualTo(403);
    }

    @Test
    void elPreflightCorsNoSeBloquea() throws Exception {
        ModuloFilter f = con(Set.of("CREDITO"));
        assertThat(llamar(f, "OPTIONS", "/api/v1/cartera/abonos").paso()).isTrue();
    }
}
