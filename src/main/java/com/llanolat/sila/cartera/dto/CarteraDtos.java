package com.llanolat.sila.cartera.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/** Cartera: lo que los clientes deben y sus abonos. */
public final class CarteraDtos {

    /** estado_credito: AL_DIA | VIGENTE | EN_MORA | EXCEDIDO (lo calcula la base). */
    public record ClienteCartera(
            Long idCliente, String cliente, String telefono, BigDecimal limiteCredito, BigDecimal saldoDeudor,
            BigDecimal cupoDisponible, Integer diasMora, String estadoCredito) {}

    public record VentaPendiente(
            Long idVenta, java.time.LocalDateTime fechaVenta, LocalDate fechaVencimiento, BigDecimal totalVenta,
            BigDecimal saldoPendiente, Integer diasMora) {}

    public record Abono(
            Long idAbono, Long idRecibo, Long idCliente, String cliente, Long idVenta, LocalDate fechaAbono,
            BigDecimal monto, String metodoPago, String referenciaPago, String usuarioRegistro) {}

    public record Resumen(BigDecimal totalCartera, Long clientesConDeuda, Long clientesEnMora, BigDecimal carteraVencida) {}

    /** El recibo de un abono: como se repartio (de la venta mas antigua a la mas nueva) y lo que queda debiendo. */
    public record Recibo(Long idRecibo, BigDecimal saldoRestante, List<Abono> abonos) {}

    public record CastigoResultado(Long idCliente, BigDecimal montoCastigado) {}

    public record AbonoRequest(
            @NotNull Long idCliente,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 10, fraction = 2) BigDecimal monto,
            @NotNull @Pattern(regexp = "EFECTIVO|TRANSFERENCIA|TARJETA|CHEQUE|OTRO", message = "medio de pago invalido") String metodoPago,
            @Size(max = 60) String referencia) {}

    public record CastigoRequest(
            @NotNull Long idCliente,
            @NotBlank @Size(min = 10, max = 255) String motivo) {}

    private CarteraDtos() {}
}
