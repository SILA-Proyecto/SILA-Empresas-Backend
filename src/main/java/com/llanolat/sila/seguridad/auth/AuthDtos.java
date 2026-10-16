package com.llanolat.sila.seguridad.auth;

import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/** Cuerpos del API de autenticacion. El JSON es snake_case (clave_actual, access_token...). */
final class AuthDtos {

    record LoginRequest(
            @NotBlank @Size(max = 100) String usuario,
            @NotBlank @Size(max = 200) String clave) {}

    record CodigoRequest(
            @NotBlank @Pattern(regexp = "\\d{6}", message = "Debe ser el codigo de 6 digitos.") String codigo) {}

    record RespaldoRequest(
            @NotBlank @Size(max = 30) String codigoRespaldo) {}

    /** codigo: 6 digitos de la app de autenticacion, o un codigo de respaldo. */
    record RegenerarRespaldoRequest(
            @NotBlank @Size(max = 200) String claveActual,
            @NotBlank @Size(max = 30) String codigo) {}

    /** codigo: obligatorio con sesion abierta; no aplica al cambio obligatorio del primer ingreso. */
    record CambiarClaveRequest(
            @NotBlank @Size(max = 200) String claveActual,
            @NotBlank @Size(max = 200) String claveNueva,
            @Size(max = 30) String codigo) {}

    record ActualizarPerfilRequest(
            @NotBlank @Size(min = 3, max = 120) String nombre,
            @NotBlank @Size(max = 150) @Pattern(regexp = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", message = "Correo invalido.") String email,
            @NotBlank @Size(max = 30) String codigo) {}

    /** credencial: lo que devuelve navigator.credentials.create()/get(), en JSON (PublicKeyCredential.toJSON()). */
    record PasskeyRegistroRequest(
            @NotBlank @Size(max = 60) String nombre,
            @NotNull tools.jackson.databind.JsonNode credencial) {}

    record PasskeyVerificarRequest(
            @NotNull tools.jackson.databind.JsonNode credencial) {}

    /** codigo: 6 digitos de la app o un codigo de respaldo (registrar un dispositivo es una accion sensible). */
    record PasskeyOpcionesRequest(
            @NotBlank @Size(max = 30) String codigo) {}

    /** Quitar un dispositivo tambien es una accion sensible: pide el mismo codigo que al registrarlo. */
    record PasskeyQuitarRequest(
            @NotBlank @Size(max = 30) String codigo) {}

    record PasskeyRegistrada(Long idPasskey, String nombre) {}

    record UsuarioSesion(
            Long idUsuario, String usuario, String nombre, String email, String rol, boolean mfaActivo) {}

    /**
     * estado: OK (trae access_token) | CAMBIAR_CLAVE | MFA_REQUERIDO | MFA_ENROLAR (traen
     * token_temporal, valido para el siguiente paso) | MFA_ACTIVADO | CLAVE_CAMBIADA.
     * codigos_respaldo: solo al activar el segundo factor, UNA vez. codigos_restantes: al entrar con uno.
     * passkey_disponible: en MFA_REQUERIDO, true si la persona tiene Face ID / huella registrado.
     */
    @JsonInclude(JsonInclude.Include.NON_NULL)
    record AuthResponse(
            String estado,
            String accessToken,
            Long expiresIn,
            String tokenTemporal,
            UsuarioSesion usuario,
            java.util.List<String> codigosRespaldo,
            Integer codigosRestantes,
            Boolean passkeyDisponible) {

        static AuthResponse estado(String estado) {
            return new AuthResponse(estado, null, null, null, null, null, null, null);
        }

        AuthResponse con(java.util.List<String> codigos, Integer restantes) {
            return new AuthResponse(estado, accessToken, expiresIn, tokenTemporal, usuario, codigos, restantes, passkeyDisponible);
        }
    }

    record CodigosRespaldo(java.util.List<String> codigosRespaldo) {}

    record EstadoRespaldo(int restantes) {}

    record SesionDto(String familia, java.time.LocalDateTime iniciada, java.time.LocalDateTime ultimaActividad,
                     String ip, String userAgent, boolean actual) {}

    record SesionesCerradas(int cerradas) {}

    record MfaConfig(String secreto, String otpauthUri) {}

    private AuthDtos() {}
}
