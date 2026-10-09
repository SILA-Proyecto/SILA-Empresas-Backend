package com.llanolat.sila.seguridad;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.ByteBuffer;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.OptionalLong;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.stereotype.Component;

/**
 * Segundo factor TOTP (RFC 6238): HMAC-SHA1, pasos de 30 s, 6 digitos; compatible con
 * Google Authenticator, Microsoft Authenticator, Authy y similares.
 * Se acepta un paso de tolerancia a cada lado por la deriva de reloj del telefono.
 * Verificada contra los vectores de prueba del RFC (ver TotpServiceTest).
 */
@Component
public class TotpService {

    static final int PASO_SEGUNDOS = 30;
    static final int DIGITOS = 6;
    private static final String BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    private final SecureRandom azar = new SecureRandom();

    public byte[] nuevoSecreto() {
        byte[] s = new byte[20];
        azar.nextBytes(s);
        return s;
    }

    public long paso(Instant instante) {
        return Math.floorDiv(instante.getEpochSecond(), PASO_SEGUNDOS);
    }

    /** Codigo de 6 digitos para un paso (con ceros a la izquierda). */
    public String codigo(byte[] secreto, long paso) {
        try {
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(new SecretKeySpec(secreto, "HmacSHA1"));
            byte[] h = mac.doFinal(ByteBuffer.allocate(8).putLong(paso).array());
            int offset = h[h.length - 1] & 0x0f;
            int binario = ((h[offset] & 0x7f) << 24) | ((h[offset + 1] & 0xff) << 16)
                        | ((h[offset + 2] & 0xff) << 8) | (h[offset + 3] & 0xff);
            int mod = (int) Math.pow(10, DIGITOS);
            return String.format("%0" + DIGITOS + "d", binario % mod);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Devuelve el paso que coincide (para impedir reutilizarlo), o vacio si el codigo no es valido. */
    public OptionalLong verificar(byte[] secreto, String ingresado, Instant ahora) {
        if (ingresado == null || !ingresado.matches("\\d{" + DIGITOS + "}")) {
            return OptionalLong.empty();
        }
        long actual = paso(ahora);
        for (long p = actual - 1; p <= actual + 1; p++) {
            // comparacion en tiempo constante
            if (MessageDigest.isEqual(codigo(secreto, p).getBytes(StandardCharsets.UTF_8),
                                      ingresado.getBytes(StandardCharsets.UTF_8))) {
                return OptionalLong.of(p);
            }
        }
        return OptionalLong.empty();
    }

    public String aBase32(byte[] datos) {
        StringBuilder sb = new StringBuilder();
        int buffer = 0, bits = 0;
        for (byte b : datos) {
            buffer = (buffer << 8) | (b & 0xff);
            bits += 8;
            while (bits >= 5) {
                sb.append(BASE32.charAt((buffer >> (bits - 5)) & 31));
                bits -= 5;
            }
        }
        if (bits > 0) {
            sb.append(BASE32.charAt((buffer << (5 - bits)) & 31));
        }
        return sb.toString();
    }

    /** URI otpauth:// que el dashboard convierte en codigo QR. */
    public String uri(String usuario, byte[] secreto) {
        String emisor = "SILA Llanolat";
        return "otpauth://totp/" + enc(emisor) + ":" + enc(usuario)
             + "?secret=" + aBase32(secreto) + "&issuer=" + enc(emisor)
             + "&algorithm=SHA1&digits=" + DIGITOS + "&period=" + PASO_SEGUNDOS;
    }

    private static String enc(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8).replace("+", "%20");
    }
}
