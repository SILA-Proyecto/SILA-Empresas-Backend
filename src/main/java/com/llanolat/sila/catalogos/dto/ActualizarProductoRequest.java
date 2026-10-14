package com.llanolat.sila.catalogos.dto;

import jakarta.validation.constraints.*;

/** Edicion de producto por OPERATIVO (SUPUESTO C-07): solo nombre y unidad. */
public record ActualizarProductoRequest(
        @NotBlank @Size(max = 100) String nombre,
        @NotBlank @Pattern(regexp = "KG|GR|LT|ML|UND|PAQ",
                message = "debe ser KG, GR, LT, ML, UND o PAQ") String unidadMedida,
        /** Opcional: null = no cambia. Alerta de reposicion (0 = sin alerta). */
        @DecimalMin("0") @Digits(integer = 8, fraction = 3) java.math.BigDecimal stockMinimo
) {}
