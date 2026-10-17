package com.llanolat.sila.acopio.repository;

import com.llanolat.sila.acopio.dto.ResumenesAcopioDto.CalidadProveedor;
import com.llanolat.sila.acopio.dto.ResumenesAcopioDto.Umbrales;
import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import java.math.BigDecimal;
import java.util.Map;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Acopio de leche: lectura de la calidad por proveedor y de los umbrales. La entrega se registra como compra de LECHE (/insumos/compras). */
@Repository
public class AcopioRepository {

    private static final Map<String, String> ORDEN_CALIDAD = Map.of(
            "id_proveedor", "id_proveedor", "proveedor", "proveedor", "numero_entregas", "numero_entregas",
            "porcentaje_rechazo", "porcentaje_rechazo", "entregas_rechazadas", "entregas_rechazadas");

    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public AcopioRepository(ConsultaPaginada paginada, JdbcClient jdbc) {
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    public Page<CalidadProveedor> calidad(Integer page, Integer size, String sort) {
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_CALIDAD, "proveedor,asc", "id_proveedor");
        return paginada.consultar("id_proveedor, proveedor, numero_entregas, temperatura_promedio, acidez_promedio, "
                + "entregas_rechazadas, porcentaje_rechazo", "vw_calidad_leche_proveedor", new Filtro(), pag, CalidadProveedor.class);
    }

    public Umbrales umbrales() {
        Map<String, BigDecimal> v = new java.util.HashMap<>();
        jdbc.sql("SELECT clave, valor_numero FROM vw_umbrales_operacion").query((rs, n) -> {
            v.put(rs.getString("clave"), rs.getBigDecimal("valor_numero"));
            return null;
        }).list();
        return new Umbrales(v.get("TEMP_MAX_LECHE_C"), v.get("ACIDEZ_MAX_DORNIC"));
    }
}
