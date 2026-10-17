package com.llanolat.sila.acopio.dto;

import java.math.BigDecimal;

/** Calidad de la leche por proveedor (vw_calidad_leche_proveedor) y umbrales de calidad. */
public final class ResumenesAcopioDto {

    public record CalidadProveedor(
            Long idProveedor, String proveedor, Long numeroEntregas,
            BigDecimal temperaturaPromedio, BigDecimal acidezPromedio,
            Long entregasRechazadas, BigDecimal porcentajeRechazo) {}

    /** Limites vigentes: arriba de ellos la entrega se RECHAZA. */
    public record Umbrales(BigDecimal temperaturaMax, BigDecimal acidezMax) {}

    private ResumenesAcopioDto() {}
}
