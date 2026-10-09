package com.llanolat.sila.seguridad.auth;

/** Fila de usuarios_app tal como la entrega pkg_autenticacion (incluye hash y secreto cifrado: nunca sale del backend). */
record Credencial(
        long idUsuario,
        String usuario,
        String nombre,
        String email,
        String rol,
        String hash,
        boolean activo,
        int bloqueadoMin,
        boolean debeCambiar,
        boolean mfaActivo,
        String mfaSecreto,
        Long mfaUltimoPaso
) {
    boolean bloqueado() {
        return bloqueadoMin > 0;
    }
}
