package com.llanolat.sila.legal;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.llanolat.sila.legal.LegalProps.Documento;
import com.llanolat.sila.legal.LegalProps.Documentos;
import java.time.Duration;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;

class LegalPropsTest {

    private static final LocalDate F = LocalDate.of(2026, 10, 28);

    private static LegalProps con(Documento t, Documento p) {
        return new LegalProps(new Documentos(t, p), Duration.ofSeconds(30));
    }

    @Test
    void versionesValidas() {
        assertThatCode(() -> con(new Documento("1.0", F), new Documento("2026-10-28.a_b", F))).doesNotThrowAnyException();
        assertThatCode(() -> con(new Documento("x".repeat(30), F), new Documento("v", F))).doesNotThrowAnyException();
    }

    @Test
    void versionInvalidaOFaltanteImpideArrancar() {
        for (String mala : new String[] {null, "", " ", "1 0", "1.0;", "1'0", "a/b", "ñ", "x".repeat(31)}) {
            assertThatThrownBy(() -> con(new Documento(mala, F), new Documento("1.0", F))).as("terminos " + mala)
                    .isInstanceOf(IllegalStateException.class).hasMessageContaining("SILA_LEGAL_TERMINOS_VERSION");
            assertThatThrownBy(() -> con(new Documento("1.0", F), new Documento(mala, F))).as("privacidad " + mala)
                    .isInstanceOf(IllegalStateException.class).hasMessageContaining("SILA_LEGAL_PRIVACIDAD_VERSION");
        }
    }

    @Test
    void sinFechaImpideArrancar() {
        assertThatThrownBy(() -> con(new Documento("1.0", null), new Documento("1.0", F)))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("SILA_LEGAL_TERMINOS_FECHA");
        assertThatThrownBy(() -> con(new Documento("1.0", F), null)).isInstanceOf(IllegalStateException.class);
    }
}
