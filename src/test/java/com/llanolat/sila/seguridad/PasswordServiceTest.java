package com.llanolat.sila.seguridad;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.llanolat.sila.infra.SilaException;
import org.junit.jupiter.api.Test;

class PasswordServiceTest {

    private final PasswordService p = new PasswordService();

    @Test
    void elHashVerificaYNoEsLaClave() {
        String h = p.hash("Una-clave-Segura-2026");
        assertThat(h).startsWith("$2").doesNotContain("Segura");
        assertThat(p.coincide("Una-clave-Segura-2026", h)).isTrue();
        assertThat(p.coincide("otra", h)).isFalse();
        assertThat(p.coincide("x", null)).isFalse();
    }

    @Test
    void laPoliticaRechazaClavesDebiles() {
        assertThatThrownBy(() -> p.validarPolitica("corta1!", "ana", "x")).isInstanceOf(SilaException.class).hasMessageContaining("12");
        assertThatThrownBy(() -> p.validarPolitica("aaaaaaaaaaaaaaaa", "ana", "x")).hasMessageContaining("repetitiva");
        assertThatThrownBy(() -> p.validarPolitica("kevin.mijares-2026!", "kevin.mijares", "x")).hasMessageContaining("usuario");
        assertThatThrownBy(() -> p.validarPolitica("MiPassword-Largo-9", "ana", "x")).hasMessageContaining("facil");
        assertThatThrownBy(() -> p.validarPolitica("Llanolat-2026-123", "ana", "x")).hasMessageContaining("facil");
        assertThatThrownBy(() -> p.validarPolitica("Sila-12345-6789!", "ana", "x")).hasMessageContaining("facil");
        assertThatThrownBy(() -> p.validarPolitica("Misma-Clave-2026!", "ana", "Misma-Clave-2026!")).hasMessageContaining("distinta");
        assertThatThrownBy(() -> p.validarPolitica("x".repeat(40) + "abcdefghijklmnopqrstuvwxyz0123456789", "ana", "y"))
                .hasMessageContaining("larga");
    }

    @Test
    void aceptaUnaClaveRazonable() {
        assertThatCode(() -> p.validarPolitica("Cuatro-Vacas-Verdes-77", "ana", "otra")).doesNotThrowAnyException();
    }

    @Test
    void unaPalabraDeLaMarcaDentroDeUnaClaveLargaSiSePermite() {
        assertThatCode(() -> p.validarPolitica("VillavoSila123", "kevin.mijares", "temporal")).doesNotThrowAnyException();
        assertThatCode(() -> p.validarPolitica("Mi-Sila-Es-Mejor-9", "ana", "otra")).doesNotThrowAnyException();
    }

    @Test
    void elErrorDePoliticaMarcaElCampoClaveNueva() {
        assertThatThrownBy(() -> p.validarPolitica("corta", "ana", "x"))
                .isInstanceOfSatisfying(SilaException.class,
                        e -> assertThat(e.getCampos()).containsKey("clave_nueva"));
    }

    @Test
    void laClaveTemporalTiene16CaracteresSinAmbiguos() {
        for (int i = 0; i < 50; i++) {
            assertThat(p.generarTemporal()).hasSize(16).matches("[a-zA-Z2-9&&[^lIO01]]{16}");
        }
        assertThat(p.generarTemporal()).isNotEqualTo(p.generarTemporal());
    }
}
