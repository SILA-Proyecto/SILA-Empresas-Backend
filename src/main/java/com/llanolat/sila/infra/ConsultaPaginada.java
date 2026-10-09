package com.llanolat.sila.infra;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * Lee una pagina de una vista: una consulta para el total y otra para las
 * filas. Solo lee vistas (LLANOLAT_APP no puede leer tablas) y no necesita
 * sesion de aplicacion.
 */
@Component
public class ConsultaPaginada {

    /** Condiciones AND y sus parametros nombrados. Las condiciones son SQL fijo del backend, nunca texto del cliente. */
    public static final class Filtro {
        private final List<String> condiciones = new ArrayList<>();
        private final Map<String, Object> parametros = new HashMap<>();

        public Filtro cuando(String condicion) {
            condiciones.add(condicion);
            return this;
        }

        public Filtro param(String nombre, Object valor) {
            // :desde y :tamano son de la paginacion (OFFSET / FETCH): un filtro con ese nombre la pisaria en silencio.
            if (nombre.equals("desde") || nombre.equals("tamano")) {
                throw new IllegalArgumentException("Nombre de parametro reservado por la paginacion: " + nombre);
            }
            parametros.put(nombre, valor);
            return this;
        }

        String where() {
            return condiciones.isEmpty() ? "" : " WHERE " + String.join(" AND ", condiciones);
        }

        Map<String, Object> parametros() {
            return parametros;
        }
    }

    private final JdbcClient jdbc;

    public ConsultaPaginada(JdbcClient jdbc) { this.jdbc = jdbc; }

    public <T> Page<T> consultar(String columnas, String vista, Filtro filtro,
                                 Paginacion pag, Class<T> tipo) {
        String where = filtro.where();

        long total = jdbc.sql("SELECT COUNT(*) FROM " + vista + where)
                         .params(filtro.parametros())
                         .query(Long.class)
                         .single();

        Map<String, Object> params = new HashMap<>(filtro.parametros());
        params.put("desde", pag.offset());
        params.put("tamano", pag.size());
        List<T> items = jdbc.sql("SELECT " + columnas + " FROM " + vista + where + pag.orderBy()
                                + " OFFSET :desde ROWS FETCH NEXT :tamano ROWS ONLY")
                            .params(params)
                            .query(tipo)
                            .list();

        return new Page<>(items, total, pag.page(), pag.size());
    }
}
