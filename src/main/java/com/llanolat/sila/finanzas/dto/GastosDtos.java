package com.llanolat.sila.finanzas.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/** Gastos operativos (vw_gastos). {@code estado}: VIGENTE o ANULADO. Fechas de registro y anulacion en UTC, sin zona. */
public final class GastosDtos {

    public record Gasto(
            Long idGasto,
            Long idPeriodo,
            Integer anio,
            Integer mes,
            Integer quincena,
            Long idCategoria,
            String categoria,
            LocalDate fechaGasto,
            String concepto,
            BigDecimal monto,
            String usuarioRegistro,
            LocalDateTime fechaRegistro,
            String estado,
            String motivoAnulacion,
            String usuarioAnulacion,
            LocalDateTime fechaAnulacion
    ) {}

    /** Validaciones de FORMA; la categoria activa, el periodo abierto y el monto los verifica Oracle. {@code fecha_gasto} es opcional (hoy en Colombia). */
    public record RegistrarGastoRequest(
            @NotNull Long idCategoria,
            @NotBlank @Size(min = 3, max = 255) String concepto,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 10, fraction = 2) BigDecimal monto,
            LocalDate fechaGasto
    ) {}

    public record AnularGastoRequest(@NotBlank @Size(min = 10, max = 255) String motivo) {}

    /** Total de los gastos VIGENTES del filtro aplicado (periodo, categoria, fechas), para el encabezado de la pantalla. */
    public record ResumenGastos(BigDecimal total, Long cantidad) {}

    private GastosDtos() {}
}
