package com.llanolat.sila.catalogos.dto;

import jakarta.validation.constraints.*;

public record CrearProveedorRequest(
        @NotBlank @Pattern(regexp = "CC|NIT|CE|PASAPORTE|TI") String tipoDocumento,
        @NotBlank @Pattern(regexp = "^[A-Za-z0-9-]{5,20}$",
                message = "5 a 20 letras, numeros o guion") String numeroDocumento,
        @NotBlank @Size(max = 120) String nombre,
        @Size(max = 20) String telefono,
        @NotBlank @Pattern(regexp = "LECHERO|INSUMOS",
                message = "debe ser LECHERO o INSUMOS") String tipoProveedor
) {}
