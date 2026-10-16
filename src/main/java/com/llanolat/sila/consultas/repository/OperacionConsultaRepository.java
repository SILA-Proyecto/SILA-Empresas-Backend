package com.llanolat.sila.consultas.repository;

import com.llanolat.sila.consultas.dto.CategoriasGastoDto;
import com.llanolat.sila.consultas.dto.DocumentosPendientesCargaDto;
import com.llanolat.sila.consultas.dto.FacturasDto;
import com.llanolat.sila.consultas.dto.GastosPorCategoriaDto;
import com.llanolat.sila.consultas.dto.ResolucionesFacturacionDto;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Lectura de periodos, ventas, cartera e inventario.
 *
 * Todo el calculo (dias de mora, estado de credito, valor del inventario,
 * rendimiento de los lotes, resultado del periodo) lo hace la vista. Aqui no
 * se replica ni una regla: solo se filtra y se ordena.
 */
@Repository
public class OperacionConsultaRepository {

    private final JdbcClient jdbc;

    public OperacionConsultaRepository(JdbcClient jdbc) { this.jdbc = jdbc; }

    // ---------- facturacion ----------

    public List<FacturasDto> facturas(String estadoDian, Long idVenta) {
        var sql = new StringBuilder("""
                SELECT id_factura, id_venta, numero_factura, fecha_emision,
                       fecha_vencimiento, subtotal_base, total_iva, total_factura,
                       cufe, qr_code_url, estado_dian, usuario_emisor
                  FROM vw_facturas WHERE 1 = 1
                """);
        if (estadoDian != null && !estadoDian.isBlank()) sql.append(" AND estado_dian = :estado");
        if (idVenta != null) sql.append(" AND id_venta = :idVenta");
        sql.append(" ORDER BY fecha_emision DESC, id_factura DESC");

        var spec = jdbc.sql(sql.toString());
        if (estadoDian != null && !estadoDian.isBlank()) spec = spec.param("estado", estadoDian.toUpperCase());
        if (idVenta != null) spec = spec.param("idVenta", idVenta);
        return spec.query(FacturasDto.class).list();
    }

    public List<ResolucionesFacturacionDto> resoluciones(boolean soloActivas) {
        return jdbc.sql("""
                SELECT id_resolucion, tipo_documento, numero_resolucion, prefijo,
                       rango_desde, rango_hasta, consecutivo_actual, vigente_desde,
                       vigente_hasta, activa
                  FROM vw_resoluciones_facturacion
                """ + (soloActivas ? " WHERE activa = 1" : "")
                    + " ORDER BY tipo_documento, vigente_desde DESC")
                .query(ResolucionesFacturacionDto.class).list();
    }

    // ---------- finanzas ----------

    public List<CategoriasGastoDto> categoriasGasto(boolean soloActivas) {
        return jdbc.sql("""
                SELECT id_categoria, nombre, activo FROM vw_categorias_gasto
                """ + (soloActivas ? " WHERE activo = 1" : "") + " ORDER BY nombre")
                .query(CategoriasGastoDto.class).list();
    }

    public List<GastosPorCategoriaDto> gastosPorCategoria(Long idPeriodo) {
        var sql = """
                SELECT id_periodo, anio, mes, quincena, categoria, total_gastos
                  FROM vw_gastos_por_categoria
                """ + (idPeriodo != null ? " WHERE id_periodo = :idPeriodo" : "")
                    + " ORDER BY anio DESC, mes DESC, quincena DESC, total_gastos DESC";
        var spec = jdbc.sql(sql);
        if (idPeriodo != null) spec = spec.param("idPeriodo", idPeriodo);
        return spec.query(GastosPorCategoriaDto.class).list();
    }

    // ---------- documentos ----------

    public List<DocumentosPendientesCargaDto> documentosPendientes(String estado) {
        var sql = """
                SELECT id_documento, tipo_entidad, id_entidad, nombre_archivo, mime_type,
                       estado_carga, intentos, ultimo_error, fecha_registro
                  FROM vw_documentos_pendientes_carga
                """ + (estado != null && !estado.isBlank() ? " WHERE estado_carga = :estado" : "")
                    + " ORDER BY fecha_registro";
        var spec = jdbc.sql(sql);
        if (estado != null && !estado.isBlank()) spec = spec.param("estado", estado.toUpperCase());
        return spec.query(DocumentosPendientesCargaDto.class).list();
    }
}
