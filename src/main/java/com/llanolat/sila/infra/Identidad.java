package com.llanolat.sila.infra;


/**
 * Quien es la persona que ejecuta la operacion y con que rol.
 *
 * La base de datos NO puede averiguarlo: LLANOLAT_APP es solo la cuenta
 * tecnica del pool. El backend lo afirma con pkg_seguridad.sp_iniciar_sesion
 * y la base lo guarda en cada registro (usuario_registro) y lo exige en cada
 * escritura (sp_exigir_rol).
 *
 * Hoy la implementacion activa es {@link IdentidadDesdeCabecera} (desarrollo).
 * Cuando se agregue Spring Security, se reemplaza por una que lea el JWT.
 */
public interface Identidad {

    String ROL_ADMIN = "ADMIN";
    String ROL_OPERATIVO = "OPERATIVO";

    /** Identificador de la persona. La base exige ^[A-Za-z0-9_.@-]{3,100}$ */
    String usuario();

    /** ADMIN u OPERATIVO. ADMIN incluye los permisos de OPERATIVO. */
    String rol();
}
