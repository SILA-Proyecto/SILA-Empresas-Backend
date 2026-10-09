package com.llanolat.sila.ventas.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/** Cuerpos y filas de Ventas. {@code fecha_venta} es hora de Colombia; {@code fecha_registro} va en UTC, sin zona. */
public final class VentasDtos {

    // ---------- lectura ----------
    public record Venta(
            Long idVenta, Long idCliente, String cliente, String tipoDocumento, String numeroDocumento, Long idPeriodo,
            LocalDateTime fechaVenta, String tipoVenta, LocalDate fechaVencimiento,
            BigDecimal subtotalVenta, BigDecimal totalIva, BigDecimal totalVenta, BigDecimal saldoPendiente,
            BigDecimal montoCastigado, String estadoPago, String motivoAnulacion,
            String usuarioRegistro, LocalDateTime fechaRegistro) {}

    /** {@code precio_pactado} = true cuando se vendio a un precio distinto al de lista (acuerdo con el cliente). */
    public record Linea(
            Long idDetalle, Long idProducto, String codigoSku, String producto, String unidadMedida,
            BigDecimal cantidad, BigDecimal precioUnitario, BigDecimal precioLista, Boolean precioPactado,
            BigDecimal tarifaIva, BigDecimal subtotal, BigDecimal valorIva, BigDecimal totalLinea) {}

    public record Pago(Long idPago, String metodoPago, BigDecimal monto, String referenciaPago) {}

    public record VentaDetalle(Venta venta, List<Linea> lineas, List<Pago> pagos) {}

    /** Un producto tal como se le vende a ESE cliente: con su precio pactado si lo tiene. */
    public record PrecioAplicable(
            Long idProducto, String codigoSku, String producto, String unidadMedida, BigDecimal tarifaIva,
            BigDecimal stockActual, BigDecimal precioBase, BigDecimal precioPactado, BigDecimal precioAplicable) {}

    // ---------- escritura ----------
    public record LineaRequest(
            @NotNull Long idProducto,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 10, fraction = 2) BigDecimal cantidad) {}

    public record PagoRequest(
            @NotNull @Pattern(regexp = "EFECTIVO|TRANSFERENCIA|TARJETA|CHEQUE|OTRO", message = "medio de pago invalido") String metodoPago,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 10, fraction = 2) BigDecimal monto,
            @Size(max = 60) String referencia) {}

    /** CONTADO: {@code pagos} obligatorio y debe sumar exactamente el total. CREDITO: sin pagos. */
    public record CrearVentaRequest(
            @NotNull Long idCliente,
            @NotNull @Pattern(regexp = "CONTADO|CREDITO", message = "debe ser CONTADO o CREDITO") String tipoVenta,
            @NotEmpty @Size(max = 200) List<@Valid LineaRequest> lineas,
            @Size(max = 6) List<@Valid PagoRequest> pagos) {}

    public record AnularRequest(@NotBlank @Size(min = 10, max = 255) String motivo) {}

    // ---------- precios pactados ----------
    public record PrecioCliente(
            Long idPrecio, Long idCliente, String cliente, Long idProducto, String codigoSku, String producto,
            String unidadMedida, BigDecimal precio, BigDecimal precioBase, BigDecimal diferencia, Boolean activo) {}

    public record FijarPrecioRequest(
            @NotNull Long idCliente,
            @NotNull Long idProducto,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 10, fraction = 2) BigDecimal precio) {}

    public record DesactivarPrecioRequest(@NotNull Boolean activo) {}

    private VentasDtos() {}
}
