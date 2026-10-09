package com.llanolat.sila.seguridad;

import java.time.Duration;
import java.util.ArrayDeque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/**
 * Limite de frecuencia en memoria (ventana deslizante) para frenar la fuerza bruta antes
 * de gastar BCrypt o tocar la base. Complementa el bloqueo por usuario de la base.
 * Con varios servidores backend habria que moverlo a un almacen compartido; hoy hay uno.
 */
@Component
public class LimiteTasa {

    private static final int MAX_CLAVES = 20_000;
    private final Map<String, ArrayDeque<Long>> eventos = new ConcurrentHashMap<>();

    /** true si la accion esta permitida y la registra; false si ya se supero el limite. */
    public boolean permitir(String clave, int maximo, Duration ventana) {
        long ahora = System.nanoTime();
        long desde = ahora - ventana.toNanos();
        if (eventos.size() > MAX_CLAVES) {
            eventos.entrySet().removeIf(e -> {
                synchronized (e.getValue()) {
                    return e.getValue().isEmpty() || e.getValue().peekLast() < desde;
                }
            });
        }
        ArrayDeque<Long> cola = eventos.computeIfAbsent(clave, k -> new ArrayDeque<>());
        synchronized (cola) {
            while (!cola.isEmpty() && cola.peekFirst() < desde) {
                cola.pollFirst();
            }
            if (cola.size() >= maximo) {
                return false;
            }
            cola.addLast(ahora);
            return true;
        }
    }
}
