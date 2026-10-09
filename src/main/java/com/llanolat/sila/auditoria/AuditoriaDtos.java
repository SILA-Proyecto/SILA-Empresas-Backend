package com.llanolat.sila.auditoria;

import java.time.LocalDateTime;

/** Filas de las vistas de auditoria. Las marcas de tiempo vienen en UTC (hora de la base), sin zona. */
public final class AuditoriaDtos {

    public record EventoAcceso(Long idEvento, LocalDateTime fecha, String usuario, String evento,
                               String ip, String userAgent, String detalle) {}

    public record CambioAuditoria(Long idAuditoria, LocalDateTime fecha, String usuario, String tabla,
                                  String idRegistro, String columna, String valorAnterior, String valorNuevo) {}

    public record ErrorSistema(Long idLog, LocalDateTime fecha, String usuario, String unidad,
                               Integer codigoError, String mensaje, String contexto) {}

    private AuditoriaDtos() {}
}
