package com.llanolat.sila.archivos;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.llanolat.sila.archivos.ValidadorSubida.ArchivoRechazadoException;
import com.llanolat.sila.archivos.ValidadorSubida.Validado;
import java.io.ByteArrayOutputStream;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.util.Arrays;
import javax.imageio.ImageIO;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.interactive.action.PDActionJavaScript;
import org.apache.pdfbox.pdmodel.interactive.action.PDActionURI;
import org.apache.pdfbox.pdmodel.interactive.annotation.PDAnnotationLink;
import org.junit.jupiter.api.Test;

class ValidadorSubidaTest {

    private final ValidadorSubida v = new ValidadorSubida();

    @Test
    void detectaElTipoRealPorLosPrimerosBytes() throws Exception {
        assertThat(ValidadorSubida.detectarMime(Fixtures.pdfSimple())).isEqualTo("application/pdf");
        assertThat(ValidadorSubida.detectarMime(Fixtures.png(4, 4))).isEqualTo("image/png");
        assertThat(ValidadorSubida.detectarMime(Fixtures.jpg(4, 4))).isEqualTo("image/jpeg");
        assertThat(ValidadorSubida.detectarMime("MZ\u0090\u0000programa.exe".getBytes())).isNull();
        assertThat(ValidadorSubida.detectarMime("<?php echo 1; ?>".getBytes())).isNull();
    }

    @Test
    void unEjecutableRenombradoAFotoSeRechaza() {
        byte[] exe = Arrays.copyOf("MZ".getBytes(), 200);
        assertThatThrownBy(() -> v.validar("foto.jpg", exe)).isInstanceOf(ArchivoRechazadoException.class)
                .hasMessageContaining("Solo se admiten PDF, JPG y PNG");
    }

    @Test
    void laExtensionDebeCorresponderAlContenidoReal() throws Exception {
        assertThatThrownBy(() -> v.validar("documento.pdf", Fixtures.png(8, 8)))
                .isInstanceOf(ArchivoRechazadoException.class).hasMessageContaining("no corresponde");
        assertThatThrownBy(() -> v.validar("imagen.png", Fixtures.pdfSimple()))
                .isInstanceOf(ArchivoRechazadoException.class);
    }

    @Test
    void nombresConRutaSeReducenAlNombreFinal() throws Exception {
        assertThat(v.validar("..\\..\\windows\\system32\\contrato.PDF", Fixtures.pdfSimple()).nombre()).isEqualTo("contrato.PDF");
        assertThat(v.validar("/etc/passwd/x.pdf", Fixtures.pdfSimple()).nombre()).isEqualTo("x.pdf");
        assertThatThrownBy(() -> v.validar("sinextension", Fixtures.pdfSimple())).isInstanceOf(ArchivoRechazadoException.class);
    }

    @Test
    void vacioYDemasiadoGrandeSeRechazan() {
        assertThatThrownBy(() -> v.validar("a.pdf", new byte[0])).isInstanceOf(ArchivoRechazadoException.class);
        byte[] grande = new byte[ValidadorSubida.MAX_BYTES + 1];
        System.arraycopy("%PDF-1.7".getBytes(), 0, grande, 0, 8);
        assertThatThrownBy(() -> v.validar("a.pdf", grande)).isInstanceOf(ArchivoRechazadoException.class).hasMessageContaining("10 MB");
    }

    @Test
    void laImagenSeRecodificaYPierdeLoQueIbaPegadoAlFinal() throws Exception {
        byte[] original = Fixtures.png(16, 16);
        byte[] conCola = Arrays.copyOf(original, original.length + 40);
        System.arraycopy("<script>alert(1)</script>".getBytes(), 0, conCola, original.length, 24);
        Validado r = v.validar("foto.png", conCola);
        assertThat(new String(r.contenido(), java.nio.charset.StandardCharsets.ISO_8859_1)).doesNotContain("<script>");
        BufferedImage img = ImageIO.read(new ByteArrayInputStream(r.contenido()));
        assertThat(img.getWidth()).isEqualTo(16);
    }

    @Test
    void jpgSeRecodificaComoJpg() throws Exception {
        Validado r = v.validar("recibo.jpeg", Fixtures.jpg(32, 20));
        assertThat(r.mime()).isEqualTo("image/jpeg");
        assertThat(ValidadorSubida.detectarMime(r.contenido())).isEqualTo("image/jpeg");
    }

    @Test
    void unaImagenQueOcupariaDemasiadaMemoriaSeRechazaSinDecodificarla() throws Exception {
        // PNG de 7000 x 7000 (49 MP): pesa muy poco en bytes pero revienta la memoria al abrirla
        byte[] enorme = Fixtures.png(7000, 7000);
        assertThat(enorme.length).isLessThan(ValidadorSubida.MAX_BYTES);
        assertThatThrownBy(() -> v.validar("bomba.png", enorme)).isInstanceOf(ArchivoRechazadoException.class)
                .hasMessageContaining("demasiado grande");
    }

    @Test
    void laOrientacionExifSeLee() {
        // JPEG minimo con APP1 Exif, little endian, IFD0 con una entrada 0x0112 = 6
        byte[] jpg = {
            (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE1, 0x00, 0x22, 'E', 'x', 'i', 'f', 0, 0,
            'I', 'I', 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, (byte) 0xFF, (byte) 0xDA};
        assertThat(ValidadorSubida.orientacionExif(jpg)).isEqualTo(6);
    }

    @Test
    void pdfNormalPasaTalCual() throws Exception {
        byte[] pdf = Fixtures.pdfSimple();
        assertThat(v.validar("contrato.pdf", pdf).contenido()).isEqualTo(pdf);
    }

    @Test
    void pdfConJavaScriptSeRechaza() throws Exception {
        byte[] pdf;
        try (PDDocument d = new PDDocument()) {
            d.addPage(new PDPage());
            d.getDocumentCatalog().setOpenAction(new PDActionJavaScript("app.alert('hola')"));
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            d.save(o);
            pdf = o.toByteArray();
        }
        assertThatThrownBy(() -> v.validar("trampa.pdf", pdf)).isInstanceOf(ArchivoRechazadoException.class)
                .hasMessageContaining("contenido activo");
    }

    @Test
    void pdfConEnlaceExternoEnUnaAnotacionSeRechaza() throws Exception {
        byte[] pdf;
        try (PDDocument d = new PDDocument()) {
            PDPage p = new PDPage();
            d.addPage(p);
            PDAnnotationLink link = new PDAnnotationLink();
            PDActionURI uri = new PDActionURI();
            uri.setURI("http://malicioso.example/x");
            link.setAction(uri);
            p.getAnnotations().add(link);
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            d.save(o);
            pdf = o.toByteArray();
        }
        assertThatThrownBy(() -> v.validar("enlace.pdf", pdf)).isInstanceOf(ArchivoRechazadoException.class);
    }

    @Test
    void pdfDanadoOCifradoSeRechaza() throws Exception {
        byte[] roto = "%PDF-1.7\nesto no es un pdf de verdad".getBytes();
        assertThatThrownBy(() -> v.validar("roto.pdf", Arrays.copyOf(roto, roto.length))).isInstanceOf(ArchivoRechazadoException.class);
        byte[] cifrado = new PdfProtegido().proteger(Fixtures.pdfSimple(), "application/pdf", "clave1234");
        assertThatThrownBy(() -> v.validar("con-clave.pdf", cifrado)).isInstanceOf(ArchivoRechazadoException.class)
                .hasMessageContaining("clave");
    }

    @Test
    void elEscanerSeLlamaAntesDeInterpretarElArchivo() throws Exception {
        boolean[] llamado = {false};
        assertThatThrownBy(() -> v.validar("roto.pdf", "%PDF-1.7\nroto".getBytes(), b -> {
            llamado[0] = true;
            throw new ArchivoRechazadoException("amenaza");
        })).hasMessage("amenaza");
        assertThat(llamado[0]).isTrue();
    }
}
