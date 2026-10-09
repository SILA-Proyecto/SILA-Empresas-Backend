package com.llanolat.sila.consultas.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/** Lectura de vw_facturas (12 columnas). Generado desde los metadatos de la vista. */
public record FacturasDto(
        Long idFactura,
        Long idVenta,
        String numeroFactura,
        LocalDate fechaEmision,
        LocalDate fechaVencimiento,
        BigDecimal subtotalBase,
        BigDecimal totalIva,
        BigDecimal totalFactura,
        String cufe,
        String qrCodeUrl,
        String estadoDian,
        String usuarioEmisor
) {}
