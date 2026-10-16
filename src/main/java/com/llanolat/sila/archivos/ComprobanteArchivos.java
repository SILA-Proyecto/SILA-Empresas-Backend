package com.llanolat.sila.archivos;

import com.llanolat.sila.archivos.Archivos.Archivo;
import com.llanolat.sila.archivos.GeneradorPdf.Anulacion;
import com.llanolat.sila.comprobantes.ComprobanteRepository;
import com.llanolat.sila.comprobantes.Comprobantes.Detalle;
import com.llanolat.sila.infra.Fechas;
import com.llanolat.sila.infra.Identidad;
import java.time.LocalDateTime;
import java.time.ZonedDateTime;
import java.util.List;
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

    /** Repone los PDF que faltan (movimientos desde la fecha de corte). Sin fecha de corte no hace nada. */
    @Scheduled(initialDelayString = "PT1M", fixedDelayString = "PT2M")
    public void reintentar() {
        if (props.fechaCorte() == null) {
            return;
        }
        try {
            List<String[]> faltan = repo.sinPdf(props.fechaCorte(), LOTE);
            for (String[] f : faltan) {
                String version = f[2];
                try {
                    generar(props.usuarioSistema(), f[0], Long.parseLong(f[1]), version,
                            "ANULADO".equals(version) ? new Anulacion(null, null, null) : null);
                } catch (RuntimeException e) {
                    log.warn("Reintento de PDF fallido para {} #{} ({}).", f[0], f[1], version, e);
                }
            }
            if (!faltan.isEmpty()) {
                log.info("Reintento de PDF: {} comprobante(s) revisados.", faltan.size());
            }
        } catch (RuntimeException e) {
            log.warn("No se pudo revisar los comprobantes sin PDF.", e);
        }
    }

    /** @return true si se creo el PDF; false si ya existia. @param sistema usuario de sistema o null (peticion actual) */
    boolean generar(String sistema, String tipo, long id, String version, Anulacion anulacion) {
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
