package com.llanolat.sila.notificaciones;

import java.time.LocalDate;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Campana del dashboard: /api/v1/notificaciones. Las alertas se CALCULAN al consultar (vw_notificaciones): no se guardan,
 * desaparecen solas cuando el problema se resuelve. "Marcar como leidas" es del cliente: guarda las `clave` vistas.
 * Cualquier usuario autenticado las ve (son solo lectura).
 */
@RestController
@RequestMapping("/api/v1/notificaciones")
public class NotificacionController {

    public record Notificacion(String clave, String tipo, String severidad, String titulo, String detalle,
                               String entidad, Long idEntidad, LocalDate fecha) {}

    public record Notificaciones(int total, int criticas, List<Notificacion> items) {}

    private final JdbcClient jdbc;

    public NotificacionController(JdbcClient jdbc) { this.jdbc = jdbc; }

    @GetMapping
    public Notificaciones listar() {
        List<Notificacion> items = jdbc.sql("""
                SELECT clave, tipo, severidad, titulo, detalle, entidad, id_entidad, fecha
                  FROM vw_notificaciones
                 ORDER BY CASE severidad WHEN 'CRITICA' THEN 0 ELSE 1 END, titulo
                 FETCH FIRST 100 ROWS ONLY""").query(Notificacion.class).list();
        int criticas = (int) items.stream().filter(n -> "CRITICA".equals(n.severidad())).count();
        return new Notificaciones(items.size(), criticas, items);
    }
}
