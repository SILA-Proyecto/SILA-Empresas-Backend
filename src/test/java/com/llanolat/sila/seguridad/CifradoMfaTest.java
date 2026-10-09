package com.llanolat.sila.seguridad;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.security.SecureRandom;
import java.time.Duration;
import java.util.Base64;
import java.util.List;
import org.junit.jupiter.api.Test;

class CifradoMfaTest {

    private static CifradoMfa conClave(byte fill) {
        byte[] k = new byte[32];
        java.util.Arrays.fill(k, fill);
        return new CifradoMfa(new SeguridadProps("jwt", "x", "OPERATIVO", null, Base64.getEncoder().encodeToString(k),
                Duration.ofMinutes(15), Duration.ofMinutes(5), Duration.ofHours(12), true, List.of("ADMIN"), "sila"));
    }

    @Test
    void descifraLoQueCifro() {
        CifradoMfa c = conClave((byte) 7);
        byte[] secreto = new byte[20];
        new SecureRandom().nextBytes(secreto);
        assertThat(c.descifrar(c.cifrar(secreto, 5L), 5L)).isEqualTo(secreto);
    }

    @Test
    void cadaCifradoUsaUnIvDistinto() {
        CifradoMfa c = conClave((byte) 7);
        byte[] secreto = new byte[20];
        assertThat(c.cifrar(secreto, 1L)).isNotEqualTo(c.cifrar(secreto, 1L));
    }

    @Test
    void unSecretoCopiadoALaFilaDeOtroUsuarioNoDescifra() {
        CifradoMfa c = conClave((byte) 7);
        String cifrado = c.cifrar(new byte[20], 1L);
        assertThatThrownBy(() -> c.descifrar(cifrado, 2L)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void otraClaveNoDescifra() {
        String cifrado = conClave((byte) 7).cifrar(new byte[20], 1L);
        assertThatThrownBy(() -> conClave((byte) 8).descifrar(cifrado, 1L)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void siSeAlteraElTextoCifradoFalla() {
        CifradoMfa c = conClave((byte) 7);
        byte[] bytes = Base64.getDecoder().decode(c.cifrar(new byte[20], 1L));
        bytes[bytes.length - 1] ^= 1;
        String alterado = Base64.getEncoder().encodeToString(bytes);
        assertThatThrownBy(() -> c.descifrar(alterado, 1L)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void sinClaveConfiguradaElArranqueFalla() {
        assertThatThrownBy(() -> new CifradoMfa(new SeguridadProps("jwt", "x", "OPERATIVO", null, "",
                Duration.ofMinutes(15), Duration.ofMinutes(5), Duration.ofHours(12), true, List.of("ADMIN"), "sila")))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("SILA_MFA_KEY");
    }
}
