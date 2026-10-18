package com.llanolat.sila.asistente;

import com.llanolat.sila.infra.Fechas;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.seguridad.AccesoRegistrador;
import com.llanolat.sila.seguridad.LimiteTasa;
import com.llanolat.sila.seguridad.TokenService;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * Pasa la pregunta del usuario al flujo de n8n. n8n nunca recibe la sesion del usuario: recibe un token de SOLO LECTURA,
 * de corta vida y con el mismo usuario y rol (ver AlcanceLecturaFilter), de modo que el asistente ve exactamente lo que
 * esa persona ve en el dashboard y no puede escribir nada. Las preguntas quedan en la bitacora de accesos.
 */
@Service
public class AsistenteService {

    private static final Logger log = LoggerFactory.getLogger(AsistenteService.class);
    private static final int MAX_RESPUESTA = 8000;
    private static final String[] CAMPOS_RESPUESTA = {"respuesta", "output", "text"};

    private final AsistenteProps props;
    private final TokenService tokens;
    private final LimiteTasa limite;
    private final AccesoRegistrador accesos;
    private final JsonMapper json;
    // HTTP/1.1 a la fuerza: por defecto Java intenta subir a HTTP/2 (Upgrade: h2c) y n8n/Node se queda sin responder.
    private final HttpClient http = HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1)
            .connectTimeout(Duration.ofSeconds(5)).build();

    public AsistenteService(AsistenteProps props, TokenService tokens, LimiteTasa limite,
                            AccesoRegistrador accesos, JsonMapper json) {
        this.props = props;
        this.tokens = tokens;
        this.limite = limite;
        this.accesos = accesos;
        this.json = json;
    }

    public String preguntar(Jwt jwt, String mensaje, String sesionId, String ip, String userAgent) {
        if (!props.habilitado()) {
            throw SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE, "El asistente no esta habilitado.");
        }
        String usuario = jwt.getSubject();
        if (!limite.permitir("asistente:" + usuario, props.limitePorHora(), Duration.ofHours(1))) {
            throw SilaException.de(SilaException.DEMASIADOS_INTENTOS,
                    "Ha hecho muchas preguntas seguidas. Intente de nuevo en un rato.");
        }
        accesos.registrar(usuario, "ASISTENTE_PREGUNTA", ip, userAgent, mensaje);

        Map<String, Object> cuerpo = new LinkedHashMap<>();
        cuerpo.put("mensaje", mensaje);
        // La memoria del agente en n8n se indexa por esta clave: atada al usuario, nadie puede leer la conversacion de otro.
        cuerpo.put("sesion_id", usuario + ":" + sesionId);
        cuerpo.put("usuario", usuario);
        cuerpo.put("rol", jwt.getClaimAsString("rol"));
        cuerpo.put("hoy", Fechas.hoy().toString());
        cuerpo.put("base_url", props.baseUrl());
        cuerpo.put("token", tokens.emitirLectura(((Number) jwt.getClaim("uid")).longValue(), usuario,
                jwt.getClaimAsString("rol"), jwt.getClaimAsString("sid"), props.tokenTtl()));

        try {
            HttpRequest req = HttpRequest.newBuilder(URI.create(props.url()))
                    .timeout(props.timeout())
                    .header("Content-Type", "application/json")
                    .header("X-Sila-Secreto", props.secreto())
                    .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(cuerpo), StandardCharsets.UTF_8))
                    .build();
            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (res.statusCode() / 100 != 2) {
                log.warn("asistente: n8n respondio {}", res.statusCode());
                throw noDisponible();
            }
            return extraer(res.body());
        } catch (IOException e) {
            log.warn("asistente: n8n no responde: {}", e.toString());
            throw noDisponible();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw noDisponible();
        }
    }

    private String extraer(String cuerpo) {
        JsonNode raiz = json.readTree(cuerpo);
        // n8n puede devolver un objeto o una lista de un objeto.
        JsonNode obj = raiz.isArray() && !raiz.isEmpty() ? raiz.get(0) : raiz;
        for (String campo : CAMPOS_RESPUESTA) {
            JsonNode v = obj.get(campo);
            if (v != null && v.isString() && !v.asString().isBlank()) {
                String t = v.asString().trim();
                return t.length() > MAX_RESPUESTA ? t.substring(0, MAX_RESPUESTA) : t;
            }
        }
        log.warn("asistente: la respuesta de n8n no trae texto");
        throw noDisponible();
    }

    private static SilaException noDisponible() {
        return SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE,
                "El asistente no esta disponible en este momento. Intente de nuevo en unos minutos.");
    }
}
