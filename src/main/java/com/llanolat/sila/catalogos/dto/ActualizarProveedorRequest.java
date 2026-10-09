package com.llanolat.sila.catalogos.dto;

import jakarta.validation.constraints.*;

public record ActualizarProveedorRequest(
        @NotBlank @Size(max = 120) String nombre,
        @Size(max = 20) String telefono
) {}
