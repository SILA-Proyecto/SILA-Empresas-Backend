package com.llanolat.sila.empresa;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import org.springframework.http.server.PathContainer;
import org.springframework.web.util.pattern.PathPattern;
import org.springframework.web.util.pattern.PathPatternParser;

/**
 * UN SOLO LUGAR que decide a que modulo pertenece cada ruta. La primera regla que coincide manda; una regla con
 * modulo {@code null} deja la ruta en el nucleo (siempre activa). Lo que no esta aqui es del nucleo.
 * Al agregar un endpoint de un modulo opcional, se agrega aqui (y se documenta en docs/CONTRATO_EMPRESA.md).
 */
public final class MapaModulos {

    public static final String CREDITO = "CREDITO";
    public static final String PRECIOS_CLIENTE = "PRECIOS_CLIENTE";
    public static final String CALIDAD_LECHE = "CALIDAD_LECHE";
    public static final String MARGEN = "MARGEN";
    public static final String ARCHIVOS = "ARCHIVOS";
    public static final String ASISTENTE = "ASISTENTE";
    public static final String AUDITORIA = "AUDITORIA";
    public static final String PARAMETROS = "PARAMETROS";
    /** Sin rutas propias: /periodos y el tablero son del nucleo; con el modulo apagado omiten las cifras del resultado. */
    public static final String RESULTADO_QUINCENA = "RESULTADO_QUINCENA";

    /**
     * @param metodos null = cualquier metodo
     * @param modulo  null = nucleo (excepcion que deja la ruta abierta)
     * @param publica la ruta se puede llamar sin sesion (el filtro la bloquea igual cuando el modulo esta apagado)
     */
    public record Regla(Set<String> metodos, PathPattern patron, String modulo, boolean publica, String texto) {
        boolean coincide(String metodo, PathContainer ruta) {
            return (metodos == null || metodos.contains(metodo)) && patron.matches(ruta);
        }
    }

    private static final PathPatternParser P = new PathPatternParser();

    private static Regla r(Set<String> metodos, String patron, String modulo, boolean publica) {
        return new Regla(metodos, P.parse(patron), modulo, publica, patron);
    }

    private static final Set<String> GET = Set.of("GET");
    private static final Set<String> POST = Set.of("POST");
    private static final Set<String> PUT = Set.of("PUT");
    private static final String A = "/api/v1/archivos";

    public static final List<Regla> REGLAS = List.of(
            // ARCHIVOS: los PDF de comprobantes que genera la app son del nucleo (ver, opciones y descarga por id; el servicio
            // rechaza con 20020 los archivos subidos por el ADMIN cuando el modulo esta apagado).
            r(GET, A + "/comprobante/**", null, false),
            r(GET, A + "/{id:\\d+}", null, false),
            r(GET, A + "/{id:\\d+}/opciones-descarga", null, false),
            r(GET, A + "/{id:\\d+}/contenido", null, false),
            r(POST, A + "/{id:\\d+}/descarga", null, false),
            r(GET, A + "/drive/callback", ARCHIVOS, true),    // lo llama el navegador al volver de Google, sin sesion
            r(null, A + "/**", ARCHIVOS, false),              // lista, explorador, subir, carpetas, archivar, descifrar, accesos, Drive
            // CREDITO: ventas a credito (la base tambien se niega), cartera, abonos, castigos y edades
            r(null, "/api/v1/cartera/**", CREDITO, false),
            r(null, "/api/v1/precios-cliente/**", PRECIOS_CLIENTE, false),
            r(null, "/api/v1/acopio/**", CALIDAD_LECHE, false),
            r(null, "/api/v1/reportes/margen/**", MARGEN, false),
            r(null, "/api/v1/asistente/**", ASISTENTE, false),
            // AUDITORIA: solo la consulta del ADMIN; la auditoria sigue registrando con el modulo apagado
            r(null, "/api/v1/auditoria/**", AUDITORIA, false),
            // PARAMETROS: solo cambiarlos (la base tambien se niega); leerlos es del nucleo porque otras pantallas los usan
            r(PUT, "/api/v1/parametros/**", PARAMETROS, false));

    private MapaModulos() {}

    /** La regla que gobierna la ruta, si la hay (incluye las excepciones del nucleo). */
    public static Optional<Regla> de(String metodo, String uri) {
        PathContainer ruta = PathContainer.parsePath(uri);
        for (Regla r : REGLAS) {
            if (r.coincide(metodo, ruta)) return Optional.of(r);
        }
        return Optional.empty();
    }

    /** El modulo opcional al que pertenece la ruta, o vacio si es del nucleo. */
    public static Optional<String> moduloDe(String metodo, String uri) {
        return de(metodo, uri).map(Regla::modulo);
    }
}
