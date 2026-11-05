package com.llanolat.sila.archivos;

import com.llanolat.sila.infra.SilaException;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Iterator;
import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.stream.MemoryCacheImageOutputStream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Logo de la empresa y foto de perfil, con las MISMAS capas que los archivos del modulo ARCHIVOS:
 *  1. solo PNG y JPG (tipo real por los primeros bytes) y tamano en bytes acotado;
 *  2. ANTIVIRUS (ClamAV) sobre el archivo tal como llego, ANTES de interpretarlo (decodificar ya es exponerse al contenido).
 *     Falla cerrado: si esta habilitado y no responde, la imagen no se guarda (503);
 *  3. tamano en pixeles acotado ANTES de decodificar;
 *  4. se aplica la orientacion EXIF y se vuelve a dibujar desde cero a un tamano fijo. Lo que se guarda nunca es lo que subio la
 *     persona: sin metadatos (EXIF, GPS), sin datos pegados al final y con un peso acotado.
 * No se acepta SVG (puede llevar scripts).
 */
@Component
public class Imagenes {

    private static final Logger log = LoggerFactory.getLogger(Imagenes.class);

    public record Imagen(byte[] contenido, String tipo, String sha256) {}

    public static final int MAX_BYTES_ENTRADA = 5 * 1024 * 1024;
    static final long MAX_PIXELES = 40_000_000L;
    /** El logo cabe en este cuadro (sin agrandarlo) y se guarda en PNG, que conserva la transparencia. */
    static final int LADO_LOGO = 480;
    /** La foto se recorta al cuadrado central y se guarda en JPG. */
    static final int LADO_FOTO = 256;

    private final Antivirus antivirus;

    public Imagenes(Antivirus antivirus) { this.antivirus = antivirus; }

    public Imagen logo(byte[] entrada) {
        BufferedImage img = leer(entrada);
        double f = Math.min(1.0, Math.min((double) LADO_LOGO / img.getWidth(), (double) LADO_LOGO / img.getHeight()));
        int w = Math.max(1, (int) Math.round(img.getWidth() * f)), h = Math.max(1, (int) Math.round(img.getHeight() * f));
        BufferedImage destino = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
        dibujar(img, destino, 0, 0, img.getWidth(), img.getHeight(), null);
        return empaquetar(png(destino), "image/png");
    }

    public Imagen foto(byte[] entrada) {
        BufferedImage img = leer(entrada);
        int lado = Math.min(img.getWidth(), img.getHeight());
        int x = (img.getWidth() - lado) / 2, y = (img.getHeight() - lado) / 2;
        int salida = Math.min(LADO_FOTO, lado);
        BufferedImage destino = new BufferedImage(salida, salida, BufferedImage.TYPE_INT_RGB);
        dibujar(img, destino, x, y, lado, lado, Color.WHITE);
        return empaquetar(jpg(destino), "image/jpeg");
    }

    // ------------------------------------------------------------------

    private BufferedImage leer(byte[] b) {
        if (b == null || b.length == 0) throw rechazo("La imagen esta vacia.");
        if (b.length > MAX_BYTES_ENTRADA) throw rechazo("La imagen supera los " + MAX_BYTES_ENTRADA / 1048576 + " MB.");
        String mime = ValidadorSubida.detectarMime(b);
        if (!"image/png".equals(mime) && !"image/jpeg".equals(mime)) {
            throw rechazo("Solo se admiten imagenes PNG o JPG.");
        }
        escanear(b);
        try (ImageInputStream in = ImageIO.createImageInputStream(new ByteArrayInputStream(b))) {
            Iterator<ImageReader> lectores = ImageIO.getImageReadersByMIMEType(mime);
            if (!lectores.hasNext()) throw rechazo("No se puede leer la imagen.");
            ImageReader lector = lectores.next();
            try {
                lector.setInput(in, true, true);
                long px = (long) lector.getWidth(0) * lector.getHeight(0);
                if (px <= 0 || px > MAX_PIXELES) {
                    throw rechazo("La imagen es demasiado grande (maximo " + MAX_PIXELES / 1_000_000 + " megapixeles).");
                }
                BufferedImage img = lector.read(0);
                return mime.equals("image/jpeg")
                        ? ValidadorSubida.aplicarOrientacion(img, ValidadorSubida.orientacionExif(b)) : img;
            } finally {
                lector.dispose();
            }
        } catch (IOException | RuntimeException e) {
            if (e instanceof SilaException s) throw s;
            // p. ej. un JPG en CMYK, que ImageIO no lee
            throw rechazo("La imagen esta danada o no es valida. Pruebe guardarla de nuevo como PNG o JPG.");
        }
    }

    private void escanear(byte[] b) {
        Antivirus.Resultado r;
        try {
            r = antivirus.escanear(b);
        } catch (Antivirus.AntivirusNoDisponibleException e) {
            log.error("Antivirus no disponible: se rechaza una imagen ({} bytes).", b.length, e);
            throw SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE,
                    "El antivirus no esta disponible, asi que la imagen no se guardo. Intente de nuevo en unos minutos.");
        }
        if (!r.limpio()) {
            log.warn("El antivirus rechazo una imagen ({} bytes): {}", b.length, r.firma());
            throw rechazo("El antivirus detecto una amenaza (" + r.firma() + "). La imagen no se guardo.");
        }
    }

    /**
     * Copia el recorte (sx, sy, sw, sh) de origen escalado al tamano de destino. Si hay que reducir mucho, lo hace a mitades
     * sucesivas: un solo paso bicubico de 4000 a 256 px deja la imagen dentada.
     */
    private static void dibujar(BufferedImage origen, BufferedImage destino, int sx, int sy, int sw, int sh, Color fondo) {
        BufferedImage actual = origen.getSubimage(sx, sy, sw, sh);
        int w = sw, h = sh;
        while (w / 2 >= destino.getWidth() && h / 2 >= destino.getHeight()) {
            w /= 2;
            h /= 2;
            BufferedImage mitad = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
            pintar(actual, mitad, null);
            actual = mitad;
        }
        pintar(actual, destino, fondo);
    }

    private static void pintar(BufferedImage origen, BufferedImage destino, Color fondo) {
        Graphics2D g = destino.createGraphics();
        try {
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
            g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            if (fondo != null) {
                g.setColor(fondo);
                g.fillRect(0, 0, destino.getWidth(), destino.getHeight());
            }
            g.drawImage(origen, 0, 0, destino.getWidth(), destino.getHeight(), null);
        } finally {
            g.dispose();
        }
    }

    private static byte[] png(BufferedImage img) {
        try {
            ByteArrayOutputStream salida = new ByteArrayOutputStream();
            if (!ImageIO.write(img, "png", salida)) throw new IOException("No hay escritor PNG.");
            return salida.toByteArray();
        } catch (IOException e) {
            throw new IllegalStateException("No se pudo escribir el PNG", e);
        }
    }

    private static byte[] jpg(BufferedImage img) {
        ByteArrayOutputStream salida = new ByteArrayOutputStream();
        ImageWriter w = ImageIO.getImageWritersByMIMEType("image/jpeg").next();
        try (MemoryCacheImageOutputStream os = new MemoryCacheImageOutputStream(salida)) {
            ImageWriteParam p = w.getDefaultWriteParam();
            p.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
            p.setCompressionQuality(0.85f);
            w.setOutput(os);
            w.write(null, new IIOImage(img, null, null), p);
        } catch (IOException e) {
            throw new IllegalStateException("No se pudo escribir el JPG", e);
        } finally {
            w.dispose();
        }
        return salida.toByteArray();
    }

    private static Imagen empaquetar(byte[] contenido, String tipo) {
        return new Imagen(contenido, tipo, Sha256.hex(contenido));
    }

    private static SilaException rechazo(String mensaje) {
        return SilaException.de(SilaException.ARCHIVO_RECHAZADO, mensaje);
    }
}
