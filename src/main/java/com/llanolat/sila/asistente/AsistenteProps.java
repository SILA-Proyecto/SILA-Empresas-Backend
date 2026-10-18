package com.llanolat.sila.asistente;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Propiedades sila.asistente.*. El asistente (flujos de n8n) queda apagado mientras no haya url.
 *
 * @param url            webhook de n8n que recibe la pregunta (solo localhost; n8n no se expone a internet)
 * @param secreto        valor de la cabecera X-Sila-Secreto que n8n debe comprobar en el webhook
 * @param baseUrl        direccion del API que usaran las herramientas de n8n (vista desde n8n)
 * @param tokenTtl       vida del token de solo lectura que recibe n8n
 * @param timeout        espera maxima de la respuesta del agente
 * @param limitePorHora  preguntas por usuario y hora
 */
@ConfigurationProperties(prefix = "sila.asistente")
public record AsistenteProps(
        @DefaultValue("") String url,
        @DefaultValue("") String secreto,
        @DefaultValue("http://127.0.0.1:8080/api/v1") String baseUrl,
        @DefaultValue("5m") Duration tokenTtl,
        @DefaultValue("60s") Duration timeout,
        @DefaultValue("30") int limitePorHora
) {
    public boolean habilitado() {
        return url != null && !url.isBlank();
    }
}
