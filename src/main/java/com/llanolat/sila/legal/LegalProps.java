package com.llanolat.sila.legal;

import java.time.Duration;
import java.time.LocalDate;
import java.util.regex.Pattern;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Propiedades sila.legal.*: la VERSION VIGENTE de cada documento legal (variables SILA_LEGAL_*). El texto vive en el dashboard
 * (HTML); aqui solo se sabe cual version rige y desde cuando. Se cambian editando la variable y reiniciando la instancia: todos
 * los usuarios tendran que aceptar de nuevo. Cada empresa tiene su instancia, asi que puede tener sus propias versiones
 * (SILA_LEGAL_* en empresas/&lt;ESQUEMA&gt;/instancia.env). Se validan al arrancar.
 *
 * @param documentos la version vigente de TERMINOS y de PRIVACIDAD
 * @param cacheTtl   cuanto se recuerda si una persona esta al dia (se invalida al aceptar)
 */
@ConfigurationProperties(prefix = "sila.legal")
public record LegalProps(@DefaultValue Documentos documentos, @DefaultValue("30s") Duration cacheTtl) {

    /** Misma regla que la base (ck_aceptaciones_version y pkg_legal): letras, digitos y . _ - (1 a 30). */
    static final Pattern VERSION = Pattern.compile("^[0-9A-Za-z._-]{1,30}$");

    /** Version y fecha de entrada en vigor de UN documento. */
    public record Documento(String version, LocalDate fecha) {}

    public record Documentos(@DefaultValue Documento terminos, @DefaultValue Documento privacidad) {}

    public LegalProps {
        comprobar("TERMINOS", documentos.terminos());
        comprobar("PRIVACIDAD", documentos.privacidad());
    }

    private static void comprobar(String nombre, Documento d) {
        if (d == null || d.version() == null || !VERSION.matcher(d.version()).matches()) {
            throw new IllegalStateException("sila.legal.documentos." + nombre.toLowerCase() + ".version (SILA_LEGAL_" + nombre
                    + "_VERSION) debe tener entre 1 y 30 letras, digitos, punto, guion o guion bajo.");
        }
        if (d.fecha() == null) {
            throw new IllegalStateException("sila.legal.documentos." + nombre.toLowerCase() + ".fecha (SILA_LEGAL_" + nombre
                    + "_FECHA) debe ser una fecha AAAA-MM-DD.");
        }
    }
}
