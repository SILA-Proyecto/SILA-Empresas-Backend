package com.llanolat.sila.produccion.repository;

import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.SilaTemplate;
import com.llanolat.sila.infra.Texto;
import com.llanolat.sila.produccion.dto.ProduccionDtos.Ajuste;
import com.llanolat.sila.produccion.dto.ProduccionDtos.AlertaCaducidad;
import com.llanolat.sila.produccion.dto.ProduccionDtos.ItemInventario;
import com.llanolat.sila.produccion.dto.ProduccionDtos.Lote;
import com.llanolat.sila.produccion.dto.ProduccionDtos.ResumenInventario;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDate;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Produccion e inventario: escritura por pkg_produccion (la base exige el rol) y lectura por vistas. */
@Repository
public class ProduccionRepository {

    private static final String COLUMNAS_LOTE = """
            id_lote, codigo_lote, id_producto, producto, codigo_sku, unidad_medida, fecha_produccion,
            litros_leche_usados, cantidad_obtenida, porcentaje_rendimiento, costo_total, costo_unitario,
            fecha_vencimiento, dias_restantes, nivel_alerta, usuario_registro, fecha_registro""";
    private static final String COLUMNAS_AJUSTE = """
            id_ajuste, id_producto, producto, codigo_sku, unidad_medida, tipo_ajuste, cantidad_delta,
            observacion, usuario_registro, fecha_registro""";

    private static final Map<String, String> ORDEN_LOTES = Map.of(
            "id_lote", "id_lote", "codigo_lote", "codigo_lote", "producto", "producto",
            "fecha_produccion", "fecha_produccion", "fecha_vencimiento", "fecha_vencimiento",
            "cantidad_obtenida", "cantidad_obtenida", "porcentaje_rendimiento", "porcentaje_rendimiento",
            "costo_total", "costo_total", "dias_restantes", "dias_restantes");
    private static final Map<String, String> ORDEN_AJUSTES = Map.of(
            "id_ajuste", "id_ajuste", "fecha_registro", "fecha_registro", "producto", "producto",
            "tipo_ajuste", "tipo_ajuste", "cantidad_delta", "cantidad_delta");
    private static final Map<String, String> ORDEN_INVENTARIO = Map.of(
            "id_producto", "id_producto", "codigo_sku", "codigo_sku", "producto", "producto",
            "stock_actual", "stock_actual", "precio_base", "precio_base", "valor_venta_inventario", "valor_venta_inventario");
    private static final Map<String, String> ORDEN_ALERTAS = Map.of(
            "dias_restantes", "dias_restantes", "fecha_vencimiento", "fecha_vencimiento",
            "producto", "producto", "codigo_lote", "codigo_lote");

    private final SilaTemplate sila;
    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public ProduccionRepository(SilaTemplate sila, ConsultaPaginada paginada, JdbcClient jdbc) {
        this.sila = sila;
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    // ---------- escritura ----------

    /** OPERATIVO. Suma la cantidad obtenida al stock del producto; el codigo del lote lo genera la base. */
    public long registrarLote(long idProducto, BigDecimal litros, BigDecimal cantidad, BigDecimal costoPorLitro,
                              LocalDate fechaProduccion, LocalDate fechaVencimiento) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_produccion.sp_registrar_lote(?,?,?,?,?,?,?,?)}")) {
                s.setLong(1, idProducto);
                s.setBigDecimal(2, litros);
                s.setBigDecimal(3, cantidad);
                s.setBigDecimal(4, costoPorLitro);
                s.setDate(5, java.sql.Date.valueOf(fechaProduccion));
                if (fechaVencimiento == null) s.setNull(6, Types.DATE); else s.setDate(6, java.sql.Date.valueOf(fechaVencimiento));
                s.registerOutParameter(7, Types.NUMERIC);
                s.registerOutParameter(8, Types.VARCHAR);
                s.execute();
                return s.getLong(7);
            }
        });
    }

    /** MERMA, DANO, VENCIMIENTO y MUESTRA: OPERATIVO. INGRESO_INICIAL y las correcciones: ADMIN (lo exige la base). */
    public long registrarAjuste(long idProducto, String tipo, BigDecimal cantidad, String observacion) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_produccion.sp_registrar_ajuste(?,?,?,?,?)}")) {
                s.setLong(1, idProducto);
                s.setString(2, tipo);
                s.setBigDecimal(3, cantidad);
                s.setString(4, observacion);
                s.registerOutParameter(5, Types.NUMERIC);
                s.execute();
                return s.getLong(5);
            }
        });
    }

    // ---------- lectura ----------

    public Optional<Lote> lote(long id) {
        return jdbc.sql("SELECT " + COLUMNAS_LOTE + " FROM vw_lotes WHERE id_lote = :id")
                   .param("id", id).query(Lote.class).optional();
    }

    public Page<Lote> lotes(String texto, Long idProducto, LocalDate desde, LocalDate hasta,
                            Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (texto != null && !texto.isBlank()) {
            f.cuando("(UPPER(codigo_lote) LIKE UPPER('%' || :q || '%') OR " + Texto.comoSinAcentos("producto") + ")")
             .param("q", texto.trim()).param("conAcento", Texto.ACENTOS).param("sinAcento", Texto.SIN_ACENTOS);
        }
        if (idProducto != null) f.cuando("id_producto = :idProducto").param("idProducto", idProducto);
        if (desde != null) f.cuando("fecha_produccion >= :f_desde").param("f_desde", desde);
        if (hasta != null) f.cuando("fecha_produccion <= :f_hasta").param("f_hasta", hasta);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_LOTES, "fecha_produccion,desc", "id_lote");
        return paginada.consultar(COLUMNAS_LOTE, "vw_lotes", f, pag, Lote.class);
    }

    public Optional<Ajuste> ajuste(long id) {
        return jdbc.sql("SELECT " + COLUMNAS_AJUSTE + " FROM vw_ajustes_inventario WHERE id_ajuste = :id")
                   .param("id", id).query(Ajuste.class).optional();
    }

    public Page<Ajuste> ajustes(Long idProducto, String tipo, LocalDate desde, LocalDate hasta,
                                Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (idProducto != null) f.cuando("id_producto = :idProducto").param("idProducto", idProducto);
        if (tipo != null && !tipo.isBlank()) f.cuando("tipo_ajuste = :tipo").param("tipo", tipo.trim().toUpperCase());
        // fecha_registro es UTC; el dia de Colombia empieza 5 h despues (el filtro de dias se interpreta en UTC, como en auditoria)
        if (desde != null) f.cuando("fecha_registro >= :f_desde").param("f_desde", desde.atStartOfDay());
        if (hasta != null) f.cuando("fecha_registro < :f_hasta").param("f_hasta", hasta.plusDays(1).atStartOfDay());
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_AJUSTES, "fecha_registro,desc", "id_ajuste");
        return paginada.consultar(COLUMNAS_AJUSTE, "vw_ajustes_inventario", f, pag, Ajuste.class);
    }

    public Page<ItemInventario> inventario(String texto, boolean soloConStock, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (texto != null && !texto.isBlank()) {
            f.cuando("(" + Texto.comoSinAcentos("producto") + " OR UPPER(codigo_sku) LIKE UPPER('%' || :q || '%'))")
             .param("q", texto.trim()).param("conAcento", Texto.ACENTOS).param("sinAcento", Texto.SIN_ACENTOS);
        }
        if (soloConStock) f.cuando("stock_actual > 0");
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_INVENTARIO, "producto,asc", "id_producto");
        return paginada.consultar("id_producto, codigo_sku, producto, unidad_medida, stock_actual, precio_base, valor_venta_inventario",
                "vw_inventario_valorizado", f, pag, ItemInventario.class);
    }

    public ResumenInventario resumenInventario() {
        return jdbc.sql("""
                SELECT COUNT(*) AS total_productos,
                       NVL(SUM(CASE WHEN stock_actual = 0 THEN 1 ELSE 0 END), 0) AS productos_sin_stock,
                       NVL(SUM(valor_venta_inventario), 0) AS valor_total
                  FROM vw_inventario_valorizado""").query(ResumenInventario.class).single();
    }

    /** Lotes con dias_restantes entre los limites; los vencidos hace mas de {@code diasMinimos} dejan de salir. */
    public Page<AlertaCaducidad> alertas(int diasMinimos, int diasMaximos, Integer page, Integer size, String sort) {
        Filtro f = new Filtro().cuando("dias_restantes BETWEEN :diasMin AND :diasMax")
                .param("diasMin", diasMinimos).param("diasMax", diasMaximos);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_ALERTAS, "dias_restantes,asc", "id_lote");
        return paginada.consultar("id_lote, codigo_lote, producto, cantidad_obtenida AS cantidad_producida, "
                + "fecha_vencimiento, dias_restantes, nivel_alerta", "vw_lotes", f, pag, AlertaCaducidad.class);
    }
}
