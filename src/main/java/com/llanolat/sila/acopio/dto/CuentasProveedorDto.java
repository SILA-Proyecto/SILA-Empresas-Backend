package com.llanolat.sila.acopio.dto;

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

/** Precios pactados, pagos y saldos de los proveedores (todas las materias primas). Montos en pesos (COP). */
public final class CuentasProveedorDto {

    /** Precio pactado de una materia prima con un proveedor; es una referencia, la compra puede traer su propio valor. */
    public record PrecioProveedor(
            Long idPrecio, Long idProveedor, String proveedor, Long idInsumo, String codigo, String insumo,
            String unidadMedida, BigDecimal precioUnitario, LocalDate vigenteDesde,
            boolean vigente, String usuarioCreacion, LocalDateTime fechaCreacion) {}

    /** vigente_desde es opcional: si falta, rige desde hoy (hora de Colombia). */
    public record FijarPrecioRequest(
            @NotNull Long idProveedor,
            @NotNull Long idInsumo,
            @NotNull @DecimalMin(value = "0.0001", message = "debe ser mayor a cero") @DecimalMax(value = "100000000", message = "no puede superar 100000000")
            @Digits(integer = 9, fraction = 4) BigDecimal precioUnitario,
            LocalDate vigenteDesde) {}

    public record PagoProveedor(
            Long idPago, Long idProveedor, String proveedor, Long idPeriodo, Long idPeriodoLiquidado,
            Integer anio, Integer mes, Integer quincena, LocalDate fechaPago, BigDecimal monto,
            String metodoPago, String referenciaPago, String estado, String motivoAnulacion,
            String usuarioRegistro, LocalDateTime fechaRegistro) {}

    /** id_periodo_liquidado = la quincena cuyas compras a credito se estan pagando. fecha_pago es opcional (hoy en Colombia). */
    public record RegistrarPagoRequest(
            @NotNull Long idProveedor,
            @NotNull Long idPeriodoLiquidado,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 12, fraction = 2) BigDecimal monto,
            @NotBlank @Pattern(regexp = "EFECTIVO|TRANSFERENCIA|CHEQUE|OTRO", message = "EFECTIVO, TRANSFERENCIA, CHEQUE u OTRO") String metodoPago,
            @Size(max = 60) String referenciaPago,
            LocalDate fechaPago) {}

    public record AnularPagoRequest(@NotBlank @Size(min = 10, max = 255) String motivo) {}

    /** Deuda total con un proveedor (todas las quincenas): solo cuentan las compras a credito. */
    public record SaldoProveedor(
            Long idProveedor, String proveedor, boolean activo,
            BigDecimal totalComprado, BigDecimal totalPagado, BigDecimal saldo,
            LocalDate ultimaCompra, LocalDate ultimoPago) {}

    /** Por quincena y proveedor: compras a credito, pagado y saldo. */
    public record ResumenPagoProveedor(
            Long idPeriodo, Integer anio, Integer mes, Integer quincena, Long idProveedor, String proveedor,
            Long numeroCompras, BigDecimal valorCompras, BigDecimal valorPagado, BigDecimal saldo) {}

    private CuentasProveedorDto() {}
}
