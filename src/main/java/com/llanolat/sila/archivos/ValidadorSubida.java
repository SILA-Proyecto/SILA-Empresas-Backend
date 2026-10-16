package com.llanolat.sila.archivos;

import java.awt.geom.AffineTransform;
import java.awt.image.AffineTransformOp;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Iterator;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;
import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.stream.MemoryCacheImageOutputStream;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.cos.COSArray;
import org.apache.pdfbox.cos.COSBase;
import org.apache.pdfbox.cos.COSDictionary;
import org.apache.pdfbox.cos.COSName;
import org.apache.pdfbox.cos.COSObject;
import org.apache.pdfbox.cos.COSStream;
import org.apache.pdfbox.io.RandomAccessReadBuffer;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.springframework.stereotype.Component;

/**
 * Valida y limpia lo que sube el ADMIN. La lista de tipos es cerrada (PDF, JPG, PNG) y el tipo REAL sale de los
 * primeros bytes del archivo, no de la extension ni del Content-Type que declara el navegador.
 *
 *  - Imagenes: se decodifican y se vuelven a escribir. Eso elimina metadatos (EXIF, GPS), datos pegados al final y
 *    cualquier carga escondida en segmentos opcionales. Se limita el tamano en pixeles ANTES de decodificar
 *    (una imagen pequena en bytes puede ocupar gigas en memoria). La orientacion EXIF se aplica antes de perderla.
 *  - PDF: se abre con PDFBox (debe ser un PDF bien formado, sin clave, de pocas paginas) y se rechaza si trae
 *    contenido activo: JavaScript, acciones de lanzar programa/URL/importar, archivos incrustados, formularios XFA,
 *    multimedia. Se guarda tal cual (no se reescribe, para no romper firmas ni formato).
 *
 * Esto NO reemplaza al antivirus: son capas distintas.
 */
@Component
public class ValidadorSubida {

    public static final int MAX_BYTES = 10 * 1024 * 1024;
    static final long MAX_PIXELES = 40_000_000L;     // ~ 6300 x 6300
    static final int MAX_PAGINAS = 300;
    private static final Pattern NOMBRE_CON_EXTENSION = Pattern.compile("^.*\\.([A-Za-z0-9]{1,5})$");

    /** Resultado: el contenido ya limpio, su tipo y el nombre normalizado (con la extension que le corresponde). */
    public record Validado(byte[] contenido, String mime, String nombre) {}

    /** El archivo se rechaza; el mensaje es apto para mostrarse al ADMIN. */
    public static class ArchivoRechazadoException extends RuntimeException {
        public ArchivoRechazadoException(String mensaje) { super(mensaje); }
        public ArchivoRechazadoException(String mensaje, Throwable causa) { super(mensaje, causa); }
    }

    /** Tipo real por los primeros bytes. null si no es PDF, JPG ni PNG. */
    public static String detectarMime(byte[] b) {
        if (b == null || b.length < 8) return null;
        if (b[0] == '%' && b[1] == 'P' && b[2] == 'D' && b[3] == 'F' && b[4] == '-') return "application/pdf";
        if ((b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF) return "image/jpeg";
        if ((b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G'
                && b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A) return "image/png";
        return null;
    }

    public Validado validar(String nombreOriginal, byte[] contenido) {
        return validar(nombreOriginal, contenido, b -> { });
    }

    /**
     * @param escaner se llama con el archivo ya aceptado por tipo y tamano y ANTES de interpretarlo (decodificar una
     *                imagen o abrir un PDF ya es exponerse al contenido): debe lanzar si encuentra una amenaza
     */
    public Validado validar(String nombreOriginal, byte[] contenido, java.util.function.Consumer<byte[]> escaner) {
        if (contenido == null || contenido.length == 0) {
            throw new ArchivoRechazadoException("El archivo esta vacio.");
        }
        if (contenido.length > MAX_BYTES) {
            throw new ArchivoRechazadoException("El archivo supera los " + (MAX_BYTES / 1048576) + " MB.");
        }
        String mime = detectarMime(contenido);
        if (mime == null) {
            throw new ArchivoRechazadoException("Tipo de archivo no permitido. Solo se admiten PDF, JPG y PNG.");
        }
        String nombre = nombreSeguro(nombreOriginal);
        String ext = extension(nombre);
        // La extension declarada debe corresponder al contenido real: foto.pdf que en realidad es PNG se rechaza.
        if (!extensionesDe(mime).contains(ext)) {
            throw new ArchivoRechazadoException("La extension ." + ext + " no corresponde al contenido real del archivo ("
                    + nombreDeTipo(mime) + ").");
        }
        escaner.accept(contenido);
        return switch (mime) {
            case "application/pdf" -> {
                revisarPdf(contenido);
                yield new Validado(contenido, mime, nombre);
            }
            default -> new Validado(recodificar(contenido, mime), mime, nombre);
        };
    }

    // ---------------------------------------------------------------- nombre

    /** Nombre para MOSTRAR: sin rutas, sin caracteres de control; nunca se usa como nombre en disco. */
    static String nombreSeguro(String original) {
        String n = original == null ? "" : original;
        n = n.replace('\\', '/');
        n = n.substring(n.lastIndexOf('/') + 1);
        n = n.replaceAll("[\\p{Cntrl}]", "").trim();
        if (n.length() > 200) {
            String ext = NOMBRE_CON_EXTENSION.matcher(n).matches() ? "." + extension(n) : "";
            n = n.substring(0, 200 - ext.length()) + ext;
        }
        if (n.length() < 3 || !NOMBRE_CON_EXTENSION.matcher(n).matches()) {
            throw new ArchivoRechazadoException("El nombre del archivo debe tener al menos 3 caracteres y su extension.");
        }
        return n;
    }

    static String extension(String nombre) {
        return nombre.substring(nombre.lastIndexOf('.') + 1).toLowerCase(Locale.ROOT);
    }

    private static Set<String> extensionesDe(String mime) {
        return switch (mime) {
            case "application/pdf" -> Set.of("pdf");
            case "image/jpeg" -> Set.of("jpg", "jpeg");
            default -> Set.of("png");
        };
    }

    private static String nombreDeTipo(String mime) {
        return switch (mime) {
            case "application/pdf" -> "PDF";
            case "image/jpeg" -> "JPG";
            default -> "PNG";
        };
    }

    // ------------------------------------------------------------------- PDF

    private static final Set<String> CLAVES_ACTIVAS = Set.of(
            "JS", "JavaScript", "Launch", "EmbeddedFile", "EmbeddedFiles", "RichMedia", "XFA", "SubmitForm",
            "ImportData", "GoToR", "GoToE", "Movie", "Sound", "Rendition", "FileAttachment");
    private static final Set<String> ACCIONES_PELIGROSAS = Set.of(
            "JavaScript", "Launch", "URI", "SubmitForm", "ImportData", "GoToR", "GoToE", "Rendition", "Movie", "Sound");

    void revisarPdf(byte[] contenido) {
        try (PDDocument doc = Loader.loadPDF(new RandomAccessReadBuffer(contenido))) {
            if (doc.isEncrypted()) {
                throw new ArchivoRechazadoException("El PDF esta protegido con clave: no se puede revisar. Suba una copia sin clave.");
            }
            if (doc.getNumberOfPages() < 1 || doc.getNumberOfPages() > MAX_PAGINAS) {
                throw new ArchivoRechazadoException("El PDF debe tener entre 1 y " + MAX_PAGINAS + " paginas.");
            }
            String hallazgo = buscarContenidoActivo(doc.getDocument().getTrailer());
            if (hallazgo != null) {
                throw new ArchivoRechazadoException("El PDF contiene contenido activo (" + hallazgo
                        + "), que no se admite. Genere el PDF de nuevo sin scripts ni archivos adjuntos.");
            }
        } catch (org.apache.pdfbox.pdmodel.encryption.InvalidPasswordException e) {
            throw new ArchivoRechazadoException("El PDF esta protegido con clave: no se puede revisar. Suba una copia sin clave.", e);
        } catch (IOException | RuntimeException e) {
            if (e instanceof ArchivoRechazadoException ar) throw ar;
            throw new ArchivoRechazadoException("El PDF esta danado o no es valido.", e);
        }
    }

    /** Recorre TODOS los objetos alcanzables desde el trailer (con control de ciclos). Devuelve que encontro, o null. */
    static String buscarContenidoActivo(COSBase raiz) {
        java.util.IdentityHashMap<COSBase, Boolean> vistos = new java.util.IdentityHashMap<>();
        java.util.ArrayDeque<COSBase> pila = new java.util.ArrayDeque<>();
        pila.push(raiz);
        int limite = 2_000_000;
        while (!pila.isEmpty()) {
            if (--limite < 0) return "estructura demasiado grande";
            COSBase actual = pila.pop();
            if (actual instanceof COSObject o) actual = o.getObject();
            if (actual == null || vistos.put(actual, Boolean.TRUE) != null) continue;
            if (actual instanceof COSDictionary d) {   // incluye COSStream
                for (var e : d.entrySet()) {
                    String clave = e.getKey().getName();
                    if (CLAVES_ACTIVAS.contains(clave)) return clave;
                    if (clave.equals("S") && e.getValue() instanceof COSName accion && ACCIONES_PELIGROSAS.contains(accion.getName())) {
                        return "accion " + accion.getName();
                    }
                    if (clave.equals("OpenAction") || clave.equals("AA")) {
                        // una accion automatica solo se tolera si es un destino de pagina (arreglo), nunca una accion
                        COSBase v = e.getValue() instanceof COSObject o2 ? o2.getObject() : e.getValue();
                        if (v instanceof COSDictionary) return "accion automatica";
                    }
                    pila.push(e.getValue());
                }
                if (actual instanceof COSStream) { /* el contenido binario no se recorre */ }
            } else if (actual instanceof COSArray a) {
                for (COSBase x : a) pila.push(x);
            }
        }
        return null;
    }

    // -------------------------------------------------------------- imagenes

    private byte[] recodificar(byte[] contenido, String mime) {
        boolean jpeg = mime.equals("image/jpeg");
        try (ImageInputStream in = ImageIO.createImageInputStream(new ByteArrayInputStream(contenido))) {
            Iterator<ImageReader> lectores = ImageIO.getImageReadersByMIMEType(mime);
            if (!lectores.hasNext()) throw new ArchivoRechazadoException("No se puede leer la imagen.");
            ImageReader lector = lectores.next();
            try {
                lector.setInput(in, true, true);
                long px = (long) lector.getWidth(0) * lector.getHeight(0);
                if (px <= 0 || px > MAX_PIXELES) {
                    throw new ArchivoRechazadoException("La imagen es demasiado grande (maximo " + MAX_PIXELES / 1_000_000 + " megapixeles).");
                }
                BufferedImage img = lector.read(0);
                if (jpeg) img = aplicarOrientacion(img, orientacionExif(contenido));
                return escribir(img, jpeg);
            } finally {
                lector.dispose();
            }
        } catch (IOException | RuntimeException e) {
            if (e instanceof ArchivoRechazadoException ar) throw ar;
            throw new ArchivoRechazadoException("La imagen esta danada o no es valida.", e);
        }
    }

    private static byte[] escribir(BufferedImage img, boolean jpeg) throws IOException {
        ByteArrayOutputStream salida = new ByteArrayOutputStream();
        if (jpeg) {
            BufferedImage rgb = img;
            if (img.getType() != BufferedImage.TYPE_INT_RGB && img.getType() != BufferedImage.TYPE_3BYTE_BGR) {
                rgb = new BufferedImage(img.getWidth(), img.getHeight(), BufferedImage.TYPE_INT_RGB);
                var g = rgb.createGraphics();
                g.setColor(java.awt.Color.WHITE);
                g.fillRect(0, 0, rgb.getWidth(), rgb.getHeight());
                g.drawImage(img, 0, 0, null);
                g.dispose();
            }
            ImageWriter w = ImageIO.getImageWritersByMIMEType("image/jpeg").next();
            try (MemoryCacheImageOutputStream os = new MemoryCacheImageOutputStream(salida)) {
                ImageWriteParam p = w.getDefaultWriteParam();
                p.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
                p.setCompressionQuality(0.92f);
                w.setOutput(os);
                w.write(null, new IIOImage(rgb, null, null), p);
            } finally {
                w.dispose();
            }
        } else if (!ImageIO.write(img, "png", salida)) {
            throw new IOException("No hay escritor PNG.");
        }
        return salida.toByteArray();
    }

    /** Orientacion EXIF (1..8) de un JPEG; 1 si no hay. Solo lee el primer segmento APP1 "Exif". */
    static int orientacionExif(byte[] j) {
        try {
            int i = 2;
            while (i + 4 < j.length && (j[i] & 0xFF) == 0xFF) {
                int marca = j[i + 1] & 0xFF;
                int largo = ((j[i + 2] & 0xFF) << 8) | (j[i + 3] & 0xFF);
                if (marca == 0xE1 && largo > 16 && j[i + 4] == 'E' && j[i + 5] == 'x' && j[i + 6] == 'i' && j[i + 7] == 'f') {
                    int t = i + 10;                                       // inicio del encabezado TIFF
                    boolean le = j[t] == 'I';
                    int ifd = t + leer32(j, t + 4, le);
                    int n = leer16(j, ifd, le);
                    for (int k = 0; k < n; k++) {
                        int e = ifd + 2 + 12 * k;
                        if (leer16(j, e, le) == 0x0112) {
                            int v = leer16(j, e + 8, le);
                            return v >= 1 && v <= 8 ? v : 1;
                        }
                    }
                    return 1;
                }
                if (marca == 0xDA) break;                                 // empieza la imagen
                i += 2 + largo;
            }
        } catch (RuntimeException e) {
            // EXIF mal formado: se ignora, la imagen se guarda sin rotar
        }
        return 1;
    }

    private static int leer16(byte[] b, int p, boolean le) {
        return le ? ((b[p + 1] & 0xFF) << 8) | (b[p] & 0xFF) : ((b[p] & 0xFF) << 8) | (b[p + 1] & 0xFF);
    }

    private static int leer32(byte[] b, int p, boolean le) {
        return le ? (leer16(b, p + 2, true) << 16) | leer16(b, p, true) : (leer16(b, p, false) << 16) | leer16(b, p + 2, false);
    }

    static BufferedImage aplicarOrientacion(BufferedImage img, int o) {
        if (o == 1) return img;
        int w = img.getWidth(), h = img.getHeight();
        AffineTransform t = new AffineTransform();
        boolean girada = o >= 5;
        switch (o) {
            case 2 -> { t.scale(-1, 1); t.translate(-w, 0); }
            case 3 -> { t.translate(w, h); t.rotate(Math.PI); }
            case 4 -> { t.scale(1, -1); t.translate(0, -h); }
            case 5 -> { t.rotate(-Math.PI / 2); t.scale(-1, 1); }
            case 6 -> { t.translate(h, 0); t.rotate(Math.PI / 2); }
            case 7 -> { t.scale(-1, 1); t.translate(-h, 0); t.translate(0, w); t.rotate(3 * Math.PI / 2); }
            case 8 -> { t.translate(0, w); t.rotate(3 * Math.PI / 2); }
            default -> { return img; }
        }
        BufferedImage destino = new BufferedImage(girada ? h : w, girada ? w : h,
                img.getType() == 0 ? BufferedImage.TYPE_INT_ARGB : img.getType());
        return new AffineTransformOp(t, AffineTransformOp.TYPE_BILINEAR).filter(img, destino);
    }
}
