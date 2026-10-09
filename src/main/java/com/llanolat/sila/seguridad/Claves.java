package com.llanolat.sila.seguridad;

import java.util.Base64;

/** Lectura de las claves que llegan en base64 por variable de entorno. */
final class Claves {

    static byte[] decodificar(String valor, String variable, int minimoBytes) {
        if (valor == null || valor.isBlank()) {
            throw new IllegalStateException("Falta la variable de entorno " + variable
                    + ". Cargue las claves con ./arrancar.sh (lee ~/sila_llanolat/credenciales.txt).");
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(valor.trim());
        } catch (IllegalArgumentException e) {
            throw new IllegalStateException(variable + " no es base64 valido.");
        }
        if (bytes.length < minimoBytes) {
            throw new IllegalStateException(variable + " debe tener al menos " + minimoBytes + " bytes.");
        }
        return bytes;
    }

    private Claves() {}
}
