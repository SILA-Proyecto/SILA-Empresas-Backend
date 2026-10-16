package com.llanolat.sila.archivos;

import com.llanolat.sila.seguridad.Claves;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.regex.Pattern;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.stereotype.Component;

/**
 * Cifrado de los archivos en disco y en Drive: AES-256-GCM con la llave SILA_DOCS_KEY.
 *
 * Formato (lo mismo en disco que en Drive, para que "Ver documento" descifre lo bajado de Drive):
 *
 *     "SILA" | 0x01 | ruta_interna (32 ASCII) | IV (12) | texto cifrado + etiqueta GCM (16)
 *
 * Todo lo que va antes del IV es dato asociado (AAD): cambiar la ruta del encabezado, o poner el contenido de un
 * archivo con el nombre de otro, hace fallar la autenticacion. El nombre del archivo ya es la ruta interna, asi que
 * el archivo sabe quien es aunque Drive o alguien lo renombre.
 */
@Component
public class CifradoDocs {

    private static final byte[] MAGIA = {'S', 'I', 'L', 'A', 1};
    private static final int RUTA = 32;
    private static final int IV = 12;
    private static final int ENCABEZADO = MAGIA.length + RUTA;
    private static final int TAG_BITS = 128;
    static final Pattern RUTA_VALIDA = Pattern.compile("^[a-f0-9]{32}$");

    public record Descifrado(String ruta, byte[] contenido) {}

    private final SecretKeySpec clave;
    private final SecureRandom azar = new SecureRandom();

    public CifradoDocs(ArchivosProps props) {
        this.clave = new SecretKeySpec(Claves.decodificar(props.docsKey(), "SILA_DOCS_KEY", 32), 0, 32, "AES");
    }

    /** Ruta interna nueva: 128 bits al azar en hexadecimal. */
    public String nuevaRuta() {
        byte[] b = new byte[16];
        azar.nextBytes(b);
        return java.util.HexFormat.of().formatHex(b);
    }

    public byte[] cifrar(byte[] contenido, String ruta) {
        if (ruta == null || !RUTA_VALIDA.matcher(ruta).matches()) {
            throw new IllegalArgumentException("Ruta interna invalida.");
        }
        try {
            byte[] encabezado = new byte[ENCABEZADO];
            System.arraycopy(MAGIA, 0, encabezado, 0, MAGIA.length);
            System.arraycopy(ruta.getBytes(StandardCharsets.US_ASCII), 0, encabezado, MAGIA.length, RUTA);
            byte[] iv = new byte[IV];
            azar.nextBytes(iv);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, clave, new GCMParameterSpec(TAG_BITS, iv));
            c.updateAAD(encabezado);
            byte[] ct = c.doFinal(contenido);
            byte[] salida = new byte[ENCABEZADO + IV + ct.length];
            System.arraycopy(encabezado, 0, salida, 0, ENCABEZADO);
            System.arraycopy(iv, 0, salida, ENCABEZADO, IV);
            System.arraycopy(ct, 0, salida, ENCABEZADO + IV, ct.length);
            return salida;
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("No se pudo cifrar el archivo.", e);
        }
    }

    /** La ruta que dice el encabezado, o null si no es un archivo de SILA. No descifra ni autentica. */
    public static String rutaDe(byte[] cifrado) {
        if (cifrado == null || cifrado.length < ENCABEZADO + IV + 16
                || !Arrays.equals(Arrays.copyOfRange(cifrado, 0, MAGIA.length), MAGIA)) {
            return null;
        }
        String ruta = new String(cifrado, MAGIA.length, RUTA, StandardCharsets.US_ASCII);
        return RUTA_VALIDA.matcher(ruta).matches() ? ruta : null;
    }

    /** @throws ArchivoIlegibleException si no es de SILA, esta alterado o se cifro con otra llave */
    public Descifrado descifrar(byte[] cifrado) {
        String ruta = rutaDe(cifrado);
        if (ruta == null) {
            throw new ArchivoIlegibleException("El archivo no es un documento cifrado de SILA.");
        }
        try {
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, clave, new GCMParameterSpec(TAG_BITS, cifrado, ENCABEZADO, IV));
            c.updateAAD(cifrado, 0, ENCABEZADO);
            return new Descifrado(ruta, c.doFinal(cifrado, ENCABEZADO + IV, cifrado.length - ENCABEZADO - IV));
        } catch (GeneralSecurityException e) {
            throw new ArchivoIlegibleException("El archivo esta alterado o se cifro con otra llave.");
        }
    }

    /** Cifra datos propios del sistema (p. ej. el acceso a Drive) atados a una etiqueta. Sin encabezado de archivo. */
    public byte[] sellar(byte[] datos, String etiqueta) {
        try {
            byte[] iv = new byte[IV];
            azar.nextBytes(iv);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, clave, new GCMParameterSpec(TAG_BITS, iv));
            c.updateAAD(etiqueta.getBytes(StandardCharsets.UTF_8));
            byte[] ct = c.doFinal(datos);
            byte[] salida = new byte[IV + ct.length];
            System.arraycopy(iv, 0, salida, 0, IV);
            System.arraycopy(ct, 0, salida, IV, ct.length);
            return salida;
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("No se pudo cifrar.", e);
        }
    }

    public byte[] abrir(byte[] sellado, String etiqueta) {
        try {
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, clave, new GCMParameterSpec(TAG_BITS, sellado, 0, IV));
            c.updateAAD(etiqueta.getBytes(StandardCharsets.UTF_8));
            return c.doFinal(sellado, IV, sellado.length - IV);
        } catch (GeneralSecurityException | RuntimeException e) {
            throw new ArchivoIlegibleException("No se pudo abrir el dato cifrado (llave distinta o dato alterado).");
        }
    }

    /** El contenido no se puede leer: no es de SILA, esta alterado o la llave no es la que lo cifro. */
    public static class ArchivoIlegibleException extends RuntimeException {
        public ArchivoIlegibleException(String mensaje) { super(mensaje); }
    }
}
