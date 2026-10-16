package com.llanolat.sila.archivos;

import com.llanolat.sila.comprobantes.Comprobantes.Comprobante;
import com.llanolat.sila.comprobantes.Comprobantes.Detalle;
import com.llanolat.sila.comprobantes.Comprobantes.Linea;
import com.llanolat.sila.comprobantes.Comprobantes.Pago;
import com.llanolat.sila.infra.Fechas;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.math.BigDecimal;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.time.LocalDateTime;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.GregorianCalendar;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDDocumentInformation;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.font.PDFont;
import org.apache.pdfbox.pdmodel.font.PDType1Font;
import org.apache.pdfbox.pdmodel.font.Standard14Fonts;
import org.apache.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState;
import org.apache.pdfbox.util.Matrix;
import org.springframework.stereotype.Component;

/**
 * Dibuja el PDF de un comprobante interno (NO es una factura). Se genera una sola vez al registrar el movimiento y se
 * congela. Con {@link Anulacion} dibuja la version de anulacion: marca de agua «ANULADO» y el recuadro con el motivo.
 * Solo usa las fuentes estandar del PDF (Helvetica), por eso todo texto se limpia a lo que esa codificacion admite.
 */
@Component
public class GeneradorPdf {

    /** Datos de la anulacion. {@code usuario} y {@code cuando} pueden faltar si el PDF se genera despues, de respaldo. */
    public record Anulacion(String motivo, String usuario, LocalDateTime cuando) {}

    private static final PDRectangle A4 = PDRectangle.A4;
    private static final float M = 42f;                       // margen
    private static final float ANCHO = A4.getWidth() - 2 * M;
    private static final float PIE = 54f;                     // alto reservado abajo
    private static final float[] AZUL = {23 / 255f, 64 / 255f, 91 / 255f};
    private static final float[] ROJO = {176 / 255f, 32 / 255f, 32 / 255f};
    private static final float[] GRIS_TEXTO = {90 / 255f, 98 / 255f, 106 / 255f};
    private static final float[] ZEBRA = {244 / 255f, 246 / 255f, 248 / 255f};
    private static final DateTimeFormatter FECHA = DateTimeFormatter.ofPattern("dd/MM/yyyy");
    private static final DateTimeFormatter FECHA_HORA = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm");

    private final ArchivosProps.Empresa empresa;

    public GeneradorPdf(ArchivosProps props) { this.empresa = props.empresa(); }

    public byte[] generar(Detalle d, Anulacion anulacion, ZonedDateTime emision) {
        try (PDDocument doc = new PDDocument()) {
            new Dibujo(doc, d, anulacion, emision).dibujar();
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            doc.save(out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new IllegalStateException("No se pudo generar el PDF del comprobante.", e);
        }
    }

    // ------------------------------------------------------------------ dibujo

    private final class Dibujo {
        final PDDocument doc;
        final Detalle d;
        final Comprobante c;
        final Anulacion anulacion;
        final ZonedDateTime emision;
        final PDFont normal = new PDType1Font(Standard14Fonts.FontName.HELVETICA);
        final PDFont negrita = new PDType1Font(Standard14Fonts.FontName.HELVETICA_BOLD);
        final List<PDPage> paginas = new ArrayList<>();
        PDPageContentStream cs;
        float y;

        Dibujo(PDDocument doc, Detalle d, Anulacion anulacion, ZonedDateTime emision) {
            this.doc = doc;
            this.d = d;
            this.c = d.comprobante();
            this.anulacion = anulacion;
            this.emision = emision;
        }

        void dibujar() throws IOException {
            nuevaPagina(true);
            datosGenerales();
            tabla();
            totales();
            pagos();
            if (cs != null) cs.close();
            cs = null;
            decorarPaginas();
            info();
        }

        // ---- paginas

        void nuevaPagina(boolean primera) throws IOException {
            if (cs != null) cs.close();
            PDPage p = new PDPage(A4);
            doc.addPage(p);
            paginas.add(p);
            cs = new PDPageContentStream(doc, p);
            if (primera) {
                encabezado();
            } else {
                relleno(AZUL);
                cs.addRect(0, A4.getHeight() - 26, A4.getWidth(), 26);
                cs.fill();
                texto(negrita, 10, M, A4.getHeight() - 17, c.numero() + (anulacion != null ? "  -  ANULADO" : "") + "  (continuacion)", new float[] {1, 1, 1});
                y = A4.getHeight() - 52;
            }
        }

        void encabezado() throws IOException {
            float alto = 78;
            relleno(anulacion != null ? ROJO : AZUL);
            cs.addRect(0, A4.getHeight() - alto, A4.getWidth(), alto);
            cs.fill();
            float[] blanco = {1, 1, 1};
            texto(negrita, 20, M, A4.getHeight() - 34, limpiar(empresa.nombre()), blanco);
            List<String> datos = new ArrayList<>();
            if (hay(empresa.nit())) datos.add("NIT " + empresa.nit());
            if (hay(empresa.direccion())) datos.add(empresa.direccion());
            if (hay(empresa.telefono())) datos.add("Tel. " + empresa.telefono());
            if (!datos.isEmpty()) texto(normal, 8.5f, M, A4.getHeight() - 50, limpiar(String.join("   |   ", datos)), blanco);
            String etiqueta = anulacion != null ? "COMPROBANTE ANULADO" : "COMPROBANTE INTERNO";
            derecha(negrita, 9, A4.getWidth() - M, A4.getHeight() - 34, etiqueta, blanco);
            derecha(normal, 8, A4.getWidth() - M, A4.getHeight() - 48, "Documento interno. No es factura electronica.", blanco);

            y = A4.getHeight() - alto - 34;
            texto(negrita, 22, M, y, limpiar(titulo()), anulacion != null ? ROJO : AZUL);
            y -= 18;
            texto(normal, 10, M, y, limpiar(c.numero()), GRIS_TEXTO);
            y -= 26;
            if (anulacion != null) cuadroAnulacion();
        }

        void cuadroAnulacion() throws IOException {
            String motivo = "Motivo: " + (hay(anulacion.motivo()) ? anulacion.motivo() : (hay(c.motivoAnulacion()) ? c.motivoAnulacion() : "no registrado"));
            String quien = anulacion.usuario() != null && anulacion.cuando() != null
                    ? "Anulado por " + anulacion.usuario() + " el " + FECHA_HORA.format(anulacion.cuando()) + " (hora de Colombia)."
                    : "Anulacion registrada en el sistema. Este PDF se genero el " + FECHA_HORA.format(emision) + " (hora de Colombia).";
            List<String> lineas = new ArrayList<>(envolver(limpiar(motivo), normal, 10, ANCHO - 24));
            lineas.add(limpiar(quien));
            lineas.add("Este es el documento de anulacion. El comprobante original no fue modificado.");
            float alto = 22 + lineas.size() * 14;
            relleno(new float[] {253 / 255f, 238 / 255f, 238 / 255f});
            cs.addRect(M, y - alto, ANCHO, alto);
            cs.fill();
            relleno(ROJO);
            cs.addRect(M, y - alto, 4, alto);
            cs.fill();
            float yy = y - 18;
            texto(negrita, 11, M + 14, yy, "ESTE COMPROBANTE FUE ANULADO", ROJO);
            for (String l : lineas) {
                yy -= 14;
                texto(normal, 9.5f, M + 14, yy, l, new float[] {60 / 255f, 20 / 255f, 20 / 255f});
            }
            y -= alto + 20;
        }

        void datosGenerales() throws IOException {
            List<String[]> filas = new ArrayList<>();
            filas.add(new String[] {"Fecha", FECHA.format(c.fecha())});
            filas.add(new String[] {"Estado", c.estado().equals("ANULADO") ? "Anulado" : "Vigente"});
            if (hay(c.tercero())) filas.add(new String[] {"CLIENTE".equals(c.terceroTipo()) ? "Cliente" : "Proveedor", c.tercero()});
            if (hay(c.descripcion())) filas.add(new String[] {"Concepto", c.descripcion()});
            if (hay(c.metodoPago())) filas.add(new String[] {"Metodo de pago", etiquetaMetodo(c.metodoPago())});
            if (hay(c.referencia())) filas.add(new String[] {"Referencia", c.referencia()});
            if (hay(c.usuarioRegistro())) filas.add(new String[] {"Registrado por", c.usuarioRegistro()});
            float etiquetaX = M, valorX = M + 110;
            for (String[] f : filas) {
                List<String> partes = envolver(limpiar(f[1]), negrita, 10, ANCHO - 110);
                espacio(14 * partes.size());
                texto(normal, 9.5f, etiquetaX, y, f[0], GRIS_TEXTO);
                for (String parte : partes) {
                    texto(negrita, 10, valorX, y, parte, new float[] {0.1f, 0.1f, 0.1f});
                    y -= 14;
                }
            }
            y -= 10;
        }

        void tabla() throws IOException {
            boolean conCantidad = d.lineas().stream().anyMatch(l -> l.cantidad() != null);
            float xConcepto = M + 8;
            float xCant = M + ANCHO - 230, xUnit = M + ANCHO - 150, xValor = M + ANCHO - 8;
            cabeceraTabla(conCantidad, xConcepto, xCant, xUnit, xValor);
            boolean zebra = false;
            for (Linea l : d.lineas()) {
                List<String> concepto = envolver(limpiar(l.concepto()), normal, 9.5f, (conCantidad ? xCant - 70 : xValor - 60) - xConcepto);
                float alto = Math.max(1, concepto.size()) * 13 + 8;
                if (y - alto < PIE + 70) {
                    nuevaPagina(false);
                    cabeceraTabla(conCantidad, xConcepto, xCant, xUnit, xValor);
                    zebra = false;
                }
                if (zebra) {
                    relleno(ZEBRA);
                    cs.addRect(M, y - alto + 4, ANCHO, alto);
                    cs.fill();
                }
                float yy = y - 8;
                for (String parte : concepto) {
                    texto(normal, 9.5f, xConcepto, yy, parte, new float[] {0.1f, 0.1f, 0.1f});
                    yy -= 13;
                }
                float yLinea = y - 8;
                if (conCantidad) {
                    if (l.cantidad() != null) derecha(normal, 9.5f, xCant + 40, yLinea, cantidad(l.cantidad()), new float[] {0.1f, 0.1f, 0.1f});
                    if (l.valorUnitario() != null) derecha(normal, 9.5f, xUnit + 60, yLinea, dinero(l.valorUnitario()), new float[] {0.1f, 0.1f, 0.1f});
                }
                derecha(negrita, 9.5f, xValor, yLinea, dinero(l.valor()), new float[] {0.1f, 0.1f, 0.1f});
                y -= alto;
                zebra = !zebra;
            }
            linea(M, y + 4, M + ANCHO, y + 4);
            y -= 14;
        }

        void cabeceraTabla(boolean conCantidad, float xConcepto, float xCant, float xUnit, float xValor) throws IOException {
            relleno(anulacion != null ? ROJO : AZUL);
            cs.addRect(M, y - 6, ANCHO, 22);
            cs.fill();
            float[] b = {1, 1, 1};
            texto(negrita, 9, xConcepto, y, "DETALLE", b);
            if (conCantidad) {
                derecha(negrita, 9, xCant + 40, y, "CANTIDAD", b);
                derecha(negrita, 9, xUnit + 60, y, "VALOR UNIT.", b);
            }
            derecha(negrita, 9, xValor, y, "VALOR", b);
            y -= 22;
        }

        void totales() throws IOException {
            espacio(80);
            float xEt = M + ANCHO - 230, xVal = M + ANCHO - 8;
            if (d.subtotal() != null) {
                texto(normal, 10, xEt, y, "Subtotal", GRIS_TEXTO);
                derecha(normal, 10, xVal, y, dinero(d.subtotal()), new float[] {0.1f, 0.1f, 0.1f});
                y -= 16;
            }
            if (d.iva() != null) {
                texto(normal, 10, xEt, y, "IVA", GRIS_TEXTO);
                derecha(normal, 10, xVal, y, dinero(d.iva()), new float[] {0.1f, 0.1f, 0.1f});
                y -= 16;
            }
            y -= 8;   // aire entre la ultima linea (IVA) y la caja del total
            relleno(anulacion != null ? ROJO : AZUL);
            cs.addRect(xEt - 10, y - 8, 230 + 10, 26);
            cs.fill();
            float[] b = {1, 1, 1};
            texto(negrita, 11, xEt, y, anulacion != null ? "TOTAL (ANULADO)" : "TOTAL", b);
            derecha(negrita, 12, xVal, y, dinero(c.monto()), b);
            y -= 34;
        }

        void pagos() throws IOException {
            if (d.pagos().isEmpty()) return;
            espacio(40 + 15 * d.pagos().size());
            texto(negrita, 10, M, y, "Forma de pago", anulacion != null ? ROJO : AZUL);
            y -= 16;
            for (Pago p : d.pagos()) {
                String linea = etiquetaMetodo(p.metodoPago()) + (hay(p.referencia()) ? "  -  ref. " + p.referencia() : "");
                texto(normal, 9.5f, M, y, limpiar(linea), new float[] {0.1f, 0.1f, 0.1f});
                derecha(normal, 9.5f, M + 230, y, dinero(p.monto()), new float[] {0.1f, 0.1f, 0.1f});
                y -= 14;
            }
        }

        /** Si no cabe lo que sigue, pasa a una pagina nueva. */
        void espacio(float necesario) throws IOException {
            if (y - necesario < PIE) nuevaPagina(false);
        }

        // ---- pie, marca de agua y metadatos (ya se sabe cuantas paginas son)

        void decorarPaginas() throws IOException {
            int total = paginas.size();
            for (int i = 0; i < total; i++) {
                try (PDPageContentStream s = new PDPageContentStream(doc, paginas.get(i), PDPageContentStream.AppendMode.APPEND, true, true)) {
                    cs = s;
                    linea(M, PIE - 8, M + ANCHO, PIE - 8);
                    texto(normal, 8, M, PIE - 22, limpiar("Comprobante interno generado por SILA  -  " + c.numero()
                            + "  -  " + FECHA_HORA.format(emision) + " (hora de Colombia)"), GRIS_TEXTO);
                    derecha(normal, 8, M + ANCHO, PIE - 22, "Pagina " + (i + 1) + " de " + total, GRIS_TEXTO);
                    if (anulacion != null) marcaDeAgua();
                }
            }
            cs = null;
        }

        void marcaDeAgua() throws IOException {
            PDExtendedGraphicsState gs = new PDExtendedGraphicsState();
            gs.setNonStrokingAlphaConstant(0.16f);
            cs.saveGraphicsState();
            cs.setGraphicsStateParameters(gs);
            relleno(ROJO);
            float tam = 120;
            float ancho = negrita.getStringWidth("ANULADO") / 1000 * tam;
            double ang = Math.toRadians(40);
            float cx = A4.getWidth() / 2, cy = A4.getHeight() / 2;
            float x0 = (float) (cx - Math.cos(ang) * ancho / 2 + Math.sin(ang) * tam * 0.35);
            float y0 = (float) (cy - Math.sin(ang) * ancho / 2 - Math.cos(ang) * tam * 0.35);
            cs.beginText();
            cs.setFont(negrita, tam);
            cs.setTextMatrix(Matrix.getRotateInstance(ang, x0, y0));
            cs.showText("ANULADO");
            cs.endText();
            cs.restoreGraphicsState();
        }

        void info() {
            PDDocumentInformation i = new PDDocumentInformation();
            i.setTitle(limpiar(titulo() + " " + c.numero()));
            i.setAuthor(limpiar(empresa.nombre()));
            i.setCreator("SILA");
            i.setProducer("SILA");
            i.setSubject(anulacion != null ? "Comprobante interno ANULADO" : "Comprobante interno");
            Calendar cal = new GregorianCalendar(TimeZone.getTimeZone(Fechas.COLOMBIA));
            cal.setTimeInMillis(emision.toInstant().toEpochMilli());
            i.setCreationDate(cal);
            doc.setDocumentInformation(i);
        }

        // ---- primitivas

        String titulo() {
            return switch (c.tipo()) {
                case "VENTA" -> "Comprobante de venta";
                case "ABONO" -> "Recibo de abono";
                case "PAGO_LECHERO" -> "Comprobante de pago a lechero";
                case "COMPRA_INSUMO" -> "Comprobante de compra de insumos";
                case "GASTO" -> "Comprobante de gasto";
                default -> "Comprobante";
            };
        }

        void relleno(float[] rgb) throws IOException { cs.setNonStrokingColor(rgb[0], rgb[1], rgb[2]); }

        void linea(float x1, float y1, float x2, float y2) throws IOException {
            cs.setStrokingColor(0.8f, 0.82f, 0.85f);
            cs.setLineWidth(0.6f);
            cs.moveTo(x1, y1);
            cs.lineTo(x2, y2);
            cs.stroke();
        }

        void texto(PDFont f, float tam, float x, float yy, String s, float[] rgb) throws IOException {
            cs.beginText();
            cs.setFont(f, tam);
            cs.setNonStrokingColor(rgb[0], rgb[1], rgb[2]);
            cs.newLineAtOffset(x, yy);
            cs.showText(limpiar(s));
            cs.endText();
        }

        void derecha(PDFont f, float tam, float xDerecha, float yy, String s, float[] rgb) throws IOException {
            String t = limpiar(s);
            texto(f, tam, xDerecha - ancho(f, tam, t), yy, t, rgb);
        }
    }

    // ------------------------------------------------------------- utilidades

    private static float ancho(PDFont f, float tam, String s) {
        try {
            return f.getStringWidth(s) / 1000f * tam;
        } catch (IOException | IllegalArgumentException e) {
            return s.length() * tam * 0.55f;
        }
    }

    private static List<String> envolver(String texto, PDFont f, float tam, float maximo) {
        List<String> lineas = new ArrayList<>();
        StringBuilder actual = new StringBuilder();
        for (String palabra : texto.split(" ")) {
            // una palabra mas larga que la linea se parte
            while (ancho(f, tam, palabra) > maximo && palabra.length() > 1) {
                int corte = palabra.length();
                while (corte > 1 && ancho(f, tam, palabra.substring(0, corte)) > maximo) corte--;
                if (actual.length() > 0) { lineas.add(actual.toString()); actual.setLength(0); }
                lineas.add(palabra.substring(0, corte));
                palabra = palabra.substring(corte);
            }
            String candidata = actual.length() == 0 ? palabra : actual + " " + palabra;
            if (ancho(f, tam, candidata) <= maximo) {
                actual.setLength(0);
                actual.append(candidata);
            } else {
                lineas.add(actual.toString());
                actual.setLength(0);
                actual.append(palabra);
            }
        }
        if (actual.length() > 0 || lineas.isEmpty()) lineas.add(actual.toString());
        return lineas;
    }

    /** Una fuente por hilo: cargar las metricas de Helvetica en cada texto es caro y el objeto no se comparte entre hilos. */
    private static final ThreadLocal<PDType1Font> FUENTE_LIMPIEZA =
            ThreadLocal.withInitial(() -> new PDType1Font(Standard14Fonts.FontName.HELVETICA));

    /** Deja solo lo que Helvetica (WinAnsi) puede dibujar; lo demas se cambia por '?'. Sin saltos ni tabulaciones. */
    static String limpiar(String s) {
        if (s == null) return "";
        if (s.chars().allMatch(c -> c >= 32 && c <= 126)) return s;     // ASCII imprimible: ya es dibujable, sin tocar la fuente
        PDType1Font f = FUENTE_LIMPIEZA.get();
        StringBuilder b = new StringBuilder();
        s.replaceAll("[\\p{Cntrl}]", " ").codePoints().forEach(cp -> {
            String ch = new String(Character.toChars(cp));
            try {
                f.encode(ch);
                b.append(ch);
            } catch (IOException | IllegalArgumentException e) {
                b.append('?');
            }
        });
        return b.toString();
    }

    private static boolean hay(String s) { return s != null && !s.isBlank(); }

    private static String etiquetaMetodo(String m) {
        if (m == null) return "";
        String t = m.toLowerCase(Locale.ROOT);
        return Character.toUpperCase(t.charAt(0)) + t.substring(1);
    }

    private static final DecimalFormatSymbols CO = new DecimalFormatSymbols(Locale.of("es", "CO"));

    static String dinero(BigDecimal v) {
        if (v == null) return "";
        boolean entero = v.stripTrailingZeros().scale() <= 0;
        return "$ " + new DecimalFormat(entero ? "#,##0" : "#,##0.00", CO).format(v);
    }

    static String cantidad(BigDecimal v) {
        return new DecimalFormat("#,##0.###", CO).format(v);
    }
}
