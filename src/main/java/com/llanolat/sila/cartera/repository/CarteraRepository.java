package com.llanolat.sila.cartera.repository;

import com.llanolat.sila.cartera.dto.CarteraDtos.Abono;
import com.llanolat.sila.cartera.dto.CarteraDtos.ClienteCartera;
import com.llanolat.sila.cartera.dto.CarteraDtos.Resumen;
import com.llanolat.sila.cartera.dto.CarteraDtos.VentaPendiente;
import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.SilaTemplate;
import com.llanolat.sila.infra.Texto;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Cartera: escritura por pkg_cartera (abonos: OPERATIVO; castigos: ADMIN) y lectura por vistas. */
@Repository
public class CarteraRepository {

    private static final String COLUMNAS_ABONO = """
            id_abono, id_recibo, id_cliente, cliente, id_venta, fecha_abono, monto, metodo_pago, referencia_pago, usuario_registro""";
    private static final String HOY_CO = "TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Bogota' AS DATE))";

    private static final Map<String, String> ORDEN_CLIENTES = Map.of(
            "id_cliente", "id_cliente", "cliente", "cliente", "saldo_deudor", "saldo_deudor", "dias_mora", "dias_mora",
            "limite_credito", "limite_credito", "cupo_disponible", "cupo_disponible", "estado_credito", "estado_credito");
    private static final Map<String, String> ORDEN_ABONOS = Map.of(
            "id_abono", "id_abono", "fecha_abono", "fecha_abono", "cliente", "cliente", "monto", "monto", "id_recibo", "id_recibo");

    private final SilaTemplate sila;
    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public CarteraRepository(SilaTemplate sila, ConsultaPaginada paginada, JdbcClient jdbc) {
        this.sila = sila;
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    public record ReciboCreado(long idRecibo, BigDecimal saldoRestante) {}

    /** OPERATIVO. El monto se reparte de la venta pendiente mas antigua a la mas nueva; no puede exceder la deuda. */
    public ReciboCreado registrarAbono(long idCliente, BigDecimal monto, String metodo, String referencia) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_cartera.sp_registrar_abono(?,?,?,?,?,?)}")) {
                s.setLong(1, idCliente);
                s.setBigDecimal(2, monto);
                s.setString(3, metodo);
                if (referencia == null || referencia.isBlank()) s.setNull(4, Types.VARCHAR); else s.setString(4, referencia.trim());
                s.registerOutParameter(5, Types.NUMERIC);
                s.registerOutParameter(6, Types.NUMERIC);
                s.execute();
                return new ReciboCreado(s.getLong(5), s.getBigDecimal(6));
            }
        });
    }

    /** ADMIN. Da de baja la cartera pendiente del cliente (incobrable); devuelve el monto castigado. */
    public BigDecimal castigar(long idCliente, String motivo) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_cartera.sp_castigar_cartera(?,?,?)}")) {
                s.setLong(1, idCliente);
                s.setString(2, motivo);
                s.registerOutParameter(3, Types.NUMERIC);
                s.execute();
                return s.getBigDecimal(3);
            }
        });
    }

    public Page<ClienteCartera> clientes(String texto, String estadoCredito, boolean soloConDeuda, Integer moraMinima,
                                         Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (texto != null && !texto.isBlank()) {
            f.cuando(Texto.comoSinAcentos("cliente")).param("q", texto.trim())
             .param("conAcento", Texto.ACENTOS).param("sinAcento", Texto.SIN_ACENTOS);
        }
        if (estadoCredito != null && !estadoCredito.isBlank()) f.cuando("estado_credito = :estadoCredito").param("estadoCredito", estadoCredito.trim().toUpperCase());
        if (soloConDeuda) f.cuando("saldo_deudor > 0");
        if (moraMinima != null) f.cuando("dias_mora >= :moraMinima").param("moraMinima", moraMinima);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_CLIENTES, "saldo_deudor,desc", "id_cliente");
        return paginada.consultar("id_cliente, cliente, telefono, limite_credito, saldo_deudor, cupo_disponible, dias_mora, estado_credito",
                "vw_dashboard_cartera", f, pag, ClienteCartera.class);
    }

    public Resumen resumen() {
        return jdbc.sql("""
                SELECT NVL((SELECT SUM(saldo_deudor) FROM vw_dashboard_cartera), 0) AS total_cartera,
                       (SELECT COUNT(*) FROM vw_dashboard_cartera WHERE saldo_deudor > 0) AS clientes_con_deuda,
                       (SELECT COUNT(*) FROM vw_dashboard_cartera WHERE estado_credito = 'EN_MORA') AS clientes_en_mora,
                       NVL((SELECT SUM(saldo_pendiente) FROM vw_ventas_completa
                             WHERE estado_pago = 'PENDIENTE' AND fecha_vencimiento < %s), 0) AS cartera_vencida
                  FROM dual""".formatted(HOY_CO)).query(Resumen.class).single();
    }

    public List<VentaPendiente> ventasPendientes(long idCliente) {
        return jdbc.sql("""
                SELECT id_venta, fecha_venta, fecha_vencimiento, total_venta, saldo_pendiente,
                       GREATEST(0, %s - fecha_vencimiento) AS dias_mora
                  FROM vw_ventas_completa
                 WHERE id_cliente = :id AND estado_pago = 'PENDIENTE'
                 ORDER BY fecha_venta, id_venta""".formatted(HOY_CO))
                   .param("id", idCliente).query(VentaPendiente.class).list();
    }

    public List<Abono> abonosDeRecibo(long idRecibo) {
        return jdbc.sql("SELECT " + COLUMNAS_ABONO + " FROM vw_abonos_cartera WHERE id_recibo = :id ORDER BY id_abono")
                   .param("id", idRecibo).query(Abono.class).list();
    }

    public Page<Abono> abonos(Long idCliente, Long idVenta, Long idRecibo, String metodo, LocalDate desde, LocalDate hasta,
                              Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (idCliente != null) f.cuando("id_cliente = :idCliente").param("idCliente", idCliente);
        if (idVenta != null) f.cuando("id_venta = :idVenta").param("idVenta", idVenta);
        if (idRecibo != null) f.cuando("id_recibo = :idRecibo").param("idRecibo", idRecibo);
        if (metodo != null && !metodo.isBlank()) f.cuando("metodo_pago = :metodo").param("metodo", metodo.trim().toUpperCase());
        if (desde != null) f.cuando("fecha_abono >= :f_desde").param("f_desde", desde.atStartOfDay());
        if (hasta != null) f.cuando("fecha_abono < :f_hasta").param("f_hasta", hasta.plusDays(1).atStartOfDay());
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_ABONOS, "fecha_abono,desc", "id_abono");
        return paginada.consultar(COLUMNAS_ABONO, "vw_abonos_cartera", f, pag, Abono.class);
    }
}
