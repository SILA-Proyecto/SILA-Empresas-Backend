package com.llanolat.sila.seguridad;

import java.time.Duration;
import java.util.ArrayDeque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import org.springframework.stereotype.Component;

/**
 * Limite de frecuencia en memoria (ventana deslizante) para frenar la fuerza bruta antes
 * de gastar BCrypt o tocar la base. Complementa el bloqueo por usuario de la base.
 * Con varios servidores backend habria que moverlo a un almacen compartido; hoy hay uno.
 *
 * El mapa tiene tope: al llegar a MAX_CLAVES se barren las claves vencidas (como mucho una vez
 * por segundo) y, si sigue lleno, las claves NUEVAS se rechazan (falla cerrado) en vez de crecer
 * sin limite. Toda lectura y escritura de una clave es atomica (compute).
 */
@Component
public class LimiteTasa {

    private static final int MAX_CLAVES = 20_000;
    private static final long INTERVALO_BARRIDO = Duration.ofSeconds(1).toNanos();

    private static final class Cola {
        final ArrayDeque<Long> instantes = new ArrayDeque<>();
        long ventana;
    }

    private final Map<String, Cola> eventos = new ConcurrentHashMap<>();
    private final AtomicInteger claves = new AtomicInteger();
    private final AtomicLong ultimoBarrido = new AtomicLong(System.nanoTime() - INTERVALO_BARRIDO);

    /** true si la accion esta permitida y la registra; false si ya se supero el limite. */
    public boolean permitir(String clave, int maximo, Duration ventana) {
        for (int intento = 0; intento < 2; intento++) {
            long ahora = System.nanoTime();
            boolean[] estado = {false, false};   // [permitido, sin cupo para una clave nueva]
            eventos.compute(clave, (k, cola) -> {
                if (cola == null) {
                    if (!reservar()) {
                        estado[1] = true;
                        return null;
                    }
                    cola = new Cola();
                }
                cola.ventana = ventana.toNanos();
                depurar(cola, ahora);
                if (cola.instantes.size() < maximo) {
                    cola.instantes.addLast(ahora);
                    estado[0] = true;
                }
                return cola;
            });
            if (!estado[1]) {
                return estado[0];
            }
            barrer(ahora);   // lleno: liberar vencidas y reintentar una vez
        }
        return false;
    }

    /** Reserva un lugar para una clave nueva de forma atomica: el tope no se rebasa ni con concurrencia. */
    private boolean reservar() {
        if (claves.incrementAndGet() > MAX_CLAVES) {
            claves.decrementAndGet();
            return false;
        }
        return true;
    }

    private void barrer(long ahora) {
        long previo = ultimoBarrido.get();
        if (ahora - previo < INTERVALO_BARRIDO || !ultimoBarrido.compareAndSet(previo, ahora)) {
            return;
        }
        for (String k : eventos.keySet()) {
            eventos.computeIfPresent(k, (key, cola) -> {
                depurar(cola, ahora);
                if (cola.instantes.isEmpty()) {
                    claves.decrementAndGet();
                    return null;
                }
                return cola;
            });
        }
    }

    /** Quita los instantes fuera de la ventana. Se compara por diferencia: nanoTime puede desbordar. */
    private static void depurar(Cola cola, long ahora) {
        while (!cola.instantes.isEmpty() && ahora - cola.instantes.peekFirst() > cola.ventana) {
            cola.instantes.pollFirst();
        }
    }
}
