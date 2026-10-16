package com.llanolat.sila.infra;

import jakarta.servlet.http.HttpServletRequest;

/** Datos del cliente de una peticion para las bitacoras (autenticacion y accesos a documentos). */
public final class Peticion {

    private Peticion() {}

    /** Direccion remota tal como la ve el servidor (detras del proxy ya viene resuelta por el contenedor). */
    public static String ip(HttpServletRequest req) {
        return req.getRemoteAddr();
    }

    /** Navegador del cliente, sin saltos de linea (la bitacora es de una linea por registro). */
    public static String agente(HttpServletRequest req) {
        String ua = req.getHeader("User-Agent");
        return ua == null ? null : ua.replaceAll("[\\r\\n]", " ");
    }
}
