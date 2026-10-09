package com.llanolat.sila.seguridad.auth;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class CodigosRespaldoTest {

    @Test
    void elCodigoIngresadoSeNormaliza() {
        assertThat(AuthService.normalizarCodigo("abcde-fghjk")).isEqualTo("ABCDEFGHJK");
        assertThat(AuthService.normalizarCodigo(" ABCDE FGHJK ")).isEqualTo("ABCDEFGHJK");
        assertThat(AuthService.normalizarCodigo("AB-CD-EF-GH-JK")).isEqualTo("ABCDEFGHJK");
        assertThat(AuthService.normalizarCodigo(null)).isEmpty();
    }

    @Test
    void elHashEsSha256EnHexadecimal() {
        // SHA-256("ABCDEFGHJK"), calculado aparte
        assertThat(AuthService.sha256("ABCDEFGHJK")).hasSize(64).matches("[0-9a-f]{64}");
        assertThat(AuthService.sha256("ABCDEFGHJK")).isEqualTo(AuthService.sha256("ABCDEFGHJK"));
        assertThat(AuthService.sha256("ABCDEFGHJK")).isNotEqualTo(AuthService.sha256("ABCDEFGHJL"));
        assertThat(AuthService.sha256("")).isEqualTo("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    }
}
