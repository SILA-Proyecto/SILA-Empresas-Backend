package com.llanolat.sila.archivos;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.llanolat.sila.archivos.Imagenes.Imagen;
import com.llanolat.sila.infra.SilaException;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.ServerSocket;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Base64;
import javax.imageio.ImageIO;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.io.RandomAccessReadBuffer;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class ImagenesTest {

    /** Antivirus apagado (como en desarrollo); las pruebas del antivirus usan el clamd falso de AntivirusTest. */
    private static final Imagenes IMG = new Imagenes(new Antivirus(Fixtures.props(1, false), new MockEnvironment()));

    private static Imagenes conAntivirus(int puerto) {
        return new Imagenes(new Antivirus(Fixtures.props(puerto, true), new MockEnvironment()));
    }

    private static BufferedImage leer(byte[] b) throws IOException {
        return ImageIO.read(new ByteArrayInputStream(b));
    }

    private static void rechaza(byte[] b, String mensaje) {
        assertThatThrownBy(() -> IMG.logo(b)).isInstanceOf(SilaException.class)
                .hasMessageContaining(mensaje)
                .satisfies(e -> assertThat(((SilaException) e).getCodigo()).isEqualTo(SilaException.ARCHIVO_RECHAZADO));
    }

    @Test
    void elLogoGrandeSeReduceSinDeformarseYQuedaEnPng() throws Exception {
        Imagen l = IMG.logo(Fixtures.jpg(2000, 1000));
        BufferedImage img = leer(l.contenido());
        assertThat(l.tipo()).isEqualTo("image/png");
        assertThat(ValidadorSubida.detectarMime(l.contenido())).isEqualTo("image/png");
        assertThat(img.getWidth()).isEqualTo(Imagenes.LADO_LOGO);
        assertThat(img.getHeight()).isEqualTo(Imagenes.LADO_LOGO / 2);
        assertThat(l.sha256()).matches("[0-9a-f]{64}").isEqualTo(Sha256.hex(l.contenido()));
    }

    @Test
    void elLogoPequenoNoSeAgrandaYConservaLaTransparencia() throws Exception {
        BufferedImage t = new BufferedImage(120, 40, BufferedImage.TYPE_INT_ARGB);   // todo transparente
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        ImageIO.write(t, "png", o);
        BufferedImage img = leer(IMG.logo(o.toByteArray()).contenido());
        assertThat(img.getWidth()).isEqualTo(120);
        assertThat(img.getHeight()).isEqualTo(40);
        assertThat(img.getColorModel().hasAlpha()).isTrue();
        assertThat(img.getRGB(10, 10) >>> 24).isZero();
    }

    @Test
    void laFotoSeRecortaAlCuadradoYQuedaEnJpg() throws Exception {
        Imagen f = IMG.foto(Fixtures.png(1200, 800));
        BufferedImage img = leer(f.contenido());
        assertThat(f.tipo()).isEqualTo("image/jpeg");
        assertThat(img.getWidth()).isEqualTo(Imagenes.LADO_FOTO);
        assertThat(img.getHeight()).isEqualTo(Imagenes.LADO_FOTO);
        assertThat(f.contenido().length).isLessThan(64 * 1024);
    }

    @Test
    void laFotoPierdeLosMetadatosExif() throws Exception {
        byte[] jpg = Fixtures.jpg(300, 300);
        // segmento APP1 "Exif" con un texto reconocible, justo despues de SOI
        byte[] carga = "Exif\0\0GPS-SECRETO-4.1234,-73.5678".getBytes(StandardCharsets.ISO_8859_1);
        byte[] app1 = new byte[4 + carga.length];
        app1[0] = (byte) 0xFF;
        app1[1] = (byte) 0xE1;
        app1[2] = (byte) ((carga.length + 2) >> 8);
        app1[3] = (byte) (carga.length + 2);
        System.arraycopy(carga, 0, app1, 4, carga.length);
        byte[] conExif = new byte[jpg.length + app1.length];
        System.arraycopy(jpg, 0, conExif, 0, 2);
        System.arraycopy(app1, 0, conExif, 2, app1.length);
        System.arraycopy(jpg, 2, conExif, 2 + app1.length, jpg.length - 2);
        assertThat(new String(conExif, StandardCharsets.ISO_8859_1)).contains("GPS-SECRETO");

        byte[] limpia = IMG.foto(conExif).contenido();
        assertThat(new String(limpia, StandardCharsets.ISO_8859_1)).doesNotContain("GPS-SECRETO").doesNotContain("Exif");
    }

    @Test
    void seRechazanLosTiposQueNoSonPngNiJpg() throws Exception {
        rechaza("<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>".getBytes(StandardCharsets.UTF_8),
                "PNG o JPG");
        ByteArrayOutputStream gif = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(10, 10, BufferedImage.TYPE_INT_RGB), "gif", gif);
        rechaza(gif.toByteArray(), "PNG o JPG");
        rechaza(Fixtures.pdfSimple(), "PNG o JPG");
        rechaza(new byte[0], "vacia");
    }

    @Test
    void seRechazaLoQueSeDisfrazaDeImagen() {
        byte[] falso = Arrays.copyOf(new byte[] {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}, 200);
        Arrays.fill(falso, 8, 200, (byte) 'A');
        rechaza(falso, "danada");
    }

    @Test
    void seRechazaLaImagenDemasiadoPesadaODemasiadoGrande() throws Exception {
        rechaza(new byte[Imagenes.MAX_BYTES_ENTRADA + 1], "MB");
        // 1x1 PNG cuya cabecera dice 50000 x 50000: se rechaza ANTES de decodificar (no reserva gigas de memoria)
        byte[] png = Base64.getDecoder().decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==");
        png[16] = 0; png[17] = 0; png[18] = (byte) 0xC3; png[19] = 0x50;   // ancho 50000
        png[20] = 0; png[21] = 0; png[22] = (byte) 0xC3; png[23] = 0x50;   // alto 50000
        rechaza(png, "megapixeles");
    }

    @Test
    void elAntivirusRevisaLaImagenTalComoLlegaYLaRechazaSiHayAmenaza() throws Exception {
        // un PNG valido con la firma de prueba EICAR pegada al final: el tipo es correcto, pero el antivirus manda
        byte[] png = Fixtures.png(50, 50);
        byte[] eicar = "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*".getBytes(StandardCharsets.US_ASCII);
        byte[] infectado = Arrays.copyOf(png, png.length + eicar.length);
        System.arraycopy(eicar, 0, infectado, png.length, eicar.length);
        try (ServerSocket ss = new ServerSocket(0)) {
            AntivirusTest.clamdFalso(ss, null, false);
            Imagenes img = conAntivirus(ss.getLocalPort());
            assertThatThrownBy(() -> img.logo(infectado)).isInstanceOf(SilaException.class)
                    .hasMessageContaining("antivirus detecto una amenaza").hasMessageContaining("Eicar-Test-Signature")
                    .satisfies(e -> assertThat(((SilaException) e).getCodigo()).isEqualTo(SilaException.ARCHIVO_RECHAZADO));
        }
        try (ServerSocket ss = new ServerSocket(0)) {
            AntivirusTest.clamdFalso(ss, null, false);
            assertThat(conAntivirus(ss.getLocalPort()).foto(png).tipo()).isEqualTo("image/jpeg");   // limpia: pasa
        }
    }

    @Test
    void sinAntivirusDisponibleLaImagenNoSeGuarda() throws Exception {
        int libre;
        try (ServerSocket ss = new ServerSocket(0)) { libre = ss.getLocalPort(); }
        assertThatThrownBy(() -> conAntivirus(libre).foto(Fixtures.png(20, 20))).isInstanceOf(SilaException.class)
                .satisfies(e -> assertThat(((SilaException) e).getCodigo()).isEqualTo(SilaException.SERVICIO_NO_DISPONIBLE));
    }

    @Test
    void elTipoSeRevisaAntesDeLlamarAlAntivirus() {
        // con un antivirus "habilitado" que no existe: un SVG se rechaza por tipo (422), sin llegar a escanearlo (503)
        assertThatThrownBy(() -> conAntivirus(1).logo("<svg/>".getBytes(StandardCharsets.UTF_8)))
                .satisfies(e -> assertThat(((SilaException) e).getCodigo()).isEqualTo(SilaException.ARCHIVO_RECHAZADO));
    }

    @Test
    void elPdfLlevaElLogoYElPieDeLaEmpresa() throws Exception {
        byte[] logo = IMG.logo(Fixtures.png(300, 120)).contenido();
        GeneradorPdf g = new GeneradorPdf(() -> Fixtures.props(1, false).empresa(),
                () -> new GeneradorPdf.Marca("Gracias por su compra. Resolucion interna 001.", logo));
        byte[] pdf = g.generar(PdfYClavesTest.venta(120, "VIGENTE"), null, java.time.ZonedDateTime.now());
        try (PDDocument d = Loader.loadPDF(new RandomAccessReadBuffer(pdf))) {
            var recursos = d.getPage(0).getResources();
            long imagenes = 0;
            for (var n : recursos.getXObjectNames()) if (recursos.getXObject(n) instanceof PDImageXObject) imagenes++;
            assertThat(imagenes).isEqualTo(1);
            String t = new PDFTextStripper().getText(d);
            // el pie va en todas las paginas, sin pisar la numeracion
            int paginas = d.getNumberOfPages();
            assertThat(paginas).isGreaterThan(1);
            assertThat(t.split("Gracias por su compra", -1)).hasSize(paginas + 1);
            assertThat(t).contains("Pagina " + paginas + " de " + paginas).contains("LLANOLAT SAS");
        }
    }

    @Test
    void unLogoIlegibleNoImpideGenerarElPdf() throws Exception {
        GeneradorPdf g = new GeneradorPdf(() -> Fixtures.props(1, false).empresa(),
                () -> new GeneradorPdf.Marca(null, new byte[] {1, 2, 3}));
        byte[] pdf = g.generar(PdfYClavesTest.venta(2, "VIGENTE"), null, java.time.ZonedDateTime.now());
        assertThat(ValidadorSubida.detectarMime(pdf)).isEqualTo("application/pdf");
    }
}
