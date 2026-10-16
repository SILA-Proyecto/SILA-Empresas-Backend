package com.llanolat.sila.archivos;

import com.llanolat.sila.archivos.ArchivosProps.Clamav;
import com.llanolat.sila.archivos.ArchivosProps.Drive;
import com.llanolat.sila.archivos.ArchivosProps.Empresa;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.Duration;
import java.util.Base64;
import javax.imageio.ImageIO;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;

final class Fixtures {

    static ArchivosProps props(int puertoClamav, boolean antivirus) {
        byte[] k = new byte[32];
        java.util.Arrays.fill(k, (byte) 9);
        return new ArchivosProps(System.getProperty("java.io.tmpdir") + "/sila-test-docs", Base64.getEncoder().encodeToString(k),
                null, "sistema.archivos", new Empresa("LLANOLAT SAS", "900.123.456-7", "Calle 1 # 2-3", "3001234567"),
                new Clamav(antivirus, "127.0.0.1", puertoClamav, null, Duration.ofSeconds(2)),
                new Drive(null, null, null, null, "a", "b", "c", "SILA-respaldo", Duration.ofMinutes(1)));
    }

    static byte[] pdfSimple() throws IOException {
        try (PDDocument d = new PDDocument()) {
            d.addPage(new PDPage());
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            d.save(o);
            return o.toByteArray();
        }
    }

    static byte[] png(int w, int h) throws IOException {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB), "png", o);
        return o.toByteArray();
    }

    static byte[] jpg(int w, int h) throws IOException {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB), "jpg", o);
        return o.toByteArray();
    }

    private Fixtures() {}
}
