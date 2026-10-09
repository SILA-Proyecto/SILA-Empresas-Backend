package com.llanolat.sila.catalogos.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

/**
 * Las validaciones aqui son de FORMA, para fallar rapido y barato.
 * Las reglas de negocio las valida la base de datos de todas maneras:
 * esto no las reemplaza, solo evita un viaje innecesario.
 */
public record CrearClienteRequest(

        @NotBlank @Pattern(regexp = "CC|NIT|CE|PASAPORTE|TI",
                message = "debe ser CC, NIT, CE, PASAPORTE o TI")
        String tipoDocumento,

        @NotBlank @Pattern(regexp = "^[A-Za-z0-9-]{5,20}$",
                message = "5 a 20 letras, numeros o guion")
        String numeroDocumento,

        @NotBlank @Size(max = 120)
        String nombre,

        @NotBlank @Email @Size(max = 150)
        String email,

        @Size(max = 20)
        String telefono,

        @Size(max = 255)
        String direccion,

        /** Opcional: OPERATIVO no lo envia y el cliente nace con cupo 0 (SUPUESTO C-04). Mayor que 0 exige ADMIN. */
        @DecimalMin("0") @Digits(integer = 10, fraction = 2)
        BigDecimal limiteCredito
) {}
