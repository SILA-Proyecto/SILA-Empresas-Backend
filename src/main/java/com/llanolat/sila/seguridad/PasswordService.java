package com.llanolat.sila.seguridad;

import com.llanolat.sila.infra.SilaException;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.text.Normalizer;
import java.util.Locale;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * Contrasenas: hash BCrypt (costo 12), politica minima y generador de claves temporales.
 * La clave nunca se guarda ni se registra; la base solo recibe el hash.
 */
@Component
public class PasswordService {

    static final int LARGO_MINIMO = 12;
    /** BCrypt solo usa los primeros 72 bytes: una clave mas larga se recortaria en silencio. */
    static final int BYTES_MAXIMOS = 72;
    private static final String ALFABETO_TEMPORAL = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    /** Secuencias que vuelven debil una clave aunque vayan dentro de otra. */
    private static final String[] SECUENCIAS_DEBILES = {"password", "contrasena", "123456", "qwerty", "abcdef", "letmein"};
    /** Palabras comunes o de la marca: se rechazan solo si, quitando numeros y simbolos, la clave ES la palabra. */
    private static final String[] PALABRAS_DEBILES = {"llanolat", "sila", "admin", "administrador", "welcome", "bienvenido", "usuario", "clave"};

    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    private final SecureRandom azar = new SecureRandom();
    /** Hash valido de una clave al azar: para gastar el mismo tiempo cuando el usuario no existe. */
    private final String hashSenuelo = encoder.encode("senuelo-" + azar.nextLong());

    public String hash(String clave) {
        return encoder.encode(clave);
    }

    public boolean coincide(String clave, String hash) {
        return hash != null && encoder.matches(clave, hash);
    }

    /** Evita que la diferencia de tiempo revele si un usuario existe. */
    public void gastarTiempo(String clave) {
        encoder.matches(clave, hashSenuelo);
    }

    public void validarPolitica(String clave, String usuario, String claveActual) {
        if (clave == null || clave.length() < LARGO_MINIMO) {
            throw SilaException.parametroInvalido("La clave nueva debe tener al menos " + LARGO_MINIMO + " caracteres.", "clave_nueva");
        }
        if (clave.getBytes(StandardCharsets.UTF_8).length > BYTES_MAXIMOS) {
            throw SilaException.parametroInvalido("La clave nueva es demasiado larga (maximo 72 bytes).", "clave_nueva");
        }
        if (clave.chars().distinct().count() < 5) {
            throw SilaException.parametroInvalido("La clave nueva es demasiado repetitiva.", "clave_nueva");
        }
        String plana = Normalizer.normalize(clave, Normalizer.Form.NFD).replaceAll("\\p{M}", "").toLowerCase(Locale.ROOT);
        if (usuario != null && plana.contains(usuario.toLowerCase(Locale.ROOT))) {
            throw SilaException.parametroInvalido("La clave nueva no puede contener su nombre de usuario.", "clave_nueva");
        }
        String soloLetras = plana.replaceAll("[^a-z]", "");
        for (String debil : SECUENCIAS_DEBILES) {
            if (plana.contains(debil)) {
                throw debil();
            }
        }
        for (String debil : PALABRAS_DEBILES) {
            if (soloLetras.equals(debil)) {
                throw debil();
            }
        }
        if (clave.equals(claveActual)) {
            throw SilaException.parametroInvalido("La clave nueva debe ser distinta de la actual.", "clave_nueva");
        }
    }

    private static SilaException debil() {
        return SilaException.parametroInvalido("La clave nueva es demasiado facil de adivinar.", "clave_nueva");
    }

    /** Clave temporal legible (sin caracteres ambiguos). Se muestra una sola vez. */
    public String generarTemporal() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 16; i++) {
            sb.append(ALFABETO_TEMPORAL.charAt(azar.nextInt(ALFABETO_TEMPORAL.length())));
        }
        return sb.toString();
    }
}
