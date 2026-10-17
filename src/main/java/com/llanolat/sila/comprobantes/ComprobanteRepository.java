package com.llanolat.sila.comprobantes;

import com.llanolat.sila.comprobantes.Comprobantes.Comprobante;
import com.llanolat.sila.comprobantes.Comprobantes.Detalle;
import com.llanolat.sila.comprobantes.Comprobantes.Linea;
import com.llanolat.sila.comprobantes.Comprobantes.Pago;
import com.llanolat.sila.comprobantes.Comprobantes.Resumen;
import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.infra.Texto;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class ComprobanteRepository {

    static final Set<String> TIPOS = Set.of("VENTA", "ABONO", "PAGO_PROVEEDOR", "COMPRA", "GASTO");
    private static final String COLUMNAS = """
            tipo, id_documento, numero, sentido, afecta_caja, fecha, monto, id_tercero, tercero_tipo, tercero,
            descripcion, metodo_pago, referencia, estado, motivo_anulacion, id_periodo, usuario_registro""";
    private static final Map<String, String> ORDEN = Map.of(
            "fecha", "fecha", "monto", "monto", "tipo", "tipo", "numero", "numero",
            "tercero", "tercero", "estado", "estado", "sentido", "sentido");

    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public ComprobanteRepository(ConsultaPaginada paginada, JdbcClient jdbc) {
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    public Page<Comprobante> listar(String tipo, String sentido, String estado, Long idPeriodo, String texto,
                                    LocalDate desde, LocalDate hasta, Integer page, Integer size, String sort) {
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN, "fecha,desc", "tipo, id_documento");
        return paginada.consultar(COLUMNAS, "vw_comprobantes", filtro(tipo, sentido, estado, idPeriodo, texto, desde, hasta),
                pag, Comprobante.class);
    }

    /** Solo VIGENTES; los anulados no suman. */
    public Resumen resumen(String tipo, String sentido, Long idPeriodo, String texto, LocalDate desde, LocalDate hasta) {
        return paginada.agregar("""
                NVL(SUM(CASE WHEN sentido = 'INGRESO' AND afecta_caja = 1 THEN monto END), 0) AS ingresos,
                NVL(SUM(CASE WHEN sentido = 'EGRESO' AND afecta_caja = 1 THEN monto END), 0) AS egresos,
                NVL(SUM(CASE WHEN sentido = 'INGRESO' AND afecta_caja = 1 THEN monto END), 0)
                  - NVL(SUM(CASE WHEN sentido = 'EGRESO' AND afecta_caja = 1 THEN monto END), 0) AS neto,
                COUNT(*) AS cantidad""", "vw_comprobantes", filtro(tipo, sentido, "VIGENTE", idPeriodo, texto, desde, hasta), Resumen.class);
    }

    public static String validarTipo(String tipo) {
        String t = tipo == null ? "" : tipo.trim().toUpperCase();
        if (!TIPOS.contains(t)) throw SilaException.parametroInvalido("tipo debe ser uno de " + new java.util.TreeSet<>(TIPOS) + ".", "tipo");
        return t;
    }

    public Detalle detalle(String tipo, long id) {
        String t = validarTipo(tipo);
        Comprobante c = jdbc.sql("SELECT " + COLUMNAS + " FROM vw_comprobantes WHERE tipo = :t AND id_documento = :id")
                .param("t", t).param("id", id).query(Comprobante.class).optional()
                .orElseThrow(() -> SilaException.noEncontrado("El comprobante " + t + " #" + id + " no existe."));
        Detalle d = switch (t) {
            case "VENTA" -> {
                List<Linea> lineas = jdbc.sql("""
                        SELECT producto || ' (' || unidad_medida || ')' AS concepto, cantidad, precio_unitario AS valor_unitario,
                               total_linea AS valor FROM vw_ventas_lineas WHERE id_venta = :id ORDER BY id_detalle""")
                        .param("id", id).query(Linea.class).list();
                List<Pago> pagos = jdbc.sql("""
                        SELECT metodo_pago, monto, referencia_pago AS referencia FROM vw_ventas_pagos
                         WHERE id_venta = :id ORDER BY id_pago""").param("id", id).query(Pago.class).list();
                BigDecimal[] t2 = jdbc.sql("SELECT subtotal_venta, total_iva FROM vw_ventas_completa WHERE id_venta = :id")
                        .param("id", id).query((rs, n) -> new BigDecimal[] {rs.getBigDecimal(1), rs.getBigDecimal(2)}).single();
                yield new Detalle(c, lineas, pagos, t2[0], t2[1]);
            }
            case "ABONO" -> new Detalle(c, jdbc.sql("""
                    SELECT 'Abono a la venta #' || id_venta AS concepto, CAST(NULL AS NUMBER) AS cantidad,
                           CAST(NULL AS NUMBER) AS valor_unitario, monto AS valor
                      FROM vw_abonos_cartera WHERE id_recibo = :id ORDER BY id_abono""")
                    .param("id", id).query(Linea.class).list(), pagoUnico(c), null, null);
            case "COMPRA" -> new Detalle(c, jdbc.sql("""
                    SELECT insumo || ' (' || unidad_medida || ')' AS concepto, cantidad, costo_unitario AS valor_unitario,
                           valor_total AS valor FROM vw_compras_insumo WHERE id_compra = :id""")
                    .param("id", id).query(Linea.class).list(), List.of(), null, null);
            case "PAGO_PROVEEDOR", "GASTO" -> new Detalle(c,
                    List.of(new Linea(c.descripcion() == null ? c.numero() : c.descripcion(), null, null, c.monto())), pagoUnico(c), null, null);
            default -> throw new IllegalStateException("Tipo de comprobante sin detalle: " + t);
        };
        if (d.lineas().isEmpty()) throw new IllegalStateException("El comprobante " + c.numero() + " existe pero no tiene lineas.");
        return d;
    }

    private static List<Pago> pagoUnico(Comprobante c) {
        return c.metodoPago() == null ? List.of() : List.of(new Pago(c.metodoPago(), c.monto(), c.referencia()));
    }

    private static Filtro filtro(String tipo, String sentido, String estado, Long idPeriodo, String texto, LocalDate desde, LocalDate hasta) {
        Filtro f = new Filtro();
        if (tipo != null && !tipo.isBlank()) {
            f.cuando("tipo = :tipo").param("tipo", validarTipo(tipo));
        }
        if (sentido != null && !sentido.isBlank()) {
            String s = sentido.trim().toUpperCase();
            if (!s.equals("INGRESO") && !s.equals("EGRESO")) throw SilaException.parametroInvalido("sentido debe ser INGRESO o EGRESO.", "sentido");
            f.cuando("sentido = :sentido").param("sentido", s);
        }
        if (estado != null && !estado.isBlank()) {
            String e = estado.trim().toUpperCase();
            if (!e.equals("VIGENTE") && !e.equals("ANULADO")) throw SilaException.parametroInvalido("estado debe ser VIGENTE o ANULADO.", "estado");
            f.cuando("estado = :estado").param("estado", e);
        }
        if (idPeriodo != null) f.cuando("id_periodo = :idPeriodo").param("idPeriodo", idPeriodo);
        if (desde != null) f.cuando("fecha >= :f_desde").param("f_desde", desde);
        if (hasta != null) f.cuando("fecha <= :f_hasta").param("f_hasta", hasta);
        if (texto != null && !texto.isBlank()) {
            f.cuando("(" + Texto.comoSinAcentos("numero") + " OR " + Texto.comoSinAcentos("tercero") + " OR "
                    + Texto.comoSinAcentos("descripcion") + " OR " + Texto.comoSinAcentos("referencia") + ")")
             .param("q", texto.trim()).param("conAcento", Texto.ACENTOS).param("sinAcento", Texto.SIN_ACENTOS);
        }
        return f;
    }
}
