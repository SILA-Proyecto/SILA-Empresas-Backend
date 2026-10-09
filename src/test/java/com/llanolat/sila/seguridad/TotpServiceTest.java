package com.llanolat.sila.seguridad;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import org.junit.jupiter.api.Test;

/** Vectores de prueba del RFC 6238 (Apendice B, HMAC-SHA1, secreto "12345678901234567890"); el RFC da 8 digitos, aqui se comparan los ultimos 6. */
class TotpServiceTest {

    private static final byte[] SECRETO = "12345678901234567890".getBytes(StandardCharsets.US_ASCII);
    private final TotpService totp = new TotpService();

    private String codigoEn(long segundos) {
        return totp.codigo(SECRETO, totp.paso(Instant.ofEpochSecond(segundos)));
    }

    @Test
    void coincideConLosVectoresDelRfc6238() {
        assertThat(codigoEn(59L)).isEqualTo("287082");          // 94287082
        assertThat(codigoEn(1111111109L)).isEqualTo("081804");  // 07081804
        assertThat(codigoEn(1111111111L)).isEqualTo("050471");  // 14050471
        assertThat(codigoEn(1234567890L)).isEqualTo("005924");  // 89005924
        assertThat(codigoEn(2000000000L)).isEqualTo("279037");  // 69279037
        assertThat(codigoEn(20000000000L)).isEqualTo("353130"); // 65353130
    }

    @Test
    void aceptaUnPasoDeToleranciaPeroNoDos() {
        Instant t = Instant.ofEpochSecond(1111111109L);
        long actual = totp.paso(t);
        assertThat(totp.verificar(SECRETO, totp.codigo(SECRETO, actual), t)).hasValue(actual);
        assertThat(totp.verificar(SECRETO, totp.codigo(SECRETO, actual - 1), t)).hasValue(actual - 1);
        assertThat(totp.verificar(SECRETO, totp.codigo(SECRETO, actual + 1), t)).hasValue(actual + 1);
        assertThat(totp.verificar(SECRETO, totp.codigo(SECRETO, actual - 2), t)).isEmpty();
        assertThat(totp.verificar(SECRETO, totp.codigo(SECRETO, actual + 2), t)).isEmpty();
    }

    @Test
    void rechazaCodigosMalFormados() {
        Instant t = Instant.ofEpochSecond(59L);
        assertThat(totp.verificar(SECRETO, null, t)).isEmpty();
        assertThat(totp.verificar(SECRETO, "", t)).isEmpty();
        assertThat(totp.verificar(SECRETO, "12345", t)).isEmpty();
        assertThat(totp.verificar(SECRETO, "1234567", t)).isEmpty();
        assertThat(totp.verificar(SECRETO, "28708a", t)).isEmpty();
    }

    @Test
    void base32SigueElRfc4648() {
        assertThat(totp.aBase32("12345678901234567890".getBytes(StandardCharsets.US_ASCII)))
                .isEqualTo("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
        assertThat(totp.aBase32("foobar".getBytes(StandardCharsets.US_ASCII))).isEqualTo("MZXW6YTBOI");
    }

    @Test
    void elUriOtpauthLlevaSecretoEmisorYParametros() {
        String uri = totp.uri("kevin.mijares", SECRETO);
        assertThat(uri).startsWith("otpauth://totp/SILA%20Llanolat:kevin.mijares?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
                       .contains("issuer=SILA%20Llanolat").contains("digits=6").contains("period=30");
    }
}
