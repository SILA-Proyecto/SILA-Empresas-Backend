package com.llanolat.sila.catalogos.dto;

import jakarta.validation.constraints.*;

public record CrearCategoriaGastoRequest(
        @NotBlank @Size(max = 60) String nombre
) {}
