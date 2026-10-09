package com.llanolat.sila.catalogos.dto;

import java.math.BigDecimal;

/** Fila de vw_clientes. Columnas snake_case en JSON; `activo` es booleano. */
public record ClienteDto(
        Long idCliente,
        String tipoDocumento,
        String numeroDocumento,
        String nombre,
        String email,
        String telefono,
        String direccion,
        BigDecimal limiteCredito,
        BigDecimal saldoDeudor,
        Boolean activo
) {}
