package com.llanolat.sila.archivos;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.PosixFilePermissions;
import org.springframework.stereotype.Component;

/**
 * Archivos cifrados en disco: {directorio}/{2 primeros caracteres}/{ruta}.sila. El nombre sale SIEMPRE de una ruta
 * interna ya validada (32 hex), nunca de texto del usuario. Se escribe a un temporal y se mueve (no queda a medias).
 */
@Component
public class AlmacenArchivos {

    private final Path base;

    public AlmacenArchivos(ArchivosProps props) {
        if (props.directorio() == null || props.directorio().isBlank()) {
            throw new IllegalStateException("Falta sila.archivos.directorio (SILA_DOCS_DIR).");
        }
        this.base = Path.of(props.directorio()).toAbsolutePath().normalize();
    }

    public Path directorio() { return base; }

    public void guardar(String ruta, byte[] cifrado) {
        Path destino = destino(ruta);
        try {
            crearDirectorio(destino.getParent());
            Path temporal = Files.createTempFile(destino.getParent(), ".tmp-", ".part");
            try {
                soloDueno(temporal);
                Files.write(temporal, cifrado);
                try {
                    Files.move(temporal, destino, StandardCopyOption.ATOMIC_MOVE);
                } catch (AtomicMoveNotSupportedException e) {
                    Files.move(temporal, destino);
                }
            } finally {
                Files.deleteIfExists(temporal);
            }
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo guardar el archivo.", e);
        }
    }

    /** @return null si el archivo no esta en disco */
    public byte[] leer(String ruta) {
        try {
            return Files.readAllBytes(destino(ruta));
        } catch (NoSuchFileException e) {
            return null;
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo leer el archivo.", e);
        }
    }

    /** Solo para deshacer un guardado cuando fallo el registro en la base; los archivos registrados nunca se borran. */
    public void descartar(String ruta) {
        try {
            Files.deleteIfExists(destino(ruta));
        } catch (IOException e) {
            // se queda huerfano: no es grave, nadie lo referencia
        }
    }

    public void escribirSellado(String nombre, byte[] datos) {
        Path destino = base.resolve(nombre).normalize();
        if (!destino.getParent().equals(base)) throw new IllegalArgumentException("Nombre invalido.");
        try {
            crearDirectorio(base);
            Path temporal = Files.createTempFile(base, ".tmp-", ".part");
            try {
                soloDueno(temporal);
                Files.write(temporal, datos);
                try {
                    Files.move(temporal, destino, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
                } catch (AtomicMoveNotSupportedException e) {
                    Files.move(temporal, destino, StandardCopyOption.REPLACE_EXISTING);
                }
            } finally {
                Files.deleteIfExists(temporal);
            }
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo guardar " + nombre + ".", e);
        }
    }

    public byte[] leerSellado(String nombre) {
        Path origen = base.resolve(nombre).normalize();
        if (!origen.getParent().equals(base)) throw new IllegalArgumentException("Nombre invalido.");
        try {
            return Files.readAllBytes(origen);
        } catch (NoSuchFileException e) {
            return null;
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo leer " + nombre + ".", e);
        }
    }

    public void borrarSellado(String nombre) {
        Path origen = base.resolve(nombre).normalize();
        if (!origen.getParent().equals(base)) throw new IllegalArgumentException("Nombre invalido.");
        try {
            Files.deleteIfExists(origen);
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo borrar " + nombre + ".", e);
        }
    }

    private Path destino(String ruta) {
        if (ruta == null || !CifradoDocs.RUTA_VALIDA.matcher(ruta).matches()) {
            throw new IllegalArgumentException("Ruta interna invalida.");
        }
        return base.resolve(ruta.substring(0, 2)).resolve(ruta + ".sila");
    }

    private static void crearDirectorio(Path dir) throws IOException {
        if (Files.isDirectory(dir)) return;
        try {
            Files.createDirectories(dir, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------")));
        } catch (UnsupportedOperationException e) {
            Files.createDirectories(dir);
        }
    }

    private static void soloDueno(Path archivo) {
        try {
            Files.setPosixFilePermissions(archivo, PosixFilePermissions.fromString("rw-------"));
        } catch (UnsupportedOperationException | IOException e) {
            // sistema sin permisos POSIX: se confia en el directorio
        }
    }
}
