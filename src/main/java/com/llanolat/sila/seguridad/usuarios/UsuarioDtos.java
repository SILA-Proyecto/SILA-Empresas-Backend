package com.llanolat.sila.seguridad.usuarios;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/** Cuerpos del API de usuarios (solo ADMIN). */
final class UsuarioDtos {

    record CrearUsuarioRequest(
            @NotBlank @Pattern(regexp = "^[a-z0-9_.@-]{3,100}$",
                    message = "3 a 100 caracteres en minuscula: letras, numeros, punto, guion, guion bajo o @.") String usuario,
            @NotBlank @Size(min = 3, max = 120) String nombre,
            @NotBlank @Size(max = 150) @Pattern(regexp = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", message = "Correo invalido.") String email,
            @NotNull @Pattern(regexp = "ADMIN|OPERATIVO", message = "Debe ser ADMIN u OPERATIVO.") String rol) {}

    record ActualizarUsuarioRequest(
            @NotBlank @Size(min = 3, max = 120) String nombre,
            @NotBlank @Size(max = 150) @Pattern(regexp = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", message = "Correo invalido.") String email,
            @NotNull @Pattern(regexp = "ADMIN|OPERATIVO", message = "Debe ser ADMIN u OPERATIVO.") String rol) {}

    record CambiarEstadoRequest(@NotNull Boolean activo) {}

    /** La clave temporal se muestra UNA vez: no se guarda en claro en ningun lado. */
    record UsuarioConClaveTemporal(UsuarioDto usuario, String claveTemporal) {}

    private UsuarioDtos() {}
}
