package com.llanolat.sila.periodos.repository;

import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.periodos.dto.PeriodoDto;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * LECTURA de periodos: une vw_estado_periodos (fechas y estado) con
 * vw_resultado_periodo (cifras). El calculo del resultado lo hace la vista.
 */
@Repository
public class PeriodoConsultaRepository {

    private static final String VISTA =
            "vw_estado_periodos e JOIN vw_cuentas_quincena r ON r.id_periodo = e.id_periodo";
    private static final String COLUMNAS = """
            e.id_periodo, e.anio, e.mes, e.quincena, e.fecha_inicio, e.fecha_fin, e.estado,
            r.ingresos_ventas, r.costo_produccion, r.gastos_operativos,
            r.cartera_castigada, r.resultado_estimado,
            r.iva_ventas, r.total_vendido, r.ventas_contado, r.ventas_credito, r.cobrado_contado, r.cobrado_abonos,
            r.total_cobrado, r.cartera_pendiente, r.leche_litros, r.leche_litros_rechazados, r.leche_comprada,
            r.leche_pagada, r.leche_por_pagar, r.pagos_proveedores_caja, r.caja_neta""";

    private static final Map<String, String> ORDEN = Map.of(
            "id_periodo", "e.id_periodo", "anio", "e.anio", "mes", "e.mes",
            "quincena", "e.quincena", "fecha_inicio", "e.fecha_inicio",
            "fecha_fin", "e.fecha_fin", "estado", "e.estado",
            "resultado_estimado", "r.resultado_estimado");

    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public PeriodoConsultaRepository(ConsultaPaginada paginada, JdbcClient jdbc) {
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    public Page<PeriodoDto> periodos(Integer anio, String estado, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (anio != null) {
            f.cuando("e.anio = :anio").param("anio", anio);
        }
        if (estado != null && !estado.isBlank()) {
            String e = estado.trim().toUpperCase();
            if (!e.equals("ABIERTA") && !e.equals("CERRADA")) {
                throw SilaException.parametroInvalido("estado debe ser ABIERTA o CERRADA.");
            }
            f.cuando("e.estado = :estado").param("estado", e);
        }
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN, "fecha_inicio,asc", "e.id_periodo");
        return paginada.consultar(COLUMNAS, VISTA, f, pag, PeriodoDto.class);
    }

    public Optional<PeriodoDto> periodo(long id) {
        return jdbc.sql("SELECT " + COLUMNAS + " FROM " + VISTA + " WHERE e.id_periodo = :id")
                   .param("id", id).query(PeriodoDto.class).optional();
    }

    /** La quincena que contiene el dia de hoy, si existe. */
    public Optional<PeriodoDto> actual() {
        return jdbc.sql("SELECT " + COLUMNAS + " FROM " + VISTA
                      + " WHERE TRUNC(SYSDATE) BETWEEN e.fecha_inicio AND e.fecha_fin")
                   .query(PeriodoDto.class).optional();
    }

    /** Anios que ya tienen quincenas creadas, de menor a mayor. */
    public List<Integer> anios() {
        return jdbc.sql("SELECT DISTINCT anio FROM vw_estado_periodos ORDER BY anio")
                   .query(Integer.class).list();
    }
}
