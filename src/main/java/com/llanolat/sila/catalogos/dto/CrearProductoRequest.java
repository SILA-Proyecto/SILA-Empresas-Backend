package com.llanolat.sila.catalogos.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public record CrearProductoRequest(
        @NotBlank @Size(max = 20) String codigoSku,
        @NotBlank @Size(max = 100) String nombre,
        @NotBlank @Pattern(regexp = "KG|GR|LT|ML|UND|PAQ",
                message = "debe ser KG, GR, LT, ML, UND o PAQ") String unidadMedida,
        @NotNull @DecimalMin("0") @Digits(integer = 8, fraction = 2) BigDecimal precioBase,
        /** Confirmar producto por producto con contabilidad: varios lacteos
            estan excluidos o exentos y otros no. */
        @NotNull @DecimalMin("0") @DecimalMax("100") @Digits(integer = 3, fraction = 2)
        BigDecimal tarifaIva
) {}
