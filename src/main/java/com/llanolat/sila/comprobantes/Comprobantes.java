package com.llanolat.sila.comprobantes;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/**
 * Comprobantes: vista unificada (solo lectura) de los movimientos de plata, desde vw_comprobantes.
 * No son facturas DIAN: son el documento interno de cada movimiento. {@code numero} = 'VENTA #123'.
 * {@code sentido}: INGRESO | EGRESO. {@code estado}: VIGENTE | ANULADO.
 */
public final class Comprobantes {

    public record Comprobante(
            String tipo, Long idDocumento, String numero, String sentido, Boolean afectaCaja,
            LocalDate fecha, BigDecimal monto,
            Long idTercero, String terceroTipo, String tercero,
            String descripcion, String metodoPago, String referencia,
            String estado, String motivoAnulacion, Long idPeriodo, String usuarioRegistro) {}

    /** Ingresos y egresos VIGENTES que mueven caja, con los filtros de la lista. */
    public record Resumen(BigDecimal ingresos, BigDecimal egresos, BigDecimal neto, Integer cantidad) {}

    public record Linea(String concepto, BigDecimal cantidad, BigDecimal valorUnitario, BigDecimal valor) {}

    public record Pago(String metodoPago, BigDecimal monto, String referencia) {}

    /** {@code subtotal} e {@code iva} solo en VENTA (null en los demas). */
    public record Detalle(Comprobante comprobante, List<Linea> lineas, List<Pago> pagos, BigDecimal subtotal, BigDecimal iva) {}

    private Comprobantes() {}
}
