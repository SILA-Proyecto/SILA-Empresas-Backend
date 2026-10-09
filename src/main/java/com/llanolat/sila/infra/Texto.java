package com.llanolat.sila.infra;


/**
 * Busqueda insensible a mayusculas, tildes y enes.
 *
 * Se usa TRANSLATE y no CONVERT(x,'US7ASCII'): CONVERT convierte la ene con
 * virgulilla en '?' en vez de 'n', asi que buscar "ordeno" no encontraria
 * "Ordeno" con virgulilla. Comprobado contra la base.
 *
 * Aplicar una funcion sobre la columna impide usar el indice. Con catalogos
 * de unos miles de filas es irrelevante; si crece, la solucion es un indice
 * basado en funcion sobre la misma expresion.
 */
public final class Texto {

    public static final String ACENTOS =
            "áéíóúÁÉÍÓÚñÑüÜ";
    public static final String SIN_ACENTOS = "aeiouAEIOUnNuU";

    /** Fragmento SQL que compara una columna con el parametro :q, sin acentos. */
    public static String comoSinAcentos(String columna) {
        return "UPPER(TRANSLATE(" + columna + ", :conAcento, :sinAcento)) "
             + "LIKE UPPER(TRANSLATE('%' || :q || '%', :conAcento, :sinAcento))";
    }

    private Texto() {}
}
