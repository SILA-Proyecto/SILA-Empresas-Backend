package com.llanolat.sila.reportes;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/** Margen de ventas por producto o por cliente. Ver {@link MargenRepository} para como se calcula. */
public final class Margen {

    private Margen() {}

    /**
     * Un producto o un cliente. {@code costo} y {@code margen} solo suman las lineas que tienen costo conocido;
     * {@code margenPct} = margen / ingreso de esas mismas lineas. {@code lineasSinCosto} cuenta las ventas de productos
     * que aun no tienen ningun lote de produccion.
     */
    public record Fila(Long id, String nombre, String codigoSku, BigDecimal unidades, BigDecimal ingreso, BigDecimal costo,
                       BigDecimal margen, BigDecimal margenPct, Long lineasSinCosto) {}

    public record Totales(BigDecimal ingreso, BigDecimal costo, BigDecimal margen, BigDecimal margenPct, Long lineasSinCosto) {}

    public record Reporte(String agrupar, LocalDate desde, LocalDate hasta, Totales totales, List<Fila> items) {}
}
