package com.llanolat.sila.archivos;

import com.llanolat.sila.archivos.Archivos.DriveAutorizacion;
import com.llanolat.sila.archivos.Archivos.DriveEstado;
import com.llanolat.sila.infra.Identidad;
import com.llanolat.sila.infra.SilaException;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Conexion con Google Drive: /api/v1/archivos/drive. Todo es ADMIN salvo /callback, que es a donde vuelve Google: no
 * lleva token de sesion, y se protege con el parametro "state" firmado (un solo uso, 10 minutos) que genera /autorizar.
 */
@RestController
@RequestMapping("/api/v1/archivos/drive")
public class DriveController {

    private static final Logger log = LoggerFactory.getLogger(DriveController.class);

    private final DriveCliente drive;
    private final DriveSincronizador sincronizador;
    private final ArchivosProps props;
    private final ObjectProvider<Identidad> identidad;

    public DriveController(DriveCliente drive, DriveSincronizador sincronizador, ArchivosProps props, ObjectProvider<Identidad> identidad) {
        this.drive = drive;
        this.sincronizador = sincronizador;
        this.props = props;
        this.identidad = identidad;
    }

    @GetMapping("/estado")
    public DriveEstado estado() { return sincronizador.estado(); }

    /** Devuelve la URL de Google a la que el dashboard manda al ADMIN para autorizar con la cuenta de la empresa. */
    @GetMapping("/autorizar")
    public DriveAutorizacion autorizar() {
        return new DriveAutorizacion(drive.urlAutorizacion(identidad.getObject().usuario()));
    }

    /**
     * A donde vuelve Google. Si hay {@code sila.archivos.drive.retorno}, redirige al dashboard con ?drive=ok o
     * ?drive=error; si no, responde un texto simple.
     */
    @GetMapping("/callback")
    public void callback(@RequestParam(required = false) String code, @RequestParam(required = false) String state,
                         @RequestParam(required = false) String error, HttpServletResponse res) throws IOException {
        String resultado = "ok";
        String mensaje = "Drive quedo conectado. Ya puede cerrar esta pestana.";
        if (error != null) {
            resultado = "error";
            mensaje = "No se conecto Drive: la autorizacion fue cancelada o rechazada.";
            log.info("Autorizacion de Drive rechazada por la persona (error={}).", error.replaceAll("[^A-Za-z0-9_ -]", ""));
        } else {
            try {
                drive.completar(code, state);
            } catch (SilaException e) {
                resultado = "error";
                mensaje = "No se conecto Drive: " + e.getMessage();
                log.warn("No se pudo completar la conexion de Drive: {}", e.getMessage());
            }
        }
        String retorno = props.drive().retorno();
        if (retorno != null && !retorno.isBlank()) {
            res.sendRedirect(retorno + (retorno.contains("?") ? "&" : "?") + "drive=" + resultado);
            return;
        }
        res.setStatus(resultado.equals("ok") ? 200 : 400);
        res.setContentType("text/plain;charset=UTF-8");
        res.getWriter().write(mensaje);
    }

    /** Envia ahora lo pendiente (ignora la espera de los que fallaron). Devuelve el estado. */
    @PostMapping("/sincronizar")
    public DriveEstado sincronizar() {
        sincronizador.sincronizar(true);
        return sincronizador.estado();
    }

    /** Borra el acceso guardado a Drive. Lo ya subido queda en Drive; la cola vuelve a esperar una conexion. */
    @PostMapping("/desconectar")
    public DriveEstado desconectar() {
        drive.desconectar();
        return sincronizador.estado();
    }
}
