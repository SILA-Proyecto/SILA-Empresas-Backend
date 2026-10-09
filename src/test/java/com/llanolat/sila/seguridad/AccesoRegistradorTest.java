package com.llanolat.sila.seguridad;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class AccesoRegistradorTest {

    @Test
    void noPermiteFalsificarLineasDelLog() {
        assertThat(AccesoRegistrador.limpiar("kevin\nLOGIN_OK usuario=admin", 100)).doesNotContain("\n").doesNotContain("\r");
        assertThat(AccesoRegistrador.limpiar("a\r\nb\tc", 100)).isEqualTo("a  b c");
    }

    @Test
    void acotaElLargo() {
        assertThat(AccesoRegistrador.limpiar("x".repeat(500), 100)).hasSize(100);
        assertThat(AccesoRegistrador.limpiar(null, 10)).isNull();
    }
}
