package com.llanolat.sila.periodos;

import static org.assertj.core.api.Assertions.assertThat;

import com.llanolat.sila.periodos.dto.PeriodoDto;
import com.llanolat.sila.tablero.Tablero.Quincena;
import java.math.BigDecimal;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;

/** Modulo RESULTADO_QUINCENA apagado: se quita SOLO el bloque del resultado y la caja neta; las cuentas siguen. */
class SinResultadoTest {

    private static BigDecimal n(int v) { return BigDecimal.valueOf(v); }

    @Test
    void laQuincenaPierdeElResultadoPeroConservaLasCuentas() {
        PeriodoDto p = new PeriodoDto(7L, 2026, 10, 2, LocalDate.of(2026, 10, 16), LocalDate.of(2026, 10, 31), "ABIERTA",
                n(1), n(2), n(3), n(4), n(5),
                n(6), n(7), n(8), n(9), n(10), n(11), n(12), n(13), n(14), n(15), n(16), n(17), n(18), n(19), n(20), n(21),
                n(22), n(23)).sinResultado();
        assertThat(p.idPeriodo()).isEqualTo(7L);
        assertThat(p.estado()).isEqualTo("ABIERTA");
        assertThat(p.ingresosVentas()).isNull();
        assertThat(p.costoProduccion()).isNull();
        assertThat(p.gastosOperativos()).isNull();
        assertThat(p.carteraCastigada()).isNull();
        assertThat(p.resultadoEstimado()).isNull();
        assertThat(p.cajaNeta()).isNull();
        assertThat(p.ivaVentas()).isEqualTo(n(6));
        assertThat(p.totalVendido()).isEqualTo(n(7));
        assertThat(p.totalCobrado()).isEqualTo(n(12));
        assertThat(p.porPagarProveedores()).isEqualTo(n(21));
        assertThat(p.pagosProveedoresCaja()).isEqualTo(n(22));
    }

    @Test
    void elTableroHaceLoMismo() {
        Quincena q = new Quincena(7L, 2026, 10, 2, LocalDate.of(2026, 10, 16), LocalDate.of(2026, 10, 31), "ABIERTA",
                n(1), n(2), n(3), n(4), n(5), n(6), n(7), n(8), n(9), n(10)).sinResultado();
        assertThat(q.ingresosVentas()).isNull();
        assertThat(q.costoProduccion()).isNull();
        assertThat(q.gastosOperativos()).isNull();
        assertThat(q.carteraCastigada()).isNull();
        assertThat(q.resultadoEstimado()).isNull();
        assertThat(q.cajaNeta()).isNull();
        assertThat(q.totalVendido()).isEqualTo(n(2));
        assertThat(q.totalCobrado()).isEqualTo(n(3));
        assertThat(q.lecheLitros()).isEqualTo(n(9));
        assertThat(q.porPagarProveedores()).isEqualTo(n(10));
    }
}
