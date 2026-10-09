package com.llanolat.sila.acopio.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/** Una entrega de leche (vw_recepciones). {@code fecha_registro} va en UTC, sin zona.
 * {@code valor_total} = litros x precio_litro; vale 0 si la entrega fue RECHAZADA. */
public record RecepcionDto(
        Long idRecepcion,
        Long idProveedor,
        String proveedor,
        Long idPeriodo,
        LocalDate fecha,
        BigDecimal litros,
        BigDecimal temperatura,
        BigDecimal acidez,
        String estadoCalidad,
        String motivoRechazo,
        String usuarioRegistro,
        LocalDateTime fechaRegistro,
        BigDecimal precioLitro,
        BigDecimal valorTotal
) {}
