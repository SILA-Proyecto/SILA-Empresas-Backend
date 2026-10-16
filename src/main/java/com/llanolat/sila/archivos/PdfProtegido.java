package com.llanolat.sila.archivos;

import com.llanolat.sila.infra.SilaException;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.security.SecureRandom;
import java.util.Locale;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.io.RandomAccessReadBuffer;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.encryption.AccessPermission;
import org.apache.pdfbox.pdmodel.encryption.StandardProtectionPolicy;
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject;
import org.springframework.stereotype.Component;

/**
 * Copia de un documento protegida con clave (PDF con AES-256) para compartirla con un cliente o proveedor. El archivo
 * guardado en el servidor no se toca: esto crea una copia nueva en memoria en cada descarga.
 *
 * Las imagenes (JPG/PNG subidas por el ADMIN) no admiten clave, asi que se envuelven en un PDF de una pagina y ese
 * PDF es el que se protege. La clave de propietario es aleatoria y se descarta: nadie puede quitar las restricciones.
 *
 * La clave es solo una barrera contra la persona equivocada: no protege el sistema (es una copia de un comprobante).
 */
@Component
public class PdfProtegido {

    public static final int CLAVE_MIN = 4;
    public static final int CLAVE_MAX = 64;
    private static final String ALFABETO = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";   // sin O/0/I/1/l que se confunden
    private final SecureRandom azar = new SecureRandom();

    public byte[] proteger(byte[] contenido, String mime, String clave) {
        try (PDDocument doc = abrir(contenido, mime)) {
            AccessPermission permisos = new AccessPermission();
            permisos.setCanModify(false);
            permisos.setCanModifyAnnotations(false);
            permisos.setCanAssembleDocument(false);
            permisos.setCanFillInForm(false);
            permisos.setCanPrint(true);
            permisos.setCanExtractContent(true);
            permisos.setCanExtractForAccessibility(true);
            StandardProtectionPolicy politica = new StandardProtectionPolicy(aleatoria(32), clave, permisos);
            politica.setEncryptionKeyLength(256);
            politica.setPreferAES(true);
            doc.protect(politica);
            ByteArrayOutputStream salida = new ByteArrayOutputStream();
            doc.save(salida);
            return salida.toByteArray();
        } catch (IOException e) {
            throw new IllegalStateException("No se pudo proteger el documento con clave.", e);
        }
    }

    private PDDocument abrir(byte[] contenido, String mime) throws IOException {
        if ("application/pdf".equals(mime)) {
            return Loader.loadPDF(new RandomAccessReadBuffer(contenido));
        }
        PDDocument doc = new PDDocument();
        try {
            PDImageXObject img = PDImageXObject.createFromByteArray(doc, contenido, "documento");
            float w = img.getWidth(), h = img.getHeight();
            float escala = Math.min(1f, Math.min(PDRectangle.A4.getWidth() * 1.4f / w, PDRectangle.A4.getHeight() * 1.4f / h));
            PDPage pagina = new PDPage(new PDRectangle(w * escala, h * escala));
            doc.addPage(pagina);
            try (PDPageContentStream cs = new PDPageContentStream(doc, pagina)) {
                cs.drawImage(img, 0, 0, w * escala, h * escala);
            }
            return doc;
        } catch (IOException | RuntimeException e) {
            doc.close();
            throw e;
        }
    }

    // --------------------------------------------------------------- claves

    /** 12 caracteres al azar sin ambiguos, en tres grupos: K7MQ-4XPD-9TRB. Unos 58 bits. */
    public String claveAleatoria() {
        String c = aleatoria(12);
        return c.substring(0, 4) + "-" + c.substring(4, 8) + "-" + c.substring(8);
    }

    private String aleatoria(int largo) {
        StringBuilder b = new StringBuilder(largo);
        for (int i = 0; i < largo; i++) b.append(ALFABETO.charAt(azar.nextInt(ALFABETO.length())));
        return b.toString();
    }

    /** Clave escrita por quien descarga: 4 a 64 caracteres, sin saltos ni caracteres de control. */
    public static String validarEscrita(String clave) {
        if (clave == null || clave.length() < CLAVE_MIN || clave.length() > CLAVE_MAX
                || clave.codePoints().anyMatch(Character::isISOControl)) {
            throw SilaException.parametroInvalido("La clave debe tener entre " + CLAVE_MIN + " y " + CLAVE_MAX
                    + " caracteres, sin saltos de linea.", "clave");
        }
        return clave;
    }

    /**
     * Clave "documento de identidad": el numero registrado, solo letras y digitos, en mayusculas
     * (900.123.456-7 queda 9001234567). Se rechaza un marcador provisional (PEND-...) o algo demasiado corto.
     */
    public static String claveDeDocumento(String numeroDocumento) {
        String n = numeroDocumento == null ? "" : numeroDocumento.trim();
        if (n.toUpperCase(Locale.ROOT).startsWith("PEND")) {
            throw SilaException.de(SilaException.OPERACION_NO_PERMITIDA,
                    "Este tercero no tiene un documento de identidad registrado todavia. Use otra opcion de clave.");
        }
        String limpio = n.replaceAll("[^A-Za-z0-9]", "").toUpperCase(Locale.ROOT);
        if (limpio.length() < CLAVE_MIN) {
            throw SilaException.de(SilaException.OPERACION_NO_PERMITIDA,
                    "El documento de identidad registrado es demasiado corto para usarlo como clave.");
        }
        return limpio;
    }

    /** Pista para mostrar al usuario sin exponer todo el numero: 9001***567. */
    public static String pista(String clave) {
        if (clave.length() <= 6) return clave.charAt(0) + "***" + clave.charAt(clave.length() - 1);
        return clave.substring(0, 3) + "***" + clave.substring(clave.length() - 3);
    }
}
