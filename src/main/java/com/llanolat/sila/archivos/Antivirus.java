package com.llanolat.sila.archivos;

import java.io.ByteArrayOutputStream;
import java.io.Closeable;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.channels.Channels;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.Set;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Cliente de ClamAV (clamd), comando zINSTREAM: el archivo viaja por el socket, nunca se escribe a disco sin cifrar.
 * Los archivos quedan en el servidor; ningun tercero los ve.
 *
 * Falla CERRADO: si ClamAV esta habilitado y no responde (o tarda mas del tiempo limite), se lanza
 * {@link AntivirusNoDisponibleException} y la subida se rechaza. Nunca se guarda un archivo sin escanear.
 */
@Component
public class Antivirus {

    private static final Logger log = LoggerFactory.getLogger(Antivirus.class);
    private static final int CHUNK = 64 * 1024;

    /** Resultado del escaneo. {@code firma} es el nombre de la amenaza cuando {@code limpio} es false. */
    public record Resultado(boolean limpio, String firma) {}

    public static class AntivirusNoDisponibleException extends RuntimeException {
        public AntivirusNoDisponibleException(String mensaje, Throwable causa) { super(mensaje, causa); }
    }

    /** Conexion a clamd: por socket Unix o por TCP. */
    private interface Conexion extends Closeable {
        InputStream entrada() throws IOException;
        OutputStream salida() throws IOException;
    }

    private final ArchivosProps.Clamav cfg;
    private final ExecutorService hilos = Executors.newVirtualThreadPerTaskExecutor();

    public Antivirus(ArchivosProps props, org.springframework.core.env.Environment env) {
        this.cfg = props.clamav();
        boolean produccion = java.util.Arrays.stream(env.getActiveProfiles())
                .anyMatch(p -> Set.of("prod", "produccion", "production").contains(p.toLowerCase()));
        if (!cfg.habilitado() && produccion) {
            throw new IllegalStateException("ANTIVIRUS APAGADO PROHIBIDO EN PRODUCCION: con un perfil de produccion activo, "
                    + "sila.archivos.clamav.habilitado debe ser true.");
        }
        if (!cfg.habilitado()) {
            log.warn("ANTIVIRUS DESHABILITADO (sila.archivos.clamav.habilitado=false): los archivos subidos NO se escanean. "
                   + "Solo para desarrollo.");
        }
    }

    public boolean habilitado() { return cfg.habilitado(); }

    public Resultado escanear(byte[] contenido) {
        if (!cfg.habilitado()) {
            return new Resultado(true, null);
        }
        Conexion[] abierta = new Conexion[1];
        Future<String> respuesta = hilos.submit(() -> {
            Conexion c = abrir();
            abierta[0] = c;
            DataOutputStream out = new DataOutputStream(c.salida());
            out.write("zINSTREAM\0".getBytes(StandardCharsets.US_ASCII));
            for (int i = 0; i < contenido.length; i += CHUNK) {
                int n = Math.min(CHUNK, contenido.length - i);
                out.writeInt(n);
                out.write(contenido, i, n);
            }
            out.writeInt(0);
            out.flush();
            return leerRespuesta(c.entrada());
        });
        try {
            return interpretar(respuesta.get(cfg.timeout().toMillis(), TimeUnit.MILLISECONDS));
        } catch (TimeoutException e) {
            respuesta.cancel(true);
            throw new AntivirusNoDisponibleException("El antivirus tardo demasiado.", e);
        } catch (ExecutionException e) {
            throw new AntivirusNoDisponibleException("El antivirus no respondio.", e.getCause());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new AntivirusNoDisponibleException("Escaneo interrumpido.", e);
        } finally {
            if (abierta[0] != null) {
                try { abierta[0].close(); } catch (IOException ignorada) { /* ya se uso */ }
            }
        }
    }

    private Conexion abrir() throws IOException {
        if (cfg.socket() != null && !cfg.socket().isBlank()) {
            SocketChannel canal = SocketChannel.open(StandardProtocolFamily.UNIX);
            try {
                canal.connect(UnixDomainSocketAddress.of(Path.of(cfg.socket())));
            } catch (IOException e) {
                canal.close();
                throw e;
            }
            return new Conexion() {
                public InputStream entrada() { return Channels.newInputStream(canal); }
                public OutputStream salida() { return Channels.newOutputStream(canal); }
                public void close() throws IOException { canal.close(); }
            };
        }
        Socket s = new Socket();
        s.connect(new InetSocketAddress(cfg.host(), cfg.puerto()), (int) cfg.timeout().toMillis());
        return new Conexion() {
            public InputStream entrada() throws IOException { return s.getInputStream(); }
            public OutputStream salida() throws IOException { return s.getOutputStream(); }
            public void close() throws IOException { s.close(); }
        };
    }

    private static String leerRespuesta(InputStream in) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        int c;
        while ((c = in.read()) != -1 && c != 0 && c != '\n') {
            b.write(c);
            if (b.size() > 1024) break;
        }
        return b.toString(StandardCharsets.US_ASCII);
    }

    /** Respuestas de clamd: "stream: OK", "stream: Eicar-Test-Signature FOUND", "... ERROR". */
    static Resultado interpretar(String respuesta) {
        String r = respuesta == null ? "" : respuesta.trim();
        if (r.endsWith("OK")) {
            return new Resultado(true, null);
        }
        if (r.endsWith("FOUND")) {
            String sinPrefijo = r.startsWith("stream:") ? r.substring(7).trim() : r;
            String firma = sinPrefijo.substring(0, sinPrefijo.length() - "FOUND".length()).trim();
            return new Resultado(false, firma.replaceAll("[^A-Za-z0-9._:/ -]", "").trim());
        }
        throw new AntivirusNoDisponibleException("Respuesta inesperada del antivirus: " + r, null);
    }
}
