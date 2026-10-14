package com.llanolat.sila.catalogos.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public record StockMinimoRequest(
        @NotNull @DecimalMin("0") @Digits(integer = 8, fraction = 3) BigDecimal stockMinimo
) {}
