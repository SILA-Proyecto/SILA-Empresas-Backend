package com.llanolat.sila.acopio.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Validaciones de FORMA (las de negocio las hace Oracle). {@code fecha} es opcional: si falta se usa
 * el dia de hoy en hora de Colombia.
 */
public record RegistrarRecepcionRequest(
        @NotNull Long idProveedor,
        @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 8, fraction = 2) BigDecimal litros,
        @NotNull @DecimalMin("-5") @DecimalMax("60") @Digits(integer = 3, fraction = 2) BigDecimal temperatura,
        @NotNull @DecimalMin("0") @DecimalMax("40") @Digits(integer = 3, fraction = 2) BigDecimal acidez,
        LocalDate fecha
) {}
