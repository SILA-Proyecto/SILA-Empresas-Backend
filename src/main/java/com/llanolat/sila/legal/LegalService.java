package com.llanolat.sila.legal;

import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.legal.LegalRepository.Aceptacion;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Terminos y privacidad: cual version rige (LegalProps), si una persona esta al dia y como acepta.
 * "Al dia" = tiene aceptada la version VIGENTE de los DOS documentos. Quien no lo esta recibe 403 / 20022 en toda la API
 * salvo en las rutas de {@link LegalPendienteFilter}. Se recuerda 30 s por persona (no se consulta la base en cada peticion);
 * aceptar la invalida al instante. Si no se puede comprobar, falla CERRADO (el filtro responde 503, nunca deja pasar).
 */
@Service
public class LegalService {

    private static final Logger log = LoggerFactory.getLogger("sila.legal");

    public static final String TERMINOS = "TERMINOS";
    public static final String PRIVACIDAD = "PRIVACIDAD";
    public static final String MENSAJE_PENDIENTE = "Debe aceptar los términos y condiciones y la política de privacidad vigentes para continuar.";

    /** Lo que rige hoy para un documento. */
    public record Vigente(String documento, String version, LocalDate fecha) {}

    /** Lo que la persona dijo de un documento vigente. {@code fechaAceptacion}: null si aun no lo acepta. */
    public record EstadoDocumento(String documento, String version, LocalDate fecha, boolean aceptado, LocalDateTime fechaAceptacion) {}

    public record Estado(boolean alDia, List<EstadoDocumento> documentos) {}

    /** Lo que envia el cliente: el documento y la version que leyo. */
    public record Aceptado(String documento, String version) {}

    private record Entrada(boolean alDia, long expira) {}

    private static final long INTERVALO_LIMPIEZA = 60_000_000_000L;
    private static final int UMBRAL_LIMPIEZA = 1_000;

    private final LegalRepository repo;
    private final LegalProps props;
    private final long ttlNanos;
    private final Map<Long, Entrada> cache = new ConcurrentHashMap<>();
    private volatile long ultimaLimpieza = System.nanoTime();

    public LegalService(LegalRepository repo, LegalProps props) {
        this.repo = repo;
        this.props = props;
        this.ttlNanos = props.cacheTtl().toNanos();
    }

    /** Los dos documentos con la version que rige hoy, en orden fijo (TERMINOS, PRIVACIDAD). */
    public List<Vigente> vigentes() {
        return List.of(
                new Vigente(TERMINOS, props.documentos().terminos().version(), props.documentos().terminos().fecha()),
                new Vigente(PRIVACIDAD, props.documentos().privacidad().version(), props.documentos().privacidad().fecha()));
    }

    /** Estado detallado de una persona (siempre lee la base). */
    public Estado estado(long idUsuario) {
        return calcular(repo.deUsuario(idUsuario));
    }

    /** true si la persona tiene aceptada la version vigente de los dos documentos. Con cache; lanza si la base falla. */
    public boolean alDia(long idUsuario) {
        long ahora = System.nanoTime();
        Entrada e = cache.get(idUsuario);
        if (e == null || e.expira() < ahora) {
            e = new Entrada(estado(idUsuario).alDia(), ahora + ttlNanos);
            cache.put(idUsuario, e);
            limpiarVencidas(ahora);
        }
        return e.alDia();
    }

    /**
     * Acepta en nombre de la persona de la sesion. Exige LOS DOS documentos, una sola vez cada uno, en la version vigente:
     * 400 si faltan, sobran o se repiten; 409 / 20023 si alguna version ya no es la vigente (hay que volver a leer).
     * Idempotente: aceptar lo ya aceptado no cambia nada. Devuelve el estado resultante.
     */
    public Estado aceptar(long idUsuario, List<Aceptado> enviados, String ip, String userAgent) {
        List<Vigente> vigentes = vigentes();
        Set<String> esperados = vigentes.stream().map(Vigente::documento).collect(Collectors.toSet());
        Set<String> vistos = new HashSet<>();
        for (Aceptado a : enviados) {
            String doc = a.documento() == null ? "" : a.documento().toUpperCase();
            if (!esperados.contains(doc) || !vistos.add(doc)) {
                throw SilaException.parametroInvalido("Debe aceptar los dos documentos (TERMINOS y PRIVACIDAD), una sola vez cada uno.", "aceptaciones");
            }
        }
        if (vistos.size() != esperados.size()) {
            throw SilaException.parametroInvalido("Debe aceptar los dos documentos (TERMINOS y PRIVACIDAD), una sola vez cada uno.", "aceptaciones");
        }
        for (Vigente v : vigentes) {
            Optional<Aceptado> a = enviados.stream().filter(x -> v.documento().equalsIgnoreCase(x.documento())).findFirst();
            if (a.isEmpty() || !v.version().equals(a.get().version())) {
                throw SilaException.de(SilaException.VERSION_LEGAL_DESACTUALIZADA,
                        "Los documentos legales cambiaron. Vuelva a leerlos y acepte la versión vigente.");
            }
        }
        int nuevas = repo.aceptar(props.documentos().terminos().version(), props.documentos().privacidad().version(), ip, userAgent);
        cache.remove(idUsuario);
        log.info("legal aceptado uid={} nuevas={} terminos={} privacidad={}", idUsuario, nuevas,
                props.documentos().terminos().version(), props.documentos().privacidad().version());
        return estado(idUsuario);
    }

    /** Descarta lo recordado de una persona (pruebas). */
    public void invalidar(long idUsuario) { cache.remove(idUsuario); }

    private Estado calcular(List<Aceptacion> aceptadas) {
        List<EstadoDocumento> docs = vigentes().stream().map(v -> {
            Optional<Aceptacion> a = aceptadas.stream()
                    .filter(x -> x.documento().equals(v.documento()) && x.version().equals(v.version())).findFirst();
            return new EstadoDocumento(v.documento(), v.version(), v.fecha(), a.isPresent(), a.map(Aceptacion::fecha).orElse(null));
        }).toList();
        return new Estado(docs.stream().allMatch(EstadoDocumento::aceptado), docs);
    }

    /** Quita lo vencido (una persona que ya no vuelve no debe quedar para siempre en memoria). */
    private void limpiarVencidas(long ahora) {
        if (cache.size() < UMBRAL_LIMPIEZA || ahora - ultimaLimpieza < INTERVALO_LIMPIEZA) return;
        ultimaLimpieza = ahora;
        cache.values().removeIf(v -> v.expira() < ahora);
    }
}
