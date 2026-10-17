package com.llanolat.sila.insumos.repository;

import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.SilaTemplate;
import com.llanolat.sila.infra.Texto;
import com.llanolat.sila.insumos.dto.InsumosDtos.*;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Insumos, recetas, compras y ajustes: escritura por pkg_insumos (la base exige el rol) y lectura por vistas. */
@Repository
public class InsumoRepository {

    private static final String COLUMNAS_INSUMO = """
            id_insumo, codigo, nombre, unidad_medida, costo_promedio, stock_actual, stock_minimo, valor_inventario,
            bajo_minimo, productos_que_lo_usan, activo, fecha_creacion, usuario_creacion, requiere_calidad""";
    private static final String COLUMNAS_COMPRA = """
            id_compra, id_insumo, codigo, insumo, unidad_medida, id_proveedor, proveedor, id_periodo, fecha, cantidad,
            valor_total, costo_unitario, referencia, estado, motivo_anulacion, usuario_registro, fecha_registro,
            contado, comprado_en, estado_calidad, temperatura, acidez, motivo_rechazo, requiere_calidad""";
    private static final String COLUMNAS_AJUSTE = """
            id_ajuste, id_insumo, codigo, insumo, unidad_medida, tipo_ajuste, cantidad_delta, valor_delta,
            observacion, usuario_registro, fecha_registro""";
    private static final String COLUMNAS_LINEA = """
            id_insumo, codigo_insumo, insumo, unidad_insumo, cantidad_por_unidad, costo_unitario_insumo,
            valor_por_unidad, stock_insumo, insumo_activo""";
    private static final String COLUMNAS_CONSUMO = """
            id_consumo, id_lote, codigo_lote, id_insumo, codigo, insumo, unidad_medida, cantidad, costo_unitario, valor""";

    private static final Map<String, String> ORDEN_INSUMOS = Map.of(
            "id_insumo", "id_insumo", "codigo", "codigo", "nombre", "nombre", "stock_actual", "stock_actual",
            "costo_promedio", "costo_promedio", "valor_inventario", "valor_inventario");
    private static final Map<String, String> ORDEN_COMPRAS = Map.of(
            "id_compra", "id_compra", "fecha", "fecha", "insumo", "insumo", "proveedor", "proveedor",
            "valor_total", "valor_total", "cantidad", "cantidad", "estado", "estado",
            "temperatura", "temperatura", "acidez", "acidez");
    private static final Map<String, String> ORDEN_AJUSTES = Map.of(
            "id_ajuste", "id_ajuste", "fecha_registro", "fecha_registro", "insumo", "insumo",
            "tipo_ajuste", "tipo_ajuste", "cantidad_delta", "cantidad_delta");

    private final SilaTemplate sila;
    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public InsumoRepository(SilaTemplate sila, ConsultaPaginada paginada, JdbcClient jdbc) {
        this.sila = sila;
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    // ---------- escritura ----------

    public long crear(CrearInsumoRequest r) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_insumos.sp_crear_insumo(?,?,?,?,?)}")) {
                s.setString(1, r.codigo());
                s.setString(2, r.nombre());
                s.setString(3, r.unidadMedida());
                s.setBigDecimal(4, r.stockMinimo());
                s.registerOutParameter(5, Types.NUMERIC);
                s.execute();
                return s.getLong(5);
            }
        });
    }

    public void actualizar(long id, ActualizarInsumoRequest r) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_insumos.sp_actualizar_insumo(?,?,?,?)}")) {
                s.setLong(1, id);
                s.setString(2, r.nombre());
                s.setString(3, r.unidadMedida());
                s.setBigDecimal(4, r.stockMinimo());
                s.execute();
                return null;
            }
        });
    }

    public void cambiarEstado(long id, boolean activo) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_insumos.sp_cambiar_estado(?,?)}")) {
                s.setLong(1, id);
                s.setInt(2, activo ? 1 : 0);
                s.execute();
                return null;
            }
        });
    }

    /** La base decide el rol (OPERATIVO para la leche, ADMIN para el resto) y la calidad; un rechazo de leche NO es un error. */
    public long registrarCompra(CrearCompraRequest r, LocalDate fecha) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_insumos.sp_registrar_compra(?,?,?,?,?,?,?,?,?,?,?,?)}")) {
                s.setLong(1, r.idInsumo());
                if (r.idProveedor() == null) s.setNull(2, Types.NUMERIC); else s.setLong(2, r.idProveedor());
                s.setBigDecimal(3, r.cantidad());
                if (r.valorTotal() == null) s.setNull(4, Types.NUMERIC); else s.setBigDecimal(4, r.valorTotal());
                s.setString(5, r.referencia());
                s.setDate(6, java.sql.Date.valueOf(fecha));
                if (r.contado() == null) s.setNull(7, Types.NUMERIC); else s.setInt(7, r.contado() ? 1 : 0);
                s.setString(8, r.compradoEn());
                if (r.temperatura() == null) s.setNull(9, Types.NUMERIC); else s.setBigDecimal(9, r.temperatura());
                if (r.acidez() == null) s.setNull(10, Types.NUMERIC); else s.setBigDecimal(10, r.acidez());
                s.registerOutParameter(11, Types.NUMERIC);
                s.registerOutParameter(12, Types.VARCHAR);
                s.execute();
                return s.getLong(11);
            }
        });
    }

    public void anularCompra(long id, String motivo) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_insumos.sp_anular_compra(?,?)}")) {
                s.setLong(1, id);
                s.setString(2, motivo);
                s.execute();
                return null;
            }
        });
    }

    public long registrarAjuste(CrearAjusteInsumoRequest r) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_insumos.sp_registrar_ajuste(?,?,?,?,?)}")) {
                s.setLong(1, r.idInsumo());
                s.setString(2, r.tipoAjuste());
                s.setBigDecimal(3, r.cantidad());
                s.setString(4, r.observacion());
                s.registerOutParameter(5, Types.NUMERIC);
                s.execute();
                return s.getLong(5);
            }
        });
    }

    /** ADMIN. {@code lineasJson}: [{"id_insumo":1,"cantidad":0.25}]; reemplaza la receta completa. */
    public void definirReceta(long idProducto, String lineasJson) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_insumos.sp_definir_receta(?,?)}")) {
                s.setLong(1, idProducto);
                s.setString(2, lineasJson);
                s.execute();
                return null;
            }
        });
    }

    // ---------- lectura ----------

    public Optional<Insumo> insumo(long id) {
        return jdbc.sql("SELECT " + COLUMNAS_INSUMO + " FROM vw_insumos WHERE id_insumo = :id")
                   .param("id", id).query(Insumo.class).optional();
    }

    public Page<Insumo> insumos(String texto, Boolean activo, boolean soloBajoMinimo, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (texto != null && !texto.isBlank()) {
            f.cuando("(" + Texto.comoSinAcentos("nombre") + " OR UPPER(codigo) LIKE UPPER('%' || :q || '%'))")
             .param("q", texto.trim()).param("conAcento", Texto.ACENTOS).param("sinAcento", Texto.SIN_ACENTOS);
        }
        if (activo != null) f.cuando("activo = :activo").param("activo", activo ? 1 : 0);
        if (soloBajoMinimo) f.cuando("bajo_minimo = 1");
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_INSUMOS, "nombre,asc", "id_insumo");
        return paginada.consultar(COLUMNAS_INSUMO, "vw_insumos", f, pag, Insumo.class);
    }

    public ResumenInsumos resumen() {
        return jdbc.sql("""
                SELECT COUNT(*) AS total_insumos, NVL(SUM(bajo_minimo), 0) AS bajo_minimo,
                       NVL(SUM(valor_inventario), 0) AS valor_total
                  FROM vw_insumos WHERE activo = 1""").query(ResumenInsumos.class).single();
    }

    public Optional<Compra> compra(long id) {
        return jdbc.sql("SELECT " + COLUMNAS_COMPRA + " FROM vw_compras_insumo WHERE id_compra = :id")
                   .param("id", id).query(Compra.class).optional();
    }

    public Page<Compra> compras(Long idInsumo, Long idProveedor, String estado, String estadoCalidad, Long idPeriodo,
                                Boolean contado, LocalDate desde, LocalDate hasta,
                                Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (estadoCalidad != null && !estadoCalidad.isBlank()) f.cuando("estado_calidad = :estadoCalidad").param("estadoCalidad", estadoCalidad.trim().toUpperCase());
        if (idPeriodo != null) f.cuando("id_periodo = :idPeriodo").param("idPeriodo", idPeriodo);
        if (contado != null) f.cuando("contado = :contado").param("contado", contado ? 1 : 0);
        if (idInsumo != null) f.cuando("id_insumo = :idInsumo").param("idInsumo", idInsumo);
        if (idProveedor != null) f.cuando("id_proveedor = :idProveedor").param("idProveedor", idProveedor);
        if (estado != null && !estado.isBlank()) f.cuando("estado = :estado").param("estado", estado.trim().toUpperCase());
        if (desde != null) f.cuando("fecha >= :f_desde").param("f_desde", desde);
        if (hasta != null) f.cuando("fecha <= :f_hasta").param("f_hasta", hasta);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_COMPRAS, "fecha,desc", "id_compra");
        return paginada.consultar(COLUMNAS_COMPRA, "vw_compras_insumo", f, pag, Compra.class);
    }

    public Optional<AjusteInsumo> ajuste(long id) {
        return jdbc.sql("SELECT " + COLUMNAS_AJUSTE + " FROM vw_ajustes_insumo WHERE id_ajuste = :id")
                   .param("id", id).query(AjusteInsumo.class).optional();
    }

    public Page<AjusteInsumo> ajustes(Long idInsumo, String tipo, LocalDate desde, LocalDate hasta,
                                      Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (idInsumo != null) f.cuando("id_insumo = :idInsumo").param("idInsumo", idInsumo);
        if (tipo != null && !tipo.isBlank()) f.cuando("tipo_ajuste = :tipo").param("tipo", tipo.trim().toUpperCase());
        // fecha_registro es UTC (igual que en los ajustes de productos)
        if (desde != null) f.cuando("fecha_registro >= :f_desde").param("f_desde", desde.atStartOfDay());
        if (hasta != null) f.cuando("fecha_registro < :f_hasta").param("f_hasta", hasta.plusDays(1).atStartOfDay());
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_AJUSTES, "fecha_registro,desc", "id_ajuste");
        return paginada.consultar(COLUMNAS_AJUSTE, "vw_ajustes_insumo", f, pag, AjusteInsumo.class);
    }

    public List<ConsumoLote> consumosDelLote(long idLote) {
        return jdbc.sql("SELECT " + COLUMNAS_CONSUMO + " FROM vw_consumos_lote WHERE id_lote = :id ORDER BY insumo")
                   .param("id", idLote).query(ConsumoLote.class).list();
    }

    // ---------- recetas ----------

    /** {codigo_sku, nombre} del producto, o vacio si no existe. */
    public Optional<String[]> productoBasico(long idProducto) {
        return jdbc.sql("SELECT codigo_sku, nombre FROM vw_productos WHERE id_producto = :id")
                   .param("id", idProducto)
                   .query((rs, n) -> new String[]{rs.getString(1), rs.getString(2)})
                   .optional();
    }

    public List<LineaRecetaDto> lineasReceta(long idProducto) {
        return jdbc.sql("SELECT " + COLUMNAS_LINEA + " FROM vw_recetas WHERE id_producto = :id ORDER BY insumo")
                   .param("id", idProducto).query(LineaRecetaDto.class).list();
    }

    public Optional<BigDecimal[]> costoYCapacidad(long idProducto) {
        return jdbc.sql("SELECT costo_insumos_unitario, unidades_posibles FROM vw_costo_insumos_producto WHERE id_producto = :id")
                   .param("id", idProducto)
                   .query((rs, n) -> new BigDecimal[]{rs.getBigDecimal(1), rs.getBigDecimal(2)})
                   .optional();
    }
}
