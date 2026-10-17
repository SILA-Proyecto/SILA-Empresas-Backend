package com.llanolat.sila.documentos.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.LocalDateTime;

/** Cola y registro de documentos subidos a Google Drive (vw_documentos). Fechas en UTC, sin zona. */
public final class DocumentosDtos {

    public record Documento(
            Long idDocumento,
            String tipoEntidad,
            Long idEntidad,
            String nombreArchivo,
            String mimeType,
            String driveUrl,
            String checksumSha256,
            String estadoCarga,
            Integer intentos,
            String ultimoError,
            String usuarioCarga,
            LocalDateTime fechaRegistro,
            LocalDateTime fechaCarga
    ) {}

    /** tipo_entidad: FACTURA, NOTA_CREDITO o COMPRA (la base verifica que la entidad exista). mime_type por defecto application/pdf. */
    public record RegistrarDocumentoRequest(
            @NotBlank @Pattern(regexp = "FACTURA|NOTA_CREDITO|COMPRA", message = "tipo_entidad debe ser FACTURA, NOTA_CREDITO o COMPRA") String tipoEntidad,
            @NotNull Long idEntidad,
            @NotBlank @Size(min = 3, max = 255) String nombreArchivo,
            @Size(max = 100) String mimeType
    ) {}

    public record MarcarSubidoRequest(
            @NotBlank @Size(max = 150) String driveFileId,
            @Size(max = 500) String driveUrl,
            @Pattern(regexp = "^[A-Fa-f0-9]{64}$", message = "debe ser un SHA-256 en hexadecimal") String checksumSha256
    ) {}

    public record MarcarErrorRequest(@NotBlank @Size(max = 500) String mensaje) {}

    private DocumentosDtos() {}
}
