package com.llanolat.sila.seguridad.usuarios;

import java.time.LocalDateTime;

/**
 * Lectura de vw_usuarios: nunca incluye el hash ni el secreto del segundo factor.
 * Las marcas de tiempo vienen en UTC (hora del servidor de base de datos), sin zona.
 */
public record UsuarioDto(
        Long idUsuario,
        String usuario,
        String nombre,
        String email,
        String rol,
        Boolean activo,
        Boolean debeCambiarClave,
        Boolean mfaActivo,
        Boolean bloqueado,
        Integer bloqueadoMinutos,
        LocalDateTime ultimoLogin,
        LocalDateTime fechaCambioClave,
        LocalDateTime fechaCreacion
) {}
