package com.llanolat.sila.archivos;

import com.llanolat.sila.infra.Page;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Contrato de /api/v1/archivos. Fechas con hora en UTC y sin zona (como el resto del API); las fechas de comprobante
 * son el dia de Colombia. Ver docs/CONTRATO_BACKEND.md del dashboard.
 */
public final class Archivos {

    /**
     * Un archivo (PDF de un comprobante o archivo subido por el ADMIN). No incluye la ruta interna.
     * {@code origen}: COMPROBANTE | ADMIN. {@code version}: ORIGINAL | ANULADO (solo COMPROBANTE).
     * {@code estadoDrive}: PENDIENTE | SUBIDO | ERROR. {@code fecha}: la del comprobante, o el dia en que se subio.
     */
    public record Archivo(
            Long idDocumento, String origen, String tipoEntidad, Long idEntidad, String version, Long idDocumentoOriginal,
            String nombreArchivo, String mimeType, Long tamanoBytes, String checksumSha256,
            Long idCarpeta, String carpeta,
            Boolean archivado, String motivoArchivo, String usuarioArchivo, LocalDateTime fechaArchivo,
            String estadoDrive, LocalDateTime fechaDrive, String usuarioCarga, LocalDateTime fechaRegistro,
            LocalDate fecha, String numero, String sentido, BigDecimal monto,
            Long idTercero, String terceroTipo, String tercero, String estadoComprobante,
            Long idPeriodo, Integer anio, Integer mes, Integer quincena) {}

    /** Uso interno: lo necesario para leer el archivo del disco. Nunca sale por el API. */
    record Interno(
            Long idDocumento, String rutaInterna, String mimeType, String nombreArchivo, String checksumSha256,
            String origen, String tipoEntidad, Long idEntidad, String version,
            Long idTercero, String terceroTipo, String tercero, Boolean archivado) {}

    /** Una carpeta (virtual o manual) dentro del explorador. {@code clave} es lo que se manda en {@code ruta}. */
    public record Entrada(String clave, String nombre, long cantidad) {}

    /**
     * Contenido de una carpeta del explorador. {@code ruta}: el camino hasta aqui (para migas de pan).
     * {@code carpetas}: subcarpetas. {@code archivos}: archivos de ESTA carpeta (vacio en las carpetas que solo
     * contienen otras). {@code puedeSubir}: true solo dentro de "Mis carpetas" y si quien consulta es ADMIN.
     */
    public record Explorador(String arbol, List<Entrada> ruta, List<Entrada> carpetas, Page<Archivo> archivos, boolean puedeSubir) {}

    public record Carpeta(
            Long idCarpeta, Long idPadre, String nombre, String ruta, Integer nivel,
            Boolean archivada, String motivoArchivo, String usuarioArchivo, LocalDateTime fechaArchivo,
            String usuarioCreacion, LocalDateTime fechaCreacion, Integer nArchivos, Integer nSubcarpetas) {}

    public record CrearCarpetaRequest(Long idPadre, @NotBlank @Size(max = 80) String nombre) {}

    public record ArchivarRequest(@NotBlank @Size(min = 5, max = 255) String motivo) {}

    /** modo_clave: DOCUMENTO | ESCRITA | ALEATORIA. {@code clave} solo en ESCRITA. */
    public record DescargaRequest(@NotBlank String modoClave, @Size(max = 64) String clave) {}

    /** Que opciones de clave admite este archivo. */
    public record OpcionesDescarga(
            boolean documentoDisponible, String motivoNoDisponible, String tercero, String terceroTipo,
            String pistaClaveDocumento, int claveMin, int claveMax, boolean esImagen) {}

    public record AccesoDocumento(
            Long idAcceso, LocalDateTime fecha, Long idDocumento, String nombreArchivo, String tipoEntidad, Long idEntidad,
            String version, String usuario, String accion, String modoClave, String ip, String userAgent, String detalle) {}

    /** Estado de la copia de respaldo en Drive. */
    public record DriveEstado(
            boolean configurado, boolean conectado, String cuenta, String carpeta,
            long pendientes, long conError, long subidos, String ultimoError, LocalDateTime ultimaSincronizacion) {}

    public record DriveAutorizacion(String url) {}

    private Archivos() {}
}
