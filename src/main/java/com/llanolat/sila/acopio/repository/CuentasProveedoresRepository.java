package com.llanolat.sila.acopio.repository;

import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PagoProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PrecioProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.ResumenPagoProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.SaldoProveedor;
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

/** Cuentas con los proveedores: precios pactados, pagos por quincena y saldos. Escritura por pkg_pagos_proveedor (ADMIN). */
@Repository
public class CuentasProveedoresRepository {

    private static final Map<String, String> ORDEN_PRECIOS = Map.of(
            "id_precio", "id_precio", "proveedor", "proveedor", "insumo", "insumo",
            "precio_unitario", "precio_unitario", "vigente_desde", "vigente_desde");
    private static final Map<String, String> ORDEN_PAGOS = Map.of(
            "id_pago", "id_pago", "fecha_pago", "fecha_pago", "proveedor", "proveedor", "monto", "monto", "estado", "estado");
    private static final Map<String, String> ORDEN_SALDOS = Map.of(
            "id_proveedor", "id_proveedor", "proveedor", "proveedor", "saldo", "saldo",
            "total_comprado", "total_comprado", "total_pagado", "total_pagado", "ultima_compra", "ultima_compra");
    private static final Map<String, String> ORDEN_RESUMEN = Map.of(
            "id_proveedor", "id_proveedor", "proveedor", "proveedor", "id_periodo", "id_periodo",
            "valor_compras", "valor_compras", "valor_pagado", "valor_pagado", "saldo", "saldo");

    private static final String COLUMNAS_PAGO = """
            id_pago, id_proveedor, proveedor, id_periodo, id_periodo_liquidado, anio, mes, quincena, fecha_pago,
            monto, metodo_pago, referencia_pago, estado, motivo_anulacion, usuario_registro, fecha_registro""";
    private static final String COLUMNAS_PRECIO = """
            id_precio, id_proveedor, proveedor, id_insumo, codigo, insumo, unidad_medida, precio_unitario,
            vigente_desde, vigente, usuario_creacion, fecha_creacion""";

    private final SilaTemplate sila;
    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public CuentasProveedoresRepository(SilaTemplate sila, ConsultaPaginada paginada, JdbcClient jdbc) {
        this.sila = sila;
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    /** ADMIN. Afecta solo las compras futuras: las ya registradas conservan su valor. */
    public void fijarPrecio(long idProveedor, long idInsumo, BigDecimal precio, LocalDate desde) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_pagos_proveedor.sp_fijar_precio(?,?,?,?)}")) {
                s.setLong(1, idProveedor);
                s.setLong(2, idInsumo);
                s.setBigDecimal(3, precio);
                s.setDate(4, java.sql.Date.valueOf(desde));
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

    public Page<PrecioProveedor> precios(Long idProveedor, Long idInsumo, boolean soloVigentes,
                                         Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (idProveedor != null) f.cuando("id_proveedor = :idProveedor").param("idProveedor", idProveedor);
        if (idInsumo != null) f.cuando("id_insumo = :idInsumo").param("idInsumo", idInsumo);
        if (soloVigentes) f.cuando("vigente = 1");
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_PRECIOS, "vigente_desde,desc", "id_precio");
        return paginada.consultar(COLUMNAS_PRECIO, "vw_precios_proveedor", f, pag, PrecioProveedor.class);
    }

    public Page<SaldoProveedor> saldos(Boolean soloConSaldo, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (Boolean.TRUE.equals(soloConSaldo)) f.cuando("saldo > 0");
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_SALDOS, "saldo,desc", "id_proveedor");
        return paginada.consultar("id_proveedor, proveedor, activo, total_comprado, total_pagado, saldo, ultima_compra, ultimo_pago",
                "vw_saldo_proveedores", f, pag, SaldoProveedor.class);
    }

    public Page<ResumenPagoProveedor> resumen(Long idPeriodo, Integer anio, Long idProveedor,
                                              Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        if (idPeriodo != null) f.cuando("id_periodo = :idPeriodo").param("idPeriodo", idPeriodo);
        if (anio != null) f.cuando("anio = :anio").param("anio", anio);
        if (idProveedor != null) f.cuando("id_proveedor = :idProveedor").param("idProveedor", idProveedor);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_RESUMEN, "proveedor,asc", "id_proveedor");
        return paginada.consultar("id_periodo, anio, mes, quincena, id_proveedor, proveedor, numero_compras, valor_compras, valor_pagado, saldo",
                "vw_resumen_pagos_proveedores", f, pag, ResumenPagoProveedor.class);
    }
}
