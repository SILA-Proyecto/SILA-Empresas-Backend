package com.llanolat.sila.infra.idempotencia;

import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * @param obligatoriaEn prefijos de ruta donde Idempotency-Key es OBLIGATORIA (las que mueven dinero o stock)
 * @param maxBytes      tamano maximo del cuerpo que se acepta bajo idempotencia
 */
@ConfigurationProperties(prefix = "sila.idempotencia")
public record IdempotenciaProps(
        @DefaultValue({"/api/v1/ventas", "/api/v1/cartera", "/api/v1/facturacion", "/api/v1/acopio", "/api/v1/produccion"}) List<String> obligatoriaEn,
        @DefaultValue("1048576") int maxBytes
) {}
