package com.llanolat.sila.catalogos.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

/**
 * El dashboard manda el mismo cuerpo (ClienteGuardar) al crear y al editar.
 * El tipo y el numero de documento son la identidad del cliente y no se
 * editan: si llegan, se ignoran.
 */
public record ActualizarClienteRequest(
        @NotBlank @Size(max = 120) String nombre,
        @NotBlank @Email @Size(max = 150) String email,
        @Size(max = 20) String telefono,
        @Size(max = 255) String direccion,

        /** Opcional. Si trae un valor distinto al actual se cambia aparte, y eso exige ADMIN (ORA-20008). */
        @DecimalMin("0") @Digits(integer = 10, fraction = 2)
        BigDecimal limiteCredito
) {}
