package com.llanolat.sila.consultas.repository;

import com.llanolat.sila.consultas.dto.CategoriasGastoDto;
import com.llanolat.sila.consultas.dto.DocumentosPendientesCargaDto;
import com.llanolat.sila.consultas.dto.GastosPorCategoriaDto;
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
