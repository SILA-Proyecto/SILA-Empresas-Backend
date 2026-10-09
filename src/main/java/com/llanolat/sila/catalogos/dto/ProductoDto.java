package com.llanolat.sila.catalogos.dto;

import java.math.BigDecimal;

/**
 * Fila de vw_productos. El dashboard llama `stock` a lo que la vista llama
 * `stock_actual` (Producto.stock en catalogos.models.ts): se expone con el
 * nombre del dashboard.
 */
public record ProductoDto(
        Long idProducto,
        String codigoSku,
        String nombre,
        String unidadMedida,
        BigDecimal precioBase,
        BigDecimal tarifaIva,
        BigDecimal stock,
        Boolean activo
) {}
