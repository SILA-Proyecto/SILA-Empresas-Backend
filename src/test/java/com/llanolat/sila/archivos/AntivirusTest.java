package com.llanolat.sila.archivos;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.llanolat.sila.archivos.Antivirus.AntivirusNoDisponibleException;
import java.io.DataInputStream;
import java.io.IOException;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

/** Habla con un "clamd" falso que implementa zINSTREAM: valida el protocolo y que falle cerrado. */
class AntivirusTest {

    /** Lee el flujo zINSTREAM completo y responde segun el contenido. */
    private static Thread clamdFalso(ServerSocket ss, String respuestaFija, boolean colgar) {
        Thread t = Thread.startVirtualThread(() -> {
            try (Socket s = ss.accept()) {
                if (colgar) { Thread.sleep(10_000); return; }
                DataInputStream in = new DataInputStream(s.getInputStream());
                byte[] cmd = new byte["zINSTREAM\0".length()];
                in.readFully(cmd);
                assertThat(new String(cmd, StandardCharsets.US_ASCII)).isEqualTo("zINSTREAM\0");
                var todo = new java.io.ByteArrayOutputStream();
                int n;
                while ((n = in.readInt()) > 0) { byte[] b = new byte[n]; in.readFully(b); todo.write(b); }
                String r = respuestaFija != null ? respuestaFija
                        : (todo.toString(StandardCharsets.ISO_8859_1).contains("EICAR") ? "stream: Eicar-Test-Signature FOUND" : "stream: OK");
                s.getOutputStream().write((r + "\0").getBytes(StandardCharsets.US_ASCII));
            } catch (IOException | InterruptedException e) { /* el cliente cerro o se corto */ }
        });
        return t;
    }

    private static Antivirus con(int puerto, boolean habilitado) {
        return new Antivirus(Fixtures.props(puerto, habilitado), new MockEnvironment());
    }

    @Test
    void archivoLimpio() throws Exception {
        try (ServerSocket ss = new ServerSocket(0)) {
            clamdFalso(ss, null, false);
            assertThat(con(ss.getLocalPort(), true).escanear(new byte[200_000]).limpio()).isTrue();   // varios bloques
        }
    }

    @Test
    void amenazaDetectada() throws Exception {
        try (ServerSocket ss = new ServerSocket(0)) {
            clamdFalso(ss, null, false);
            var r = con(ss.getLocalPort(), true).escanear("X5O!P%@AP EICAR-STANDARD".getBytes());
            assertThat(r.limpio()).isFalse();
            assertThat(r.firma()).isEqualTo("Eicar-Test-Signature");
        }
    }

    @Test
    void sinAntivirusFallaCerrado() throws Exception {
        int libre;
        try (ServerSocket ss = new ServerSocket(0)) { libre = ss.getLocalPort(); }
        assertThatThrownBy(() -> con(libre, true).escanear(new byte[10])).isInstanceOf(AntivirusNoDisponibleException.class);
    }

    @Test
    void sinRespuestaFallaCerradoPorTiempo() throws Exception {
        try (ServerSocket ss = new ServerSocket(0)) {
            clamdFalso(ss, null, true);
            assertThatThrownBy(() -> con(ss.getLocalPort(), true).escanear(new byte[10])).isInstanceOf(AntivirusNoDisponibleException.class);
        }
    }

    @Test
    void respuestaRaraTambienFallaCerrado() throws Exception {
        try (ServerSocket ss = new ServerSocket(0)) {
            clamdFalso(ss, "INSTREAM size limit exceeded. ERROR", false);
            assertThatThrownBy(() -> con(ss.getLocalPort(), true).escanear(new byte[10])).isInstanceOf(AntivirusNoDisponibleException.class);
        }
    }

    @Test
    void apagadoNoEscaneaPeroEnProduccionNoArranca() {
        assertThat(con(1, false).escanear(new byte[5]).limpio()).isTrue();
        MockEnvironment prod = new MockEnvironment();
        prod.setActiveProfiles("prod");
        assertThatThrownBy(() -> new Antivirus(Fixtures.props(1, false), prod)).isInstanceOf(IllegalStateException.class);
    }
}
