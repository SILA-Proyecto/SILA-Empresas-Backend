package com.llanolat.sila.consultas.dto;

import java.math.BigDecimal;

/** Lectura de vw_gastos_por_categoria (6 columnas). Generado desde los metadatos de la vista. */
public record GastosPorCategoriaDto(
        Long idPeriodo,
        Integer anio,
        Integer mes,
        Integer quincena,
        String categoria,
        BigDecimal totalGastos
) {}
