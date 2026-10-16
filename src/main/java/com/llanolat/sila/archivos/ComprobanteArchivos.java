package com.llanolat.sila.archivos;

import com.llanolat.sila.archivos.Archivos.Archivo;
import com.llanolat.sila.archivos.GeneradorPdf.Anulacion;
import com.llanolat.sila.comprobantes.ComprobanteRepository;
import com.llanolat.sila.comprobantes.Comprobantes.Detalle;
import com.llanolat.sila.infra.Fechas;
import com.llanolat.sila.infra.Identidad;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZonedDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * PDF de los comprobantes. {@link #alRegistrar} y {@link #alAnular} se llaman justo despues de confirmar el movimiento,
 * dentro de la misma peticion: el PDF se genera UNA vez y se congela. Nunca lanzan: si algo falla, el movimiento ya
 * esta guardado y el PDF lo repone {@link #reintentar} (solo para movimientos desde la fecha de corte).
 *
 * Al anular, el PDF original NO se toca: se agrega un segundo PDF con la marca de agua «ANULADO».
 *
 * Fecha de corte del reintento: la configurada (SILA_DOCS_FECHA_CORTE) o, si no hay, la del movimiento mas antiguo que ya
 * tiene PDF o, si todavia no hay ninguno, el dia en que arranco el sistema. Asi un PDF que fallo al registrar se repone
 * siempre, sin generar «originales» retroactivos de lo anterior a la funcion.
 */
@Service
public class ComprobanteArchivos {

    private static final Logger log = LoggerFactory.getLogger(ComprobanteArchivos.class);
    private static final int LOTE = 50;

    private final ComprobanteRepository comprobantes;
    private final ArchivoRepository repo;
    private final GeneradorPdf generador;
    private final CifradoDocs cifrado;
    private final AlmacenArchivos almacen;
    private final ArchivosProps props;
    private final ObjectProvider<Identidad> identidad;
    private final LocalDate arranque = LocalDate.now(Fechas.COLOMBIA);
    /** Comprobantes cuyo PDF se esta generando ahora: evita que la peticion y el reintento lo hagan a la vez. */
    private final Set<String> enCurso = ConcurrentHashMap.newKeySet();
    private final Map<String, Integer> fallos = new ConcurrentHashMap<>();
    private final Map<String, Instant> proximo = new ConcurrentHashMap<>();

    public ComprobanteArchivos(ComprobanteRepository comprobantes, ArchivoRepository repo, GeneradorPdf generador,
                               CifradoDocs cifrado, AlmacenArchivos almacen, ArchivosProps props,
                               ObjectProvider<Identidad> identidad) {
        this.comprobantes = comprobantes;
        this.repo = repo;
        this.generador = generador;
        this.cifrado = cifrado;
        this.almacen = almacen;
        this.props = props;
        this.identidad = identidad;
    }

    /** Tipos: VENTA, ABONO (id = id_recibo), PAGO_LECHERO, COMPRA_INSUMO, GASTO. */
    public void alRegistrar(String tipo, long id) {
        try {
            generar(null, tipo, id, "ORIGINAL", null);
        } catch (RuntimeException e) {
            log.warn("No se pudo generar el PDF de {} #{}; el reintento automatico lo repondra.", tipo, id, e);
        }
    }

    public void alAnular(String tipo, long id) {
        try {
            String usuario = null;
            try {
                usuario = identidad.getObject().usuario();
            } catch (RuntimeException e) {
                // sin identidad de peticion: queda sin nombre
            }
            LocalDateTime ahora = LocalDateTime.now(Fechas.COLOMBIA);
            generar(null, tipo, id, "ANULADO", new Anulacion(null, usuario, ahora));
        } catch (RuntimeException e) {
            log.warn("No se pudo generar el PDF de anulacion de {} #{}; el reintento automatico lo repondra.", tipo, id, e);
        }
    }

    /** Repone los PDF que faltan (movimientos desde la fecha de corte). Los que fallan esperan cada vez mas (hasta 60 min). */
    @Scheduled(initialDelayString = "PT1M", fixedDelayString = "PT2M")
    public void reintentar() {
        try {
            LocalDate corte = props.fechaCorte() != null ? props.fechaCorte() : repo.fechaPrimerPdf().orElse(arranque);
            Instant ahora = Instant.now();
            long enEspera = proximo.values().stream().filter(ahora::isBefore).count();
            List<String[]> faltan = repo.sinPdf(corte, (int) Math.min(1000, LOTE + enEspera));
            int intentados = 0;
            for (String[] f : faltan) {
                String version = f[2];
                String clave = f[0] + "|" + f[1] + "|" + version;
                if (Instant.now().isBefore(proximo.getOrDefault(clave, Instant.EPOCH))) continue;
                if (++intentados > LOTE) break;
                try {
                    generar(props.usuarioSistema(), f[0], Long.parseLong(f[1]), version,
                            "ANULADO".equals(version) ? new Anulacion(null, null, null) : null);
                    fallos.remove(clave);
                    proximo.remove(clave);
                } catch (RuntimeException e) {
                    int n = fallos.merge(clave, 1, Integer::sum);
                    proximo.put(clave, Instant.now().plusSeconds(120L * Math.min(30, 1L << Math.min(n - 1, 5))));
                    log.warn("Reintento de PDF fallido para {} #{} ({}), intento {}.", f[0], f[1], version, n, e);
                }
            }
            if (intentados > 0) {
                log.info("Reintento de PDF: {} comprobante(s) revisados.", intentados);
            }
        } catch (RuntimeException e) {
            log.warn("No se pudo revisar los comprobantes sin PDF.", e);
        }
    }

    /** @return true si se creo el PDF; false si ya existia. @param sistema usuario de sistema o null (peticion actual) */
    boolean generar(String sistema, String tipo, long id, String version, Anulacion anulacion) {
        String clave = tipo + "|" + id + "|" + version;
        if (!enCurso.add(clave)) {
            return false;                                   // otro hilo lo esta generando en este momento
        }
        try {
            return generarExclusivo(sistema, tipo, id, version, anulacion);
        } finally {
            enCurso.remove(clave);
        }
    }

    private boolean generarExclusivo(String sistema, String tipo, long id, String version, Anulacion anulacion) {
        List<Archivo> existentes = repo.deComprobante(tipo, id);
        if (existentes.stream().anyMatch(a -> version.equals(a.version()))) {
            return false;
        }
        if ("ANULADO".equals(version) && existentes.stream().noneMatch(a -> "ORIGINAL".equals(a.version()))) {
            log.debug("{} #{} se anulo sin PDF original (es anterior a la funcion de archivos): sin PDF de anulacion.", tipo, id);
            return false;
        }
        Detalle detalle = comprobantes.detalle(tipo, id);
        Anulacion anul = anulacion == null ? null
                : new Anulacion(detalle.comprobante().motivoAnulacion(), anulacion.usuario(), anulacion.cuando());
        byte[] pdf = generador.generar(detalle, anul, ZonedDateTime.now(Fechas.COLOMBIA));
        String ruta = cifrado.nuevaRuta();
        almacen.guardar(ruta, cifrado.cifrar(pdf, ruta));
        try {
            repo.registrarComprobante(sistema, tipo, id, version,
                    tipo + "-" + id + ("ANULADO".equals(version) ? "-ANULADO" : "") + ".pdf", ruta, pdf.length, Sha256.hex(pdf));
        } catch (RuntimeException e) {
            almacen.descartar(ruta);
            throw e;
        }
        return true;
    }
}
