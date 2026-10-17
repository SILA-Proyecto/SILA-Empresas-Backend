package com.llanolat.sila.tablero;

import com.llanolat.sila.infra.Fechas;
import com.llanolat.sila.notificaciones.NotificacionController.Notificacion;
import com.llanolat.sila.tablero.Tablero.Alertas;
import com.llanolat.sila.tablero.Tablero.Cartera;
import com.llanolat.sila.tablero.Tablero.Hoy;
import com.llanolat.sila.tablero.Tablero.Indicadores;
import com.llanolat.sila.tablero.Tablero.Inventario;
import com.llanolat.sila.tablero.Tablero.Proveedores;
import com.llanolat.sila.tablero.Tablero.Quincena;
import com.llanolat.sila.tablero.Tablero.Respuesta;
import com.llanolat.sila.tablero.Tablero.VentaDia;
import java.time.LocalDate;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Tablero: /api/v1/tablero. Solo lectura, cualquier usuario autenticado (el OPERATIVO ve lo mismo que el ADMIN).
 * Lee vistas existentes: vw_ventas_consolidadas, vw_comprobantes, vw_compras_insumo, vw_lotes, vw_dashboard_cartera,
 * vw_inventario_valorizado, vw_productos, vw_insumos, vw_saldo_proveedores, vw_notificaciones y vw_cuentas_quincena.
 * Los indicadores salen en UNA consulta con subconsultas escalares; aparte van la quincena, las alertas y la serie.
 */
@RestController
@RequestMapping("/api/v1/tablero")
public class TableroController {

    private final JdbcClient jdbc;

    public TableroController(JdbcClient jdbc) { this.jdbc = jdbc; }

    @GetMapping
    public Respuesta tablero() {
        LocalDate hoy = Fechas.hoy();
        // fecha_venta guarda hora de Colombia: el dia es [hoy, manana)
        Indicadores i = jdbc.sql("""
                SELECT
                  (SELECT NVL(SUM(total_venta), 0) FROM vw_ventas_consolidadas
                    WHERE fecha_venta >= :hoy AND fecha_venta < :manana AND estado_pago <> 'ANULADA') AS ventas_total,
                  (SELECT COUNT(*) FROM vw_ventas_consolidadas
                    WHERE fecha_venta >= :hoy AND fecha_venta < :manana AND estado_pago <> 'ANULADA') AS ventas_cantidad,
                  (SELECT NVL(SUM(total_venta), 0) FROM vw_ventas_consolidadas
                    WHERE fecha_venta >= :hoy AND fecha_venta < :manana AND estado_pago <> 'ANULADA' AND tipo_venta = 'CONTADO') AS ventas_contado,
                  (SELECT NVL(SUM(total_venta), 0) FROM vw_ventas_consolidadas
                    WHERE fecha_venta >= :hoy AND fecha_venta < :manana AND estado_pago <> 'ANULADA' AND tipo_venta = 'CREDITO') AS ventas_credito,
                  (SELECT NVL(SUM(monto), 0) FROM vw_comprobantes
                    WHERE fecha = :hoy AND estado = 'VIGENTE' AND afecta_caja = 1 AND sentido = 'INGRESO') AS caja_ingresos,
                  (SELECT NVL(SUM(monto), 0) FROM vw_comprobantes
                    WHERE fecha = :hoy AND estado = 'VIGENTE' AND afecta_caja = 1 AND sentido = 'EGRESO') AS caja_egresos,
                  (SELECT NVL(SUM(CASE WHEN estado_calidad = 'APROBADO' THEN cantidad END), 0) FROM vw_compras_insumo
                    WHERE fecha = :hoy AND requiere_calidad = 1 AND estado = 'VIGENTE') AS litros_recibidos,
                  (SELECT NVL(SUM(CASE WHEN estado_calidad = 'RECHAZADO' THEN cantidad END), 0) FROM vw_compras_insumo
                    WHERE fecha = :hoy AND requiere_calidad = 1 AND estado = 'VIGENTE') AS litros_rechazados,
                  (SELECT COUNT(*) FROM vw_lotes WHERE fecha_produccion = :hoy) AS lotes_producidos,
                  (SELECT NVL(SUM(saldo_deudor), 0) FROM vw_dashboard_cartera) AS cartera_saldo,
                  (SELECT NVL(SUM(saldo_pendiente), 0) FROM vw_ventas_consolidadas
                    WHERE estado_pago = 'PENDIENTE' AND fecha_vencimiento < :hoy) AS cartera_vencido,
                  (SELECT COUNT(*) FROM vw_dashboard_cartera WHERE saldo_deudor > 0) AS clientes_con_saldo,
                  (SELECT COUNT(*) FROM vw_dashboard_cartera WHERE estado_credito = 'EN_MORA') AS clientes_en_mora,
                  (SELECT NVL(SUM(valor_venta_inventario), 0) FROM vw_inventario_valorizado) AS valor_productos,
                  (SELECT COUNT(*) FROM vw_productos WHERE activo = 1 AND bajo_minimo = 1) AS productos_bajo_minimo,
                  (SELECT COUNT(*) FROM vw_productos WHERE activo = 1 AND stock_actual <= 0) AS productos_agotados,
                  (SELECT NVL(SUM(valor_inventario), 0) FROM vw_insumos WHERE activo = 1) AS valor_insumos,
                  (SELECT COUNT(*) FROM vw_insumos WHERE activo = 1 AND bajo_minimo = 1) AS insumos_bajo_minimo,
                  (SELECT COUNT(*) FROM vw_lotes WHERE nivel_alerta IS NOT NULL AND dias_restantes >= 0) AS lotes_por_vencer,
                  (SELECT NVL(SUM(CASE WHEN saldo > 0 THEN saldo END), 0) FROM vw_saldo_proveedores) AS proveedores_saldo,
                  (SELECT COUNT(*) FROM vw_saldo_proveedores WHERE saldo > 0) AS proveedores_con_saldo,
                  (SELECT COUNT(*) FROM vw_notificaciones) AS alertas_total,
                  (SELECT COUNT(*) FROM vw_notificaciones WHERE severidad = 'CRITICA') AS alertas_criticas
                  FROM dual""")
                .param("hoy", hoy).param("manana", hoy.plusDays(1))
                .query(Indicadores.class).single();

        Quincena quincena = jdbc.sql("""
                SELECT id_periodo, anio, mes, quincena, fecha_inicio, fecha_fin, estado, ingresos_ventas, total_vendido,
                       total_cobrado, costo_produccion, gastos_operativos, cartera_castigada, resultado_estimado, caja_neta,
                       leche_litros, por_pagar_proveedores
                  FROM vw_cuentas_quincena
                 WHERE :hoy BETWEEN fecha_inicio AND fecha_fin""")
                .param("hoy", hoy).query(Quincena.class).optional().orElse(null);

        List<Notificacion> principales = jdbc.sql("""
                SELECT clave, tipo, severidad, titulo, detalle, entidad, id_entidad, fecha
                  FROM vw_notificaciones
                 ORDER BY CASE severidad WHEN 'CRITICA' THEN 0 ELSE 1 END, titulo
                 FETCH FIRST 5 ROWS ONLY""").query(Notificacion.class).list();

        List<VentaDia> serie = jdbc.sql("""
                SELECT d.fecha, NVL(SUM(v.total_venta), 0) AS total, COUNT(v.id_venta) AS cantidad
                  FROM (SELECT :desde + LEVEL - 1 AS fecha FROM dual CONNECT BY LEVEL <= 7) d
                  LEFT JOIN vw_ventas_consolidadas v
                    ON v.fecha_venta >= d.fecha AND v.fecha_venta < d.fecha + 1 AND v.estado_pago <> 'ANULADA'
                 GROUP BY d.fecha
                 ORDER BY d.fecha""")
                .param("desde", hoy.minusDays(6)).query(VentaDia.class).list();

        return new Respuesta(hoy,
                new Hoy(i.ventasTotal(), i.ventasCantidad(), i.ventasContado(), i.ventasCredito(),
                        i.cajaIngresos(), i.cajaEgresos(), i.cajaIngresos().subtract(i.cajaEgresos()),
                        i.litrosRecibidos(), i.litrosRechazados(), i.lotesProducidos()),
                quincena,
                new Cartera(i.carteraSaldo(), i.carteraVencido(), i.clientesConSaldo(), i.clientesEnMora()),
                new Inventario(i.valorProductos(), i.productosBajoMinimo(), i.productosAgotados(),
                        i.valorInsumos(), i.insumosBajoMinimo(), i.lotesPorVencer()),
                new Proveedores(i.proveedoresSaldo(), i.proveedoresConSaldo()),
                new Alertas(i.alertasTotal(), i.alertasCriticas(), principales),
                serie);
    }
}
