package com.llanolat.sila.periodos.dto;

/** Resultado de crear las quincenas de un anio: cuantas se crearon (0 si ya existian todas). */
public record CrearPeriodosResponse(int anio, int creados) {}
