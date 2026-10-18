package com.llanolat.sila.asistente;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public final class AsistenteDtos {

    private AsistenteDtos() {}

    /** sesion_id lo genera el dashboard (un UUID por conversacion); el backend lo ata al usuario. */
    public record MensajeRequest(
            @NotBlank @Size(max = 1000) String mensaje,
            @NotBlank @Pattern(regexp = "[A-Za-z0-9-]{8,64}") String sesionId) {}

    public record Respuesta(String respuesta, String sesionId) {}
}
