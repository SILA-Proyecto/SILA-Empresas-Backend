package com.llanolat.sila.seguridad;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import org.junit.jupiter.api.Test;

class LimiteTasaTest {

    @Test
    void permiteHastaElMaximoYBloqueaElSiguiente() {
        LimiteTasa l = new LimiteTasa();
        for (int i = 0; i < 3; i++) assertThat(l.permitir("a", 3, Duration.ofMinutes(1))).isTrue();
        assertThat(l.permitir("a", 3, Duration.ofMinutes(1))).isFalse();
    }

    @Test
    void lasClavesSonIndependientes() {
        LimiteTasa l = new LimiteTasa();
        assertThat(l.permitir("a", 1, Duration.ofMinutes(1))).isTrue();
        assertThat(l.permitir("a", 1, Duration.ofMinutes(1))).isFalse();
        assertThat(l.permitir("b", 1, Duration.ofMinutes(1))).isTrue();
    }

    @Test
    void laVentanaSeLibera() throws InterruptedException {
        LimiteTasa l = new LimiteTasa();
        assertThat(l.permitir("a", 1, Duration.ofMillis(50))).isTrue();
        assertThat(l.permitir("a", 1, Duration.ofMillis(50))).isFalse();
        Thread.sleep(80);
        assertThat(l.permitir("a", 1, Duration.ofMillis(50))).isTrue();
    }
}
