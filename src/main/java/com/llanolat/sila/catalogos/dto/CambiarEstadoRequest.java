package com.llanolat.sila.catalogos.dto;

import jakarta.validation.constraints.NotNull;

/** Cuerpo de PATCH /{id}/estado: {"activo": false}. */
public record CambiarEstadoRequest(@NotNull Boolean activo) {}
