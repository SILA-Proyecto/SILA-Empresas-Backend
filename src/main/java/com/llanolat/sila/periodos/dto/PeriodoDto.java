package com.llanolat.sila.periodos.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Una quincena con su resultado estimado (vw_estado_periodos + vw_resultado_periodo).
 * El resultado es una estimacion de gestion, no un estado contable.
 * resultado_estimado = DEVENGADO (ventas sin IVA - costo de produccion - gastos - cartera castigada).
 * caja_neta = lo cobrado - lo pagado a lecheros - gastos, en la quincena. Son dos miradas distintas.
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
        BigDecimal lechePagada,
        BigDecimal lechePorPagar,
        BigDecimal pagosProveedoresCaja,
        BigDecimal cajaNeta
) {}
