package com.llanolat.sila.consultas.dto;

import java.time.LocalDateTime;

/** Lectura de vw_documentos_pendientes_carga (9 columnas). Generado desde los metadatos de la vista. */
public record DocumentosPendientesCargaDto(
        Long idDocumento,
        String tipoEntidad,
        Long idEntidad,
        String nombreArchivo,
        String mimeType,
        String estadoCarga,
        Integer intentos,
        String ultimoError,
        LocalDateTime fechaRegistro
) {}
