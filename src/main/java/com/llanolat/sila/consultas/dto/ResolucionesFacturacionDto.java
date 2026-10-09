package com.llanolat.sila.consultas.dto;

import java.time.LocalDate;

/** Lectura de vw_resoluciones_facturacion (10 columnas). Generado desde los metadatos de la vista. */
public record ResolucionesFacturacionDto(
        Long idResolucion,
        String tipoDocumento,
        String numeroResolucion,
        String prefijo,
        Integer rangoDesde,
        Integer rangoHasta,
        Integer consecutivoActual,
        LocalDate vigenteDesde,
        LocalDate vigenteHasta,
        Integer activa
) {}
