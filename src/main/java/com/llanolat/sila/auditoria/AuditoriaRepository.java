package com.llanolat.sila.auditoria;

import com.llanolat.sila.auditoria.AuditoriaDtos.CambioAuditoria;
import com.llanolat.sila.auditoria.AuditoriaDtos.ErrorSistema;
import com.llanolat.sila.auditoria.AuditoriaDtos.EventoAcceso;
import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import java.time.LocalDate;
import java.util.Map;
import org.springframework.stereotype.Repository;

/** LECTURA de la auditoria (solo vistas, solo ADMIN). Las fechas del filtro son dias en UTC (hora de la base). */
@Repository
class AuditoriaRepository {

    private static final Map<String, String> ORDEN_ACCESOS = Map.of(
            "id_evento", "id_evento", "fecha", "fecha", "usuario", "usuario", "evento", "evento", "ip", "ip");
    private static final Map<String, String> ORDEN_CAMBIOS = Map.of(
            "id_auditoria", "id_auditoria", "fecha", "fecha", "usuario", "usuario", "tabla", "tabla", "columna", "columna");
    private static final Map<String, String> ORDEN_ERRORES = Map.of(
            "id_log", "id_log", "fecha", "fecha", "usuario", "usuario", "unidad", "unidad", "codigo_error", "codigo_error");

    private final ConsultaPaginada paginada;

    AuditoriaRepository(ConsultaPaginada paginada) { this.paginada = paginada; }

    Page<EventoAcceso> accesos(String usuario, String evento, String ip, LocalDate desde, LocalDate hasta,
                               Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        contiene(f, "usuario", "usuario", usuario);
        igual(f, "evento", "evento", evento == null ? null : evento.trim().toUpperCase());
        igual(f, "ip", "ip", ip);
        rango(f, desde, hasta);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_ACCESOS, "fecha,desc", "id_evento");
        return paginada.consultar("id_evento, fecha, usuario, evento, ip, user_agent, detalle",
                "vw_eventos_acceso", f, pag, EventoAcceso.class);
    }

    Page<CambioAuditoria> cambios(String usuario, String tabla, String columna, LocalDate desde, LocalDate hasta,
                                  Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        contiene(f, "usuario", "usuario", usuario);
        igual(f, "tabla", "tabla", tabla == null ? null : tabla.trim().toUpperCase());
        igual(f, "columna", "columna", columna == null ? null : columna.trim().toUpperCase());
        rango(f, desde, hasta);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_CAMBIOS, "fecha,desc", "id_auditoria");
        return paginada.consultar("id_auditoria, fecha, usuario, tabla, id_registro, columna, valor_anterior, valor_nuevo",
                "vw_auditoria_cambios", f, pag, CambioAuditoria.class);
    }

    Page<ErrorSistema> errores(String usuario, String unidad, Integer codigo, LocalDate desde, LocalDate hasta,
                               Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        contiene(f, "usuario", "usuario", usuario);
        contiene(f, "unidad", "unidad", unidad);
        if (codigo != null) {
            f.cuando("codigo_error = :codigo").param("codigo", codigo);
        }
        rango(f, desde, hasta);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_ERRORES, "fecha,desc", "id_log");
        return paginada.consultar("id_log, fecha, usuario, unidad, codigo_error, mensaje, contexto",
                "vw_log_errores", f, pag, ErrorSistema.class);
    }

    // Los nombres de columna son constantes del backend; solo los VALORES vienen del cliente y van como parametros.
    private static void contiene(Filtro f, String columna, String param, String valor) {
        if (valor != null && !valor.isBlank()) {
            f.cuando("LOWER(" + columna + ") LIKE '%' || LOWER(:" + param + ") || '%'").param(param, valor.trim());
        }
    }

    private static void igual(Filtro f, String columna, String param, String valor) {
        if (valor != null && !valor.isBlank()) {
            f.cuando(columna + " = :" + param).param(param, valor.trim());
        }
    }

    private static void rango(Filtro f, LocalDate desde, LocalDate hasta) {
        if (desde != null) {
            f.cuando("fecha >= :f_desde").param("f_desde", desde.atStartOfDay());
        }
        if (hasta != null) {
            f.cuando("fecha < :f_hasta").param("f_hasta", hasta.plusDays(1).atStartOfDay());
        }
    }
}
