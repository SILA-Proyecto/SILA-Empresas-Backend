package com.llanolat.sila.ventas.repository;

import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.SilaTemplate;
import com.llanolat.sila.infra.Texto;
import com.llanolat.sila.ventas.dto.VentasDtos.Linea;
import com.llanolat.sila.ventas.dto.VentasDtos.Pago;
import com.llanolat.sila.ventas.dto.VentasDtos.PrecioAplicable;
import com.llanolat.sila.ventas.dto.VentasDtos.PrecioCliente;
import com.llanolat.sila.ventas.dto.VentasDtos.Venta;
import java.io.StringReader;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Ventas: escritura por pkg_ventas / pkg_precios (la base valida stock, cupo, rol y suma de pagos) y lectura por vistas. */
@Repository
public class VentaRepository {

    private static final String COLUMNAS_VENTA = """
            id_venta, id_cliente, cliente, tipo_documento, numero_documento, id_periodo, fecha_venta, tipo_venta,
            fecha_vencimiento, subtotal_venta, total_iva, total_venta, saldo_pendiente, monto_castigado,
            estado_pago, motivo_anulacion, usuario_registro, fecha_registro""";
    private static final String COLUMNAS_PRECIO = """
            id_precio, id_cliente, cliente, id_producto, codigo_sku, producto, unidad_medida, precio, precio_base, diferencia, activo""";

    private static final Map<String, String> ORDEN_VENTAS = Map.of(
            "id_venta", "id_venta", "fecha_venta", "fecha_venta", "cliente", "cliente", "total_venta", "total_venta",
            "saldo_pendiente", "saldo_pendiente", "estado_pago", "estado_pago", "tipo_venta", "tipo_venta");
    private static final Map<String, String> ORDEN_PRECIOS_APLICABLES = Map.of(
            "id_producto", "p.id_producto", "codigo_sku", "p.codigo_sku", "producto", "p.nombre",
            "stock_actual", "p.stock_actual", "precio_aplicable", "NVL(pc.precio, p.precio_base)");
    private static final Map<String, String> ORDEN_PRECIOS = Map.of(
            "id_precio", "id_precio", "cliente", "cliente", "producto", "producto", "precio", "precio", "diferencia", "diferencia");

    private final SilaTemplate sila;
    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public VentaRepository(SilaTemplate sila, ConsultaPaginada paginada, JdbcClient jdbc) {
        this.sila = sila;
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    // ---------- escritura ----------

    /** OPERATIVO. Descuenta stock; en CREDITO sube la deuda del cliente; el precio es el pactado con el cliente si existe. */
    public long registrar(long idCliente, String tipoVenta, String lineasJson, String pagosJson) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_ventas.sp_registrar_venta(?,?,?,?,?,?)}")) {
                s.setLong(1, idCliente);
                s.setString(2, tipoVenta);
                s.setCharacterStream(3, new StringReader(lineasJson), lineasJson.length());
                if (pagosJson == null) s.setNull(4, Types.CLOB);
                else s.setCharacterStream(4, new StringReader(pagosJson), pagosJson.length());
                s.registerOutParameter(5, Types.NUMERIC);
                s.registerOutParameter(6, Types.NUMERIC);
                s.execute();
                return s.getLong(5);
            }
        });
    }

    /** ADMIN. Devuelve el stock y la deuda; la base lo rechaza si hay abonos o una factura enviada. */
    public void anular(long idVenta, String motivo) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_ventas.sp_anular_venta(?,?)}")) {
                s.setLong(1, idVenta);
                s.setString(2, motivo);
                s.execute();
                return null;
            }
        });
    }

    /** ADMIN. */
    public long fijarPrecio(long idCliente, long idProducto, java.math.BigDecimal precio) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_precios.sp_fijar_precio(?,?,?,?)}")) {
                s.setLong(1, idCliente);
                s.setLong(2, idProducto);
                s.setBigDecimal(3, precio);
                s.registerOutParameter(4, Types.NUMERIC);
                s.execute();
                return s.getLong(4);
            }
        });
    }

    /** ADMIN. */
    public void quitarPrecio(long idCliente, long idProducto) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_precios.sp_quitar_precio(?,?)}")) {
                s.setLong(1, idCliente);
                s.setLong(2, idProducto);
                s.execute();
                return null;
            }
        });
    }

    // ---------- lectura ----------

    public Optional<Venta> venta(long id) {
        return jdbc.sql("SELECT " + COLUMNAS_VENTA + " FROM vw_ventas_completa WHERE id_venta = :id")
                   .param("id", id).query(Venta.class).optional();
    }

    public List<Linea> lineas(long idVenta) {
        return jdbc.sql("""
                SELECT id_detalle, id_producto, codigo_sku, producto, unidad_medida, cantidad, precio_unitario, precio_lista,
                       CASE WHEN precio_lista IS NOT NULL AND precio_lista <> precio_unitario THEN 1 ELSE 0 END AS precio_pactado,
                       tarifa_iva, subtotal, valor_iva, total_linea
                  FROM vw_ventas_lineas WHERE id_venta = :id ORDER BY id_detalle""")
                   .param("id", idVenta).query(Linea.class).list();
    }

    public List<Pago> pagos(long idVenta) {
        return jdbc.sql("SELECT id_pago, metodo_pago, monto, referencia_pago FROM vw_ventas_pagos WHERE id_venta = :id ORDER BY id_pago")
                   .param("id", idVenta).query(Pago.class).list();
    }

    public Page<Venta> listar(String texto, Long idCliente, String estadoPago, String tipoVenta,
                              LocalDate desde, LocalDate hasta, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (texto != null && !texto.isBlank()) {
            f.cuando("(" + Texto.comoSinAcentos("cliente") + " OR numero_documento LIKE '%' || :q || '%')")
             .param("q", texto.trim()).param("conAcento", Texto.ACENTOS).param("sinAcento", Texto.SIN_ACENTOS);
        }
        if (idCliente != null) f.cuando("id_cliente = :idCliente").param("idCliente", idCliente);
        if (estadoPago != null && !estadoPago.isBlank()) f.cuando("estado_pago = :estadoPago").param("estadoPago", estadoPago.trim().toUpperCase());
        if (tipoVenta != null && !tipoVenta.isBlank()) f.cuando("tipo_venta = :tipoVenta").param("tipoVenta", tipoVenta.trim().toUpperCase());
        if (desde != null) f.cuando("fecha_venta >= :f_desde").param("f_desde", desde.atStartOfDay());
        if (hasta != null) f.cuando("fecha_venta < :f_hasta").param("f_hasta", hasta.plusDays(1).atStartOfDay());
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_VENTAS, "fecha_venta,desc", "id_venta");
        return paginada.consultar(COLUMNAS_VENTA, "vw_ventas_completa", f, pag, Venta.class);
    }

    /** Productos activos con el precio que se le cobraria a ESTE cliente (pactado o de lista). Para el punto de venta. */
    public Page<PrecioAplicable> preciosAplicables(long idCliente, String texto, boolean soloConStock,
                                                   Integer page, Integer size, String sort) {
        Filtro f = new Filtro().cuando("p.activo = 1").param("idCliente", idCliente);
        if (texto != null && !texto.isBlank()) {
            f.cuando("(" + Texto.comoSinAcentos("p.nombre") + " OR UPPER(p.codigo_sku) LIKE UPPER('%' || :q || '%'))")
             .param("q", texto.trim()).param("conAcento", Texto.ACENTOS).param("sinAcento", Texto.SIN_ACENTOS);
        }
        if (soloConStock) f.cuando("p.stock_actual > 0");
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_PRECIOS_APLICABLES, "producto,asc", "p.id_producto");
        return paginada.consultar("""
                p.id_producto, p.codigo_sku, p.nombre AS producto, p.unidad_medida, p.tarifa_iva, p.stock_actual,
                p.precio_base, pc.precio AS precio_pactado, NVL(pc.precio, p.precio_base) AS precio_aplicable""",
                "vw_productos p LEFT JOIN vw_precios_cliente pc ON pc.id_producto = p.id_producto AND pc.id_cliente = :idCliente AND pc.activo = 1",
                f, pag, PrecioAplicable.class);
    }

    public Optional<PrecioCliente> precioCliente(long idPrecio) {
        return jdbc.sql("SELECT " + COLUMNAS_PRECIO + " FROM vw_precios_cliente WHERE id_precio = :id")
                   .param("id", idPrecio).query(PrecioCliente.class).optional();
    }

    public Page<PrecioCliente> preciosCliente(Long idCliente, Long idProducto, Boolean activo,
                                              Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (idCliente != null) f.cuando("id_cliente = :idCliente").param("idCliente", idCliente);
        if (idProducto != null) f.cuando("id_producto = :idProducto").param("idProducto", idProducto);
        if (activo != null) f.cuando("activo = :activo").param("activo", activo ? 1 : 0);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_PRECIOS, "cliente,asc", "id_precio");
        return paginada.consultar(COLUMNAS_PRECIO, "vw_precios_cliente", f, pag, PrecioCliente.class);
    }
}
