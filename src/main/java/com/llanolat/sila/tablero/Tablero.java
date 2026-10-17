package com.llanolat.sila.tablero;

import com.llanolat.sila.notificaciones.NotificacionController.Notificacion;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/**
 * Tablero (pantalla de inicio): un solo JSON armado con vistas que ya existen; no hay SQL propio en la base.
 * "Hoy" es el dia en Colombia. Las ventas ANULADAS no suman. {@code quincena} es null si hoy no cae en ningun periodo creado.
 */
public final class Tablero {

    public record Respuesta(LocalDate fecha, Hoy hoy, Quincena quincena, Cartera cartera, Inventario inventario,
                            Proveedores proveedores, Alertas alertas, List<VentaDia> ventasSemana) {}

    /** Ventas del dia y la caja del dia (ingresos y egresos que mueven caja, de vw_comprobantes). */
    public record Hoy(BigDecimal ventasTotal, Integer ventasCantidad, BigDecimal ventasContado, BigDecimal ventasCredito,
                      BigDecimal cajaIngresos, BigDecimal cajaEgresos, BigDecimal cajaNeta,
                      BigDecimal litrosRecibidos, BigDecimal litrosRechazados, Integer lotesProducidos) {}

    /** La quincena que contiene hoy, desde vw_cuentas_quincena (mismas cifras que /periodos). */
    public record Quincena(Long idPeriodo, Integer anio, Integer mes, Integer quincena, LocalDate fechaInicio, LocalDate fechaFin,
                           String estado, BigDecimal ingresosVentas, BigDecimal totalVendido, BigDecimal totalCobrado,
                           BigDecimal costoProduccion, BigDecimal gastosOperativos, BigDecimal carteraCastigada,
                           BigDecimal resultadoEstimado, BigDecimal cajaNeta, BigDecimal lecheLitros, BigDecimal porPagarProveedores) {}

    public record Cartera(BigDecimal saldoTotal, BigDecimal saldoVencido, Integer clientesConSaldo, Integer clientesEnMora) {}

    public record Inventario(BigDecimal valorProductos, Integer productosBajoMinimo, Integer productosAgotados,
                             BigDecimal valorInsumos, Integer insumosBajoMinimo, Integer lotesPorVencer) {}

    /** Saldo historico por pagar a los proveedores (vw_saldo_proveedores), no solo de la quincena. */
    public record Proveedores(BigDecimal saldoPorPagar, Integer proveedoresConSaldo) {}

    /** Las 5 primeras de vw_notificaciones (criticas primero); el total es el de la campana. */
    public record Alertas(Integer total, Integer criticas, List<Notificacion> principales) {}

    /** Un dia por fila, de hace 6 dias a hoy; los dias sin ventas vienen en 0. */
    public record VentaDia(LocalDate fecha, BigDecimal total, Integer cantidad) {}

    /** Fila plana de la consulta de indicadores (una sola ida a la base). */
    record Indicadores(BigDecimal ventasTotal, Integer ventasCantidad, BigDecimal ventasContado, BigDecimal ventasCredito,
                       BigDecimal cajaIngresos, BigDecimal cajaEgresos,
                       BigDecimal litrosRecibidos, BigDecimal litrosRechazados, Integer lotesProducidos,
                       BigDecimal carteraSaldo, BigDecimal carteraVencido, Integer clientesConSaldo, Integer clientesEnMora,
                       BigDecimal valorProductos, Integer productosBajoMinimo, Integer productosAgotados,
                       BigDecimal valorInsumos, Integer insumosBajoMinimo, Integer lotesPorVencer,
                       BigDecimal proveedoresSaldo, Integer proveedoresConSaldo,
                       Integer alertasTotal, Integer alertasCriticas) {}

    private Tablero() {}
}
