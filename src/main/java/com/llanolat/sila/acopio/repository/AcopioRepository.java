package com.llanolat.sila.acopio.repository;

import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PagoProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PrecioProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.SaldoProveedor;
import com.llanolat.sila.acopio.dto.RecepcionDto;
import com.llanolat.sila.acopio.dto.ResumenesAcopioDto.CalidadProveedor;
import com.llanolat.sila.acopio.dto.ResumenesAcopioDto.PagoLechero;
import com.llanolat.sila.acopio.dto.ResumenesAcopioDto.Umbrales;
import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.SilaTemplate;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDate;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Acopio de leche: escritura por pkg_acopio (rol OPERATIVO) y lectura por vistas. */
@Repository
public class AcopioRepository {

    private static final String COLUMNAS_RECEPCION = """
            id_recepcion, id_proveedor, proveedor, id_periodo, fecha, litros, temperatura, acidez,
            estado_calidad, motivo_rechazo, usuario_registro, fecha_registro, precio_litro, valor_total""";
    private static final Map<String, String> ORDEN_RECEPCIONES = Map.of(
            "id_recepcion", "id_recepcion", "fecha", "fecha", "proveedor", "proveedor", "litros", "litros",
            "temperatura", "temperatura", "acidez", "acidez", "estado_calidad", "estado_calidad");
    private static final Map<String, String> ORDEN_CALIDAD = Map.of(
            "id_proveedor", "id_proveedor", "proveedor", "proveedor", "numero_entregas", "numero_entregas",
            "porcentaje_rechazo", "porcentaje_rechazo", "entregas_rechazadas", "entregas_rechazadas");
    private static final Map<String, String> ORDEN_PAGO = Map.of(
            "id_proveedor", "id_proveedor", "proveedor", "proveedor", "litros_a_pagar", "litros_a_pagar",
            "litros_rechazados", "litros_rechazados", "id_periodo", "id_periodo",
            "valor_leche", "valor_leche", "valor_pagado", "valor_pagado", "saldo", "saldo");

    private final SilaTemplate sila;
    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public AcopioRepository(SilaTemplate sila, ConsultaPaginada paginada, JdbcClient jdbc) {
        this.sila = sila;
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    /** OPERATIVO. La calidad (APROBADO/RECHAZADO) la decide la base con los umbrales; un rechazo NO es un error. */
    public long registrarRecepcion(long idProveedor, BigDecimal litros, BigDecimal temperatura,
                                   BigDecimal acidez, LocalDate fecha) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_acopio.sp_registrar_recepcion(?,?,?,?,?,?,?)}")) {
                s.setLong(1, idProveedor);
                s.setBigDecimal(2, litros);
                s.setBigDecimal(3, temperatura);
                s.setBigDecimal(4, acidez);
                s.setDate(5, java.sql.Date.valueOf(fecha));
                s.registerOutParameter(6, Types.NUMERIC);
                s.registerOutParameter(7, Types.VARCHAR);
                s.execute();
                return s.getLong(6);
            }
        });
    }

    public Optional<RecepcionDto> recepcion(long id) {
        return jdbc.sql("SELECT " + COLUMNAS_RECEPCION + " FROM vw_recepciones WHERE id_recepcion = :id")
                   .param("id", id).query(RecepcionDto.class).optional();
    }

    public Page<RecepcionDto> recepciones(Long idProveedor, String estado, LocalDate desde, LocalDate hasta,
                                          Long idPeriodo, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (idProveedor != null) f.cuando("id_proveedor = :idProveedor").param("idProveedor", idProveedor);
        if (idPeriodo != null) f.cuando("id_periodo = :idPeriodo").param("idPeriodo", idPeriodo);
        if (estado != null && !estado.isBlank()) f.cuando("estado_calidad = :estado").param("estado", estado.trim().toUpperCase());
        if (desde != null) f.cuando("fecha >= :f_desde").param("f_desde", desde);
        if (hasta != null) f.cuando("fecha <= :f_hasta").param("f_hasta", hasta);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_RECEPCIONES, "fecha,desc", "id_recepcion");
        return paginada.consultar(COLUMNAS_RECEPCION, "vw_recepciones", f, pag, RecepcionDto.class);
    }

    public Page<CalidadProveedor> calidad(Integer page, Integer size, String sort) {
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_CALIDAD, "proveedor,asc", "id_proveedor");
        return paginada.consultar("id_proveedor, proveedor, numero_entregas, temperatura_promedio, acidez_promedio, "
                + "entregas_rechazadas, porcentaje_rechazo", "vw_calidad_leche_proveedor", new Filtro(), pag, CalidadProveedor.class);
    }

    public Page<PagoLechero> pagoLecheros(Long idPeriodo, Integer anio, Long idProveedor,
                                          Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (idPeriodo != null) f.cuando("id_periodo = :idPeriodo").param("idPeriodo", idPeriodo);
        if (anio != null) f.cuando("anio = :anio").param("anio", anio);
        if (idProveedor != null) f.cuando("id_proveedor = :idProveedor").param("idProveedor", idProveedor);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_PAGO, "proveedor,asc", "id_proveedor");
        return paginada.consultar("id_periodo, anio, mes, quincena, id_proveedor, proveedor, litros_a_pagar, litros_rechazados, "
                + "valor_leche, valor_pagado, saldo, precio_promedio",
                "vw_resumen_pago_lecheros", f, pag, PagoLechero.class);
    }

    public Umbrales umbrales() {
        Map<String, BigDecimal> v = new java.util.HashMap<>();
        jdbc.sql("SELECT clave, valor_numero FROM vw_umbrales_operacion").query((rs, n) -> {
            v.put(rs.getString("clave"), rs.getBigDecimal("valor_numero"));
            return null;
        }).list();
        return new Umbrales(v.get("TEMP_MAX_LECHE_C"), v.get("ACIDEZ_MAX_DORNIC"));
    }

    // ---------- precios, pagos y saldos de los lecheros ----------

    private static final Map<String, String> ORDEN_PRECIOS = Map.of(
            "id_precio", "id_precio", "proveedor", "proveedor", "precio_litro", "precio_litro", "vigente_desde", "vigente_desde");
    private static final Map<String, String> ORDEN_PAGOS = Map.of(
            "id_pago", "id_pago", "fecha_pago", "fecha_pago", "proveedor", "proveedor", "monto", "monto", "estado", "estado");
    private static final Map<String, String> ORDEN_SALDOS = Map.of(
            "id_proveedor", "id_proveedor", "proveedor", "proveedor", "saldo", "saldo",
            "total_comprado", "total_comprado", "total_pagado", "total_pagado", "ultima_entrega", "ultima_entrega");

    /** ADMIN. Afecta solo las recepciones futuras: las ya registradas conservan su precio. */
    public void fijarPrecio(long idProveedor, BigDecimal precio, LocalDate desde) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_pagos_proveedor.sp_fijar_precio(?,?,?)}")) {
                s.setLong(1, idProveedor);
                s.setBigDecimal(2, precio);
                s.setDate(3, java.sql.Date.valueOf(desde));
                s.execute();
                return null;
            }
        });
    }

    /** ADMIN. El pago no puede superar el saldo de la quincena que liquida. */
    public long registrarPago(long idProveedor, long idPeriodoLiquidado, BigDecimal monto, String metodo,
                              String referencia, LocalDate fecha) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_pagos_proveedor.sp_registrar_pago(?,?,?,?,?,?,?)}")) {
                s.setLong(1, idProveedor);
                s.setLong(2, idPeriodoLiquidado);
                s.setBigDecimal(3, monto);
                s.setString(4, metodo);
                s.setString(5, referencia);
                s.setDate(6, java.sql.Date.valueOf(fecha));
                s.registerOutParameter(7, Types.NUMERIC);
                s.execute();
                return s.getLong(7);
            }
        });
    }

    public void anularPago(long idPago, String motivo) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_pagos_proveedor.sp_anular_pago(?,?)}")) {
                s.setLong(1, idPago);
                s.setString(2, motivo);
                s.execute();
                return null;
            }
        });
    }

    private static final String COLUMNAS_PAGO = """
            id_pago, id_proveedor, proveedor, id_periodo, id_periodo_liquidado, anio, mes, quincena, fecha_pago,
            monto, metodo_pago, referencia_pago, estado, motivo_anulacion, usuario_registro, fecha_registro""";

    public Optional<PagoProveedor> pago(long id) {
        return jdbc.sql("SELECT " + COLUMNAS_PAGO + " FROM vw_pagos_proveedor WHERE id_pago = :id")
                   .param("id", id).query(PagoProveedor.class).optional();
    }

    public Page<PagoProveedor> pagos(Long idProveedor, Long idPeriodo, Long idPeriodoLiquidado, String estado,
                                     Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (idProveedor != null) f.cuando("id_proveedor = :idProveedor").param("idProveedor", idProveedor);
        if (idPeriodo != null) f.cuando("id_periodo = :idPeriodo").param("idPeriodo", idPeriodo);
        if (idPeriodoLiquidado != null) f.cuando("id_periodo_liquidado = :idLiq").param("idLiq", idPeriodoLiquidado);
        if (estado != null && !estado.isBlank()) f.cuando("estado = :estado").param("estado", estado.trim().toUpperCase());
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_PAGOS, "fecha_pago,desc", "id_pago");
        return paginada.consultar(COLUMNAS_PAGO, "vw_pagos_proveedor", f, pag, PagoProveedor.class);
    }

    public Page<PrecioProveedor> precios(Long idProveedor, boolean soloVigentes, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (idProveedor != null) f.cuando("id_proveedor = :idProveedor").param("idProveedor", idProveedor);
        if (soloVigentes) f.cuando("vigente = 1");
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_PRECIOS, "vigente_desde,desc", "id_precio");
        return paginada.consultar("id_precio, id_proveedor, proveedor, precio_litro, vigente_desde, vigente, usuario_creacion, fecha_creacion",
                "vw_precios_proveedor", f, pag, PrecioProveedor.class);
    }

    public Page<SaldoProveedor> saldos(Boolean soloConSaldo, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (Boolean.TRUE.equals(soloConSaldo)) f.cuando("saldo > 0");
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_SALDOS, "saldo,desc", "id_proveedor");
        return paginada.consultar("id_proveedor, proveedor, activo, precio_vigente, litros_aprobados, total_comprado, "
                + "total_pagado, saldo, ultima_entrega, ultimo_pago", "vw_saldo_proveedores", f, pag, SaldoProveedor.class);
    }
}
