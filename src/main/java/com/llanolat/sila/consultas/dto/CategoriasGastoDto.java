package com.llanolat.sila.consultas.dto;


/** Lectura de vw_categorias_gasto (3 columnas). Generado desde los metadatos de la vista. */
public record CategoriasGastoDto(
        Long idCategoria,
        String nombre,
        Boolean activo
) {}
