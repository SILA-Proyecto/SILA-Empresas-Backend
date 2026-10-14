package com.llanolat.sila.finanzas.repository;

import com.llanolat.sila.finanzas.dto.GastosDtos.Gasto;
import com.llanolat.sila.finanzas.dto.GastosDtos.ResumenGastos;
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
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Gastos operativos: escritura por pkg_finanzas (rol OPERATIVO) y lectura por vw_gastos. */
@Repository
public class GastoRepository {

    private static final String COLUMNAS = """
            id_gasto, id_periodo, anio, mes, quincena, id_categoria, categoria, fecha_gasto, concepto, monto,
            usuario_registro, fecha_registro, estado, motivo_anulacion, usuario_anulacion, fecha_anulacion""";
    private static final Map<String, String> ORDEN = Map.of(
            "id_gasto", "id_gasto", "fecha_gasto", "fecha_gasto", "categoria", "categoria", "monto", "monto",
            "concepto", "concepto", "fecha_registro", "fecha_registro", "estado", "estado");

    private final SilaTemplate sila;
    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public GastoRepository(SilaTemplate sila, ConsultaPaginada paginada, JdbcClient jdbc) {
        this.sila = sila;
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    /** OPERATIVO. La fecha va siempre explicita (hora de Colombia). */
    public long registrar(long idCategoria, String concepto, BigDecimal monto, LocalDate fecha) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_finanzas.sp_registrar_gasto(?,?,?,?,?)}")) {
                s.setLong(1, idCategoria);
                s.setString(2, concepto);
                s.setBigDecimal(3, monto);
                s.setDate(4, java.sql.Date.valueOf(fecha));
                s.registerOutParameter(5, Types.NUMERIC);
                s.execute();
                return s.getLong(5);
            }
        });
    }

    /** ADMIN. Motivo de 10+ caracteres; la quincena del gasto debe estar abierta. */
    public void anular(long id, String motivo) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_finanzas.sp_anular_gasto(?,?)}")) {
                s.setLong(1, id);
                s.setString(2, motivo);
                s.execute();
                return null;
            }
        });
    }

    public Optional<Gasto> gasto(long id) {
        return jdbc.sql("SELECT " + COLUMNAS + " FROM vw_gastos WHERE id_gasto = :id")
                   .param("id", id).query(Gasto.class).optional();
    }

    public Page<Gasto> gastos(Long idPeriodo, Long idCategoria, String texto, String estado, LocalDate desde, LocalDate hasta,
                              Integer page, Integer size, String sort) {
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN, "fecha_gasto,desc", "id_gasto");
        return paginada.consultar(COLUMNAS, "vw_gastos", filtro(idPeriodo, idCategoria, texto, estado, desde, hasta), pag, Gasto.class);
    }

    public ResumenGastos resumen(Long idPeriodo, Long idCategoria, String texto, LocalDate desde, LocalDate hasta) {
        return paginada.agregar("NVL(SUM(monto), 0) AS total, COUNT(*) AS cantidad", "vw_gastos",
                filtro(idPeriodo, idCategoria, texto, "VIGENTE", desde, hasta), ResumenGastos.class);
    }

    private static Filtro filtro(Long idPeriodo, Long idCategoria, String texto, String estado, LocalDate desde, LocalDate hasta) {
        Filtro f = new Filtro();
        if (idPeriodo != null) f.cuando("id_periodo = :idPeriodo").param("idPeriodo", idPeriodo);
        if (idCategoria != null) f.cuando("id_categoria = :idCategoria").param("idCategoria", idCategoria);
        if (estado != null && !estado.isBlank()) f.cuando("estado = :estado").param("estado", estado.trim().toUpperCase());
        if (desde != null) f.cuando("fecha_gasto >= :f_desde").param("f_desde", desde);
        if (hasta != null) f.cuando("fecha_gasto <= :f_hasta").param("f_hasta", hasta);
        if (texto != null && !texto.isBlank()) {
            f.cuando(Texto.comoSinAcentos("concepto"))
             .param("q", texto.trim()).param("conAcento", Texto.ACENTOS).param("sinAcento", Texto.SIN_ACENTOS);
        }
        return f;
    }
}
