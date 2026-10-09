package com.llanolat.sila.infra;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.util.Map;

/**
 * Respuesta de error uniforme. Es el contrato del dashboard (ApiError en
 * core/api/api-error.ts): {code, message, supportRef}.
 *
 * @param code       codigo ORA-20xxx de la base (positivo), para que el
 *                   frontend reaccione distinto a "sin stock" que a "sin cupo"
 * @param message    texto mostrable al usuario
 * @param supportRef id en log_errores, numerico; ausente si el error no se registro
 * @param fields     solo en validaciones de forma (20001): campo -> motivo
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ErrorDto(int code, String message, Long supportRef, Map<String, String> fields) {

    /**
     * La referencia se incluye cuando existe, incluso en errores de negocio:
     * cuando la base traduce un ORA-00001 o un ORA-02291 a un mensaje limpio,
     * el detalle real (con el nombre de la restriccion) queda en log_errores y
     * esta referencia es la unica forma de encontrarlo.
     */
    public static ErrorDto deNegocio(int code, String message, Long supportRef) {
        return new ErrorDto(code, message, supportRef, null);
    }

    public static ErrorDto interno(Long supportRef) {
        return new ErrorDto(SilaException.ERROR_INTERNO,
                "Ocurrio un error interno. Si el problema persiste, reporte la referencia.",
                supportRef, null);
    }

    public static ErrorDto validacion(String message, Map<String, String> fields) {
        return new ErrorDto(SilaException.PARAMETRO_INVALIDO, message, null, fields);
    }
}
