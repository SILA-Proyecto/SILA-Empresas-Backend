package com.llanolat.sila.archivos;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.llanolat.sila.comprobantes.Comprobantes.Comprobante;
import com.llanolat.sila.comprobantes.Comprobantes.Detalle;
import com.llanolat.sila.comprobantes.Comprobantes.Linea;
import com.llanolat.sila.comprobantes.Comprobantes.Pago;
import com.llanolat.sila.infra.SilaException;
import java.io.IOException;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.List;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.io.RandomAccessReadBuffer;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.encryption.InvalidPasswordException;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.Test;

class PdfYClavesTest {

    private final PdfProtegido protegido = new PdfProtegido();
    private final GeneradorPdf generador = new GeneradorPdf(Fixtures.props(1, false));

    private static String texto(byte[] pdf) throws IOException {
        try (PDDocument d = Loader.loadPDF(new RandomAccessReadBuffer(pdf))) {
            return new PDFTextStripper().getText(d);
        }
    }

    private static Detalle venta(int lineas, String estado) {
        Comprobante c = new Comprobante("VENTA", 65L, "VENTA #65", "INGRESO", true, LocalDate.of(2026, 10, 15), new BigDecimal("1250000"),
                7L, "CLIENTE", "Distribuidora Muñoz & Hijos — 中文", "Venta contado", "EFECTIVO", null,
                estado, estado.equals("ANULADO") ? "Cliente devolvio todo el pedido por error de digitacion" : null, 3L, "paula.quintana");
        List<Linea> ls = new ArrayList<>();
        for (int i = 1; i <= lineas; i++) {
            ls.add(new Linea("Queso campesino " + i + " (kg) con un nombre bastante largo para forzar el ajuste de linea en la tabla",
                    new BigDecimal("2.5"), new BigDecimal("18000"), new BigDecimal("45000")));
        }
        return new Detalle(c, ls, List.of(new Pago("EFECTIVO", new BigDecimal("1250000"), null)), new BigDecimal("1050420"), new BigDecimal("199580"));
    }

    @Test
    void pdfDeVentaTrazaLosDatosYEsUnPdfValido() throws Exception {
        byte[] pdf = generador.generar(venta(3, "VIGENTE"), null, ZonedDateTime.now());
        assertThat(ValidadorSubida.detectarMime(pdf)).isEqualTo("application/pdf");
        String t = texto(pdf);
        assertThat(t).contains("Comprobante de venta").contains("VENTA #65").contains("LLANOLAT SAS")
                .contains("$ 1.250.000").contains("Queso campesino 1").contains("Subtotal").contains("IVA")
                .contains("No es factura electronica").doesNotContain("ANULADO");
    }

    @Test
    void conMuchasLineasPaginaYNumeraLasPaginas() throws Exception {
        byte[] pdf = generador.generar(venta(120, "VIGENTE"), null, ZonedDateTime.now());
        try (PDDocument d = Loader.loadPDF(new RandomAccessReadBuffer(pdf))) {
            assertThat(d.getNumberOfPages()).isGreaterThan(2);
        }
        assertThat(texto(pdf)).contains("Pagina 1 de").contains("(continuacion)").contains("TOTAL");
    }

    @Test
    void pdfDeAnulacionLlevaMarcaMotivoYQuien() throws Exception {
        byte[] pdf = generador.generar(venta(2, "ANULADO"),
                new GeneradorPdf.Anulacion(null, "kevin.mijares", LocalDateTime.of(2026, 10, 15, 16, 30)), ZonedDateTime.now());
        String t = texto(pdf);
        assertThat(t).contains("ANULADO").contains("ESTE COMPROBANTE FUE ANULADO").contains("error de digitacion")
                .contains("kevin.mijares").contains("15/10/2026 16:30").contains("no fue modificado");
    }

    @Test
    void textoRaroNoRompeElPdf() throws Exception {
        // ideogramas, comillas tipograficas y saltos de linea no existen en Helvetica: se cambian, no revientan
        assertThat(GeneradorPdf.limpiar("Muñoz “comillas” 中\n\tfin")).doesNotContain("\n").doesNotContain("\t").contains("Muñoz");
    }

    @Test
    void laCopiaConClaveSoloAbreConLaClave() throws Exception {
        byte[] original = generador.generar(venta(2, "VIGENTE"), null, ZonedDateTime.now());
        byte[] copia = protegido.proteger(original, "application/pdf", "Secreta-2026");
        assertThatThrownBy(() -> Loader.loadPDF(new RandomAccessReadBuffer(copia))).isInstanceOf(InvalidPasswordException.class);
        assertThatThrownBy(() -> Loader.loadPDF(new RandomAccessReadBuffer(copia), "otra")).isInstanceOf(InvalidPasswordException.class);
        try (PDDocument d = Loader.loadPDF(new RandomAccessReadBuffer(copia), "Secreta-2026")) {
            assertThat(d.isEncrypted()).isTrue();
            assertThat(d.getEncryption().getLength()).isEqualTo(256);
            assertThat(d.getCurrentAccessPermission().canModify()).isFalse();
            assertThat(new PDFTextStripper().getText(d)).contains("VENTA #65");
        }
    }

    @Test
    void laImagenSeEnvuelveEnPdfAntesDeProtegerse() throws Exception {
        byte[] copia = protegido.proteger(Fixtures.png(60, 40), "image/png", "abcd1234");
        try (PDDocument d = Loader.loadPDF(new RandomAccessReadBuffer(copia), "abcd1234")) {
            assertThat(d.getNumberOfPages()).isEqualTo(1);
        }
    }

    @Test
    void clavesDeDocumento() {
        assertThat(PdfProtegido.claveDeDocumento("900.123.456-7")).isEqualTo("9001234567");
        assertThat(PdfProtegido.claveDeDocumento(" 1.234.567 ")).isEqualTo("1234567");
        assertThatThrownBy(() -> PdfProtegido.claveDeDocumento("PEND-0003")).isInstanceOf(SilaException.class);
        assertThatThrownBy(() -> PdfProtegido.claveDeDocumento("12")).isInstanceOf(SilaException.class);
        assertThat(PdfProtegido.pista("9001234567")).isEqualTo("900***567");
    }

    @Test
    void clavesEscritasYAleatorias() {
        assertThat(PdfProtegido.validarEscrita("1234")).isEqualTo("1234");
        assertThatThrownBy(() -> PdfProtegido.validarEscrita("123")).isInstanceOf(SilaException.class);
        assertThatThrownBy(() -> PdfProtegido.validarEscrita("x".repeat(65))).isInstanceOf(SilaException.class);
        assertThatThrownBy(() -> PdfProtegido.validarEscrita("ab\ncd")).isInstanceOf(SilaException.class);
        String a = protegido.claveAleatoria();
        assertThat(a).matches("[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}");
        assertThat(protegido.claveAleatoria()).isNotEqualTo(a);
    }
}
