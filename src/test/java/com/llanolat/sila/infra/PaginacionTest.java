package com.llanolat.sila.infra;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.Map;
import org.junit.jupiter.api.Test;

class PaginacionTest {

    private static final Map<String, String> ORDENABLES =
            Map.of("nombre", "nombre", "stock", "stock_actual", "id_producto", "id_producto");

    private static Paginacion de(Integer page, Integer size, String sort) {
        return Paginacion.de(page, size, sort, ORDENABLES, "nombre,asc", "id_producto");
    }

    @Test
    void sinParametrosUsaPagina0TamanoPorDefectoYOrdenPorDefecto() {
        Paginacion p = de(null, null, null);
        assertThat(p.page()).isZero();
        assertThat(p.size()).isEqualTo(20);
        assertThat(p.orderBy()).isEqualTo(" ORDER BY nombre ASC, id_producto ASC");
        assertThat(p.offset()).isZero();
    }

    @Test
    void elOffsetEsPaginaPorTamano() {
        assertThat(de(3, 25, null).offset()).isEqualTo(75);
    }

    @Test
    void traduceElNombreExpuestoALaColumnaDeLaVista() {
        assertThat(de(0, 10, "stock,desc").orderBy()).isEqualTo(" ORDER BY stock_actual DESC, id_producto ASC");
    }

    @Test
    void ordenarPorElIdNoRepiteElDesempate() {
        assertThat(de(0, 10, "id_producto,desc").orderBy()).isEqualTo(" ORDER BY id_producto DESC");
    }

    @Test
    void elSentidoEsOpcionalYNoDistingueMayusculas() {
        assertThat(de(0, 10, "nombre").orderBy()).startsWith(" ORDER BY nombre ASC");
        assertThat(de(0, 10, "nombre,DESC").orderBy()).startsWith(" ORDER BY nombre DESC");
    }

    @Test
    void rechazaCamposFueraDeLaListaBlancaYNuncaLosConcatenaAlSql() {
        for (String malo : new String[] {
                "password,asc", "nombre;DROP TABLE productos,asc", "nombre desc", "1,asc",
                "nombre,asc,extra", "nombre,sideways", ",asc"}) {
            assertThatThrownBy(() -> de(0, 10, malo))
                    .as(malo)
                    .isInstanceOfSatisfying(SilaException.class,
                            e -> assertThat(e.getCodigo()).isEqualTo(SilaException.PARAMETRO_INVALIDO));
        }
    }

    @Test
    void rechazaPaginaNegativaYTamanosFueraDeRango() {
        assertThatThrownBy(() -> de(-1, 10, null)).isInstanceOf(SilaException.class);
        assertThatThrownBy(() -> de(0, 0, null)).isInstanceOf(SilaException.class);
        assertThatThrownBy(() -> de(0, 101, null)).isInstanceOf(SilaException.class);
        assertThat(de(0, 100, null).size()).isEqualTo(100);
    }
}
