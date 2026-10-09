package com.llanolat.sila.catalogos.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public record ActualizarPrecioRequest(
        @NotNull @DecimalMin("0") @Digits(integer = 8, fraction = 2) BigDecimal precioBase,
        @NotNull @DecimalMin("0") @DecimalMax("100") @Digits(integer = 3, fraction = 2)
        BigDecimal tarifaIva
) {}
