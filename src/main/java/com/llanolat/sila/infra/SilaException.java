package com.llanolat.sila.infra;

import java.sql.SQLException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Un error devuelto por la base de datos, ya interpretado.
 *
 * La base distingue dos cosas:
 *  - 20001..20012: error de negocio. El mensaje es limpio y se le puede
 *    mostrar al usuario final tal cual.
 *  - 20999: fallo inesperado. El mensaje solo trae una referencia; el detalle
 *    (traza incluida) quedo en la tabla log_errores. NO mostrar al usuario.
 */
public class SilaException extends RuntimeException {

    public static final int PARAMETRO_INVALIDO     = 20001;
    public static final int STOCK_INSUFICIENTE     = 20002;
    public static final int LIMITE_CREDITO         = 20003;
    public static final int PERIODO_CERRADO        = 20004;
    public static final int ABONO_INVALIDO         = 20005;
    public static final int OPERACION_NO_PERMITIDA = 20006;
    public static final int ENTIDAD_NO_EXISTE      = 20007;
    public static final int PERMISO_DENEGADO       = 20008;
    public static final int PERIODO_NO_ENCONTRADO  = 20009;
    public static final int ESTADO_INVALIDO        = 20010;
    public static final int REGISTRO_INMUTABLE     = 20011;
    public static final int FACTURACION            = 20012;
    // Originados en el backend (no en la base): autenticacion.
    public static final int AUTENTICACION          = 20013;  // credenciales o token invalidos -> 401
    public static final int CUENTA_BLOQUEADA       = 20014;  // bloqueo temporal por intentos fallidos -> 423
    public static final int DEMASIADOS_INTENTOS    = 20015;  // limite de frecuencia -> 429
    public static final int IDEMPOTENCIA_EN_CURSO  = 20016;  // misma Idempotency-Key aun en proceso -> 409
    public static final int IDEMPOTENCIA_DISTINTA  = 20017;  // misma clave con otro contenido -> 422
    public static final int ERROR_INTERNO          = 20999;

    /** "ORA-20003: La venta excede el cupo..." -> deja solo el texto. */
    private static final Pattern PREFIJO_ORA = Pattern.compile("^ORA-\\d{5}:\\s*");
    /** sp_propagar agrega "(ref. soporte: 42)" cuando el error quedo en log_errores. */
    private static final Pattern REFERENCIA = Pattern.compile("\\(ref\\. soporte:\\s*([^)]+)\\)");

    private final int codigo;
    private final String referencia;
    private final java.util.Map<String, String> campos;

    private SilaException(int codigo, String mensaje, String referencia, SQLException causa) {
        this(codigo, mensaje, referencia, causa, null);
    }

    private SilaException(int codigo, String mensaje, String referencia, SQLException causa,
                          java.util.Map<String, String> campos) {
        super(mensaje, causa);
        this.codigo = codigo;
        this.referencia = referencia;
        this.campos = campos;
    }

    public static SilaException de(SQLException e) {
        int codigo = Math.abs(e.getErrorCode());

        // El mensaje JDBC trae la pila ORA-06512 en las lineas siguientes.
        String crudo = e.getMessage() == null ? "" : e.getMessage();
        String primeraLinea = crudo.lines().findFirst().orElse("").trim();
        String mensaje = PREFIJO_ORA.matcher(primeraLinea).replaceFirst("").trim();

        Matcher m = REFERENCIA.matcher(mensaje);
        String referencia = null;
        if (m.find()) {
            referencia = m.group(1).trim();
            mensaje = m.replaceAll("").trim();
        }

        if (mensaje.isBlank()) {
            mensaje = "Error de base de datos (ORA-" + codigo + ")";
        }
        return new SilaException(codigo, mensaje, referencia, e);
    }

    /**
     * Error originado en el backend, no en la base. Se usa cuando una consulta
     * a una vista no devuelve filas: la base no lanza error en ese caso, pero
     * para el cliente HTTP sigue siendo un 404.
     */
    public static SilaException noEncontrado(String mensaje) {
        return new SilaException(ENTIDAD_NO_EXISTE, mensaje, null, null);
    }

    /** Error de negocio originado en el backend, con su propio codigo (p. ej. autenticacion). */
    public static SilaException de(int codigo, String mensaje) {
        return new SilaException(codigo, mensaje, null, null);
    }

    /** Parametro de la solicitud invalido detectado en el backend (p. ej. sort fuera de la lista blanca). */
    public static SilaException parametroInvalido(String mensaje) {
        return new SilaException(PARAMETRO_INVALIDO, mensaje, null, null);
    }

    /** Validacion de un campo concreto: el mensaje es el motivo y el campo queda marcado en el dashboard. */
    public static SilaException parametroInvalido(String mensaje, String campo) {
        return new SilaException(PARAMETRO_INVALIDO, mensaje, null, null, java.util.Map.of(campo, mensaje));
    }

    /** Campo -> motivo, solo en validaciones de un campo concreto; null en el resto. */
    public java.util.Map<String, String> getCampos() { return campos; }

    public int getCodigo() { return codigo; }

    /** Referencia a log_errores, o null si el error no se registro. */
    public String getReferencia() { return referencia; }

    /** La referencia como numero (el dashboard la espera numerica), o null. */
    public Long getReferenciaNumerica() {
        try {
            return referencia == null ? null : Long.valueOf(referencia);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** true si el mensaje es seguro para mostrarle al usuario final. */
    public boolean esDeNegocio() {
        return codigo >= PARAMETRO_INVALIDO && codigo < ERROR_INTERNO;
    }
}
