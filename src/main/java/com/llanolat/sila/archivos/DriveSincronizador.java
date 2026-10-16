package com.llanolat.sila.archivos;

import com.llanolat.sila.archivos.Archivos.DriveEstado;
import com.llanolat.sila.infra.SilaException;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Lleva a Drive los archivos pendientes de la cola (documentos_repositorio: PENDIENTE o ERROR), ya cifrados y con nombre
 * opaco. Corre sin usuario, con la identidad de sistema "sistema.drive". Si un archivo falla se anota el error en la base
 * y se reintenta con espera creciente (1, 2, 4... hasta 60 minutos); la cola nunca se pierde.
 */
@Component
public class DriveSincronizador {

    private static final Logger log = LoggerFactory.getLogger(DriveSincronizador.class);
    static final String SISTEMA = "sistema.drive";
    private static final int LOTE = 25;

    private final ArchivoRepository repo;
    private final DriveCliente drive;
    private final AlmacenArchivos almacen;
    private final Map<Long, Integer> fallos = new ConcurrentHashMap<>();
    private final Map<Long, Instant> proximo = new ConcurrentHashMap<>();

    public DriveSincronizador(ArchivoRepository repo, DriveCliente drive, AlmacenArchivos almacen) {
        this.repo = repo;
        this.drive = drive;
        this.almacen = almacen;
    }

    @Scheduled(initialDelayString = "PT30S", fixedDelayString = "${sila.archivos.drive.intervalo:PT1M}")
    public void programado() {
        if (drive.listo()) {
            try {
                sincronizar(false);
            } catch (RuntimeException e) {
                log.warn("Sincronizacion con Drive fallida: {}", e.getMessage());
            }
        }
    }

    /** @param forzar ignora la espera de los que fallaron (boton "Sincronizar ahora"). @return cuantos se subieron */
    public synchronized int sincronizar(boolean forzar) {
        if (!drive.listo()) {
            throw SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE, "Drive no esta conectado o Google rechazo el permiso.");
        }
        int subidos = 0;
        List<String[]> cola = repo.pendientesDrive(LOTE);
        for (String[] item : cola) {
            long id = Long.parseLong(item[0]);
            if (!forzar && Instant.now().isBefore(proximo.getOrDefault(id, Instant.EPOCH))) continue;
            try {
                byte[] cifrado = almacen.leer(item[1]);
                if (cifrado == null) throw new IllegalStateException("el archivo no esta en el disco del servidor");
                DriveCliente.Subido s = drive.subir(item[1] + ".sila", cifrado);
                repo.marcarSubido(SISTEMA, id, s.id(), s.enlace(), item[2]);
                fallos.remove(id);
                proximo.remove(id);
                subidos++;
            } catch (RuntimeException e) {
                int n = fallos.merge(id, 1, Integer::sum);
                proximo.put(id, Instant.now().plusSeconds(60L * Math.min(60, 1L << Math.min(n - 1, 6))));
                String mensaje = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
                drive.registrarError(mensaje);
                log.warn("No se pudo enviar el documento {} a Drive (intento {}): {}", id, n, mensaje);
                try {
                    repo.marcarErrorDrive(SISTEMA, id, mensaje);
                } catch (RuntimeException e2) {
                    log.warn("Tampoco se pudo anotar el error del documento {}.", id, e2);
                }
                if (!drive.listo()) break;   // Google revoco el permiso: no tiene sentido seguir con el resto
            }
        }
        if (subidos > 0) drive.limpiarError();
        drive.sincronizado();
        return subidos;
    }

    public DriveEstado estado() {
        long[] n = repo.conteoDrive();
        return new DriveEstado(drive.configurado(), drive.conectado(), drive.cuenta(), drive.nombreCarpeta(),
                n[0], n[1], n[2], drive.ultimoError(), drive.ultimaSincronizacion());
    }
}
