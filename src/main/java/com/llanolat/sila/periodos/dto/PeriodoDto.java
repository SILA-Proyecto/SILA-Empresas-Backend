package com.llanolat.sila.periodos.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Una quincena con su resultado estimado (vw_estado_periodos + vw_resultado_periodo).
 * El resultado es una estimacion de gestion, no un estado contable.
 * resultado_estimado = DEVENGADO (ventas sin IVA - costo de produccion - gastos - cartera castigada).
 * caja_neta = lo cobrado - lo pagado a proveedores - gastos - compras de contado, en la quincena. Son dos miradas distintas.
 * compras_credito = lo comprado a credito en la quincena; pagado_proveedores = lo que se pago DE ESA quincena (aunque se haya
 * pagado despues); por_pagar_proveedores = la diferencia; pagos_proveedores_caja = lo que salio de caja en la quincena.
 */
public record PeriodoDto(
        Long idPeriodo,
        Integer anio,
        Integer mes,
        Integer quincena,
        LocalDate fechaInicio,
        LocalDate fechaFin,
        String estado,
        BigDecimal ingresosVentas,
        BigDecimal costoProduccion,
        BigDecimal gastosOperativos,
        BigDecimal carteraCastigada,
        BigDecimal resultadoEstimado,
        // ---- cuentas de la quincena (vw_cuentas_quincena) ----
        BigDecimal ivaVentas,
        BigDecimal totalVendido,
        BigDecimal ventasContado,
        BigDecimal ventasCredito,
        BigDecimal cobradoContado,
        BigDecimal cobradoAbonos,
        BigDecimal totalCobrado,
        BigDecimal carteraPendiente,
        BigDecimal lecheLitros,
        BigDecimal lecheLitrosRechazados,
        BigDecimal lecheComprada,
        BigDecimal comprasMateriasPrimas,
        BigDecimal comprasContado,
        BigDecimal comprasCredito,
        BigDecimal pagadoProveedores,
        BigDecimal porPagarProveedores,
        BigDecimal pagosProveedoresCaja,
        BigDecimal cajaNeta
) {}
