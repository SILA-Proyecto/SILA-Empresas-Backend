package com.llanolat.sila.periodos.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * Cuerpo de PATCH /periodos/{id}/estado.
 * Cerrar: {"estado": "CERRADA"}. Reabrir: {"estado": "ABIERTA", "motivo": "..."} (motivo de 10 a 200 caracteres).
 */
public record CambiarEstadoPeriodoRequest(
        @NotNull @Pattern(regexp = "ABIERTA|CERRADA", message = "Debe ser ABIERTA o CERRADA.") String estado,
        @Size(max = 200) String motivo
) {}
