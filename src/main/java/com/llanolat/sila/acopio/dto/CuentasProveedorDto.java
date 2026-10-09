package com.llanolat.sila.acopio.dto;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/** Precios por litro, pagos y saldos de los lecheros. Montos en pesos (COP). */
public final class CuentasProveedorDto {

    public record PrecioProveedor(
            Long idPrecio, Long idProveedor, String proveedor, BigDecimal precioLitro, LocalDate vigenteDesde,
            boolean vigente, String usuarioCreacion, LocalDateTime fechaCreacion) {}

    /** vigente_desde es opcional: si falta, rige desde hoy (hora de Colombia). */
    public record FijarPrecioRequest(
            @NotNull Long idProveedor,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @DecimalMax(value = "20000", message = "no puede superar 20000")
            @Digits(integer = 5, fraction = 2) BigDecimal precioLitro,
            LocalDate vigenteDesde) {}

    public record PagoProveedor(
            Long idPago, Long idProveedor, String proveedor, Long idPeriodo, Long idPeriodoLiquidado,
            Integer anio, Integer mes, Integer quincena, LocalDate fechaPago, BigDecimal monto,
            String metodoPago, String referenciaPago, String estado, String motivoAnulacion,
            String usuarioRegistro, LocalDateTime fechaRegistro) {}

    /** id_periodo_liquidado = la quincena cuya leche se esta pagando. fecha_pago es opcional (hoy en Colombia). */
    public record RegistrarPagoRequest(
            @NotNull Long idProveedor,
            @NotNull Long idPeriodoLiquidado,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 12, fraction = 2) BigDecimal monto,
            @NotBlank @Pattern(regexp = "EFECTIVO|TRANSFERENCIA|CHEQUE|OTRO", message = "EFECTIVO, TRANSFERENCIA, CHEQUE u OTRO") String metodoPago,
            @Size(max = 60) String referenciaPago,
            LocalDate fechaPago) {}

    public record AnularPagoRequest(@NotBlank @Size(min = 10, max = 255) String motivo) {}

    /** Deuda total con un lechero (todas las quincenas). */
    public record SaldoProveedor(
            Long idProveedor, String proveedor, boolean activo, BigDecimal precioVigente,
            BigDecimal litrosAprobados, BigDecimal totalComprado, BigDecimal totalPagado, BigDecimal saldo,
            LocalDate ultimaEntrega, LocalDate ultimoPago) {}

    private CuentasProveedorDto() {}
}
