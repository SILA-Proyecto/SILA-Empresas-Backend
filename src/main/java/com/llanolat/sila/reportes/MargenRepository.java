package com.llanolat.sila.reportes;

import com.llanolat.sila.reportes.Margen.Fila;
import com.llanolat.sila.reportes.Margen.Totales;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Margen = ingreso de la venta (sin IVA) - cantidad x costo unitario del producto. El costo unitario es el PROMEDIO de lo
 * que costo producir el producto en todos sus lotes ({@code vw_margen_lineas}): es una aproximacion, no el costo del lote
 * exacto del que salio cada unidad. Solo lee la vista; las ventas anuladas no cuentan.
 */
@Repository
class MargenRepository {

    private static final int MAX_FILAS = 500;
    private static final String AGREGADOS = """
            SUM(cantidad) AS unidades, SUM(ingreso) AS ingreso, SUM(costo) AS costo, SUM(margen) AS margen,
            SUM(CASE WHEN costo IS NOT NULL THEN ingreso END) AS ingreso_con_costo,
            COUNT(CASE WHEN costo IS NULL THEN 1 END) AS lineas_sin_costo""";

    private final JdbcClient jdbc;

    MargenRepository(JdbcClient jdbc) { this.jdbc = jdbc; }

    List<Fila> porProducto(LocalDate desde, LocalDate hasta, String orden) {
        return jdbc.sql("SELECT id_producto AS id, MIN(producto) AS nombre, MIN(codigo_sku) AS sku, " + AGREGADOS
                        + " FROM vw_margen_lineas WHERE fecha_venta >= :desde AND fecha_venta <= :hasta"
                        + " GROUP BY id_producto ORDER BY " + orden + " FETCH FIRST " + MAX_FILAS + " ROWS ONLY")
                   .param("desde", desde).param("hasta", hasta).query(MargenRepository::fila).list();
    }

    List<Fila> porCliente(LocalDate desde, LocalDate hasta, String orden) {
        return jdbc.sql("SELECT id_cliente AS id, MIN(cliente) AS nombre, CAST(NULL AS VARCHAR2(1)) AS sku, " + AGREGADOS
                        + " FROM vw_margen_lineas WHERE fecha_venta >= :desde AND fecha_venta <= :hasta"
                        + " GROUP BY id_cliente ORDER BY " + orden + " FETCH FIRST " + MAX_FILAS + " ROWS ONLY")
                   .param("desde", desde).param("hasta", hasta).query(MargenRepository::fila).list();
    }

    Totales totales(LocalDate desde, LocalDate hasta) {
        return jdbc.sql("SELECT " + AGREGADOS + " FROM vw_margen_lineas WHERE fecha_venta >= :desde AND fecha_venta <= :hasta")
                   .param("desde", desde).param("hasta", hasta)
                   .query((rs, i) -> new Totales(cero(rs.getBigDecimal("ingreso")), cero(rs.getBigDecimal("costo")),
                           cero(rs.getBigDecimal("margen")), pct(rs.getBigDecimal("margen"), rs.getBigDecimal("ingreso_con_costo")),
                           rs.getLong("lineas_sin_costo")))
                   .single();
    }

    private static Fila fila(ResultSet rs, int i) throws SQLException {
        return new Fila(rs.getLong("id"), rs.getString("nombre"), rs.getString("sku"), cero(rs.getBigDecimal("unidades")),
                cero(rs.getBigDecimal("ingreso")), cero(rs.getBigDecimal("costo")), cero(rs.getBigDecimal("margen")),
                pct(rs.getBigDecimal("margen"), rs.getBigDecimal("ingreso_con_costo")), rs.getLong("lineas_sin_costo"));
    }

    private static BigDecimal cero(BigDecimal v) { return v == null ? BigDecimal.ZERO : v; }

    /** margen / ingreso de las lineas con costo, en %; null si no hay ingreso con costo conocido. */
    private static BigDecimal pct(BigDecimal margen, BigDecimal ingresoConCosto) {
        if (margen == null || ingresoConCosto == null || ingresoConCosto.signum() == 0) return null;
        return margen.multiply(BigDecimal.valueOf(100)).divide(ingresoConCosto, 2, RoundingMode.HALF_UP);
    }
}
