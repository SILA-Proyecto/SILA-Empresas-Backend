package com.llanolat.sila.infra;

import java.util.Locale;
import java.util.Map;

/**
 * Parametros de paginacion y orden de una lista: page (base 0), size y
 * sort=campo,asc|desc.
 *
 * Los nombres de columna no se pueden enlazar como parametro SQL, asi que el
 * campo de orden SOLO se acepta si esta en la lista blanca de cada entidad
 * ({@code ordenables}); lo que llega del cliente nunca se concatena al SQL.
 * El desempate por id vuelve estable la paginacion: sin el, dos filas con el
 * mismo valor podrian repetirse o perderse entre paginas.
 */
public record Paginacion(int page, int size, String orderBy) {

    public static final int TAMANO_POR_DEFECTO = 20;
    public static final int TAMANO_MAXIMO = 100;

    /**
     * @param ordenables  nombre expuesto al cliente -> expresion SQL de la vista
     * @param porDefecto  orden si no viene sort, p. ej. "nombre,asc"
     * @param columnaId   expresion SQL del id, para el desempate
     */
    public static Paginacion de(Integer page, Integer size, String sort,
                                Map<String, String> ordenables, String porDefecto, String columnaId) {
        int p = page == null ? 0 : page;
        int s = size == null ? TAMANO_POR_DEFECTO : size;
        if (p < 0) {
            throw SilaException.parametroInvalido("page debe ser 0 o mayor.");
        }
        if (s < 1 || s > TAMANO_MAXIMO) {
            throw SilaException.parametroInvalido("size debe estar entre 1 y " + TAMANO_MAXIMO + ".");
        }

        String[] partes = (sort == null || sort.isBlank() ? porDefecto : sort).split(",", -1);
        String campo = partes[0].trim();
        String sentido = partes.length > 1 ? partes[1].trim().toLowerCase(Locale.ROOT) : "asc";
        String columna = ordenables.get(campo);
        if (partes.length > 2 || columna == null || !(sentido.equals("asc") || sentido.equals("desc"))) {
            throw SilaException.parametroInvalido(
                    "sort invalido. Use campo,asc o campo,desc con uno de: "
                  + String.join(", ", ordenables.keySet()) + ".");
        }

        String orderBy = " ORDER BY " + columna + " " + sentido.toUpperCase(Locale.ROOT)
                       + (columna.equals(columnaId) ? "" : ", " + columnaId + " ASC");
        return new Paginacion(p, s, orderBy);
    }

    public long offset() {
        return (long) page * size;
    }
}
