package com.llanolat.sila.acopio.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.math.BigDecimal;

/** Resumenes de acopio (vistas vw_calidad_leche_proveedor y vw_resumen_pago_lecheros) y umbrales de calidad. */
public final class ResumenesAcopioDto {

    public record CalidadProveedor(
            Long idProveedor, String proveedor, Long numeroEntregas,
            BigDecimal temperaturaPromedio, BigDecimal acidezPromedio,
            Long entregasRechazadas, BigDecimal porcentajeRechazo) {}

    public record PagoLechero(
            Long idPeriodo, Integer anio, Integer mes, Integer quincena,
            Long idProveedor, String proveedor,
            @JsonProperty("litros_a_pagar") BigDecimal litrosAPagar, BigDecimal litrosRechazados,
            BigDecimal valorLeche, BigDecimal valorPagado, BigDecimal saldo, BigDecimal precioPromedio) {}

    /** Limites vigentes: arriba de ellos la entrega se RECHAZA. */
    public record Umbrales(BigDecimal temperaturaMax, BigDecimal acidezMax) {}

    private ResumenesAcopioDto() {}
}
