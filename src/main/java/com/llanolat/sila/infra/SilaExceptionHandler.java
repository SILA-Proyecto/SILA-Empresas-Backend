package com.llanolat.sila.infra;

import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.ErrorResponse;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

/**
 * Traduce los codigos de la base de datos a respuestas HTTP.
 * El mapeo es el que define el documento de diseno (seccion 3.4).
 */
@RestControllerAdvice
public class SilaExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(SilaExceptionHandler.class);

    @ExceptionHandler(SilaException.class)
    public ResponseEntity<ErrorDto> silaError(SilaException e) {
        HttpStatus estado = switch (e.getCodigo()) {
            case SilaException.PARAMETRO_INVALIDO,
                 SilaException.ABONO_INVALIDO            -> HttpStatus.BAD_REQUEST;   // 400
            case SilaException.AUTENTICACION             -> HttpStatus.UNAUTHORIZED;  // 401
            case SilaException.PERMISO_DENEGADO          -> HttpStatus.FORBIDDEN;     // 403
            case SilaException.CUENTA_BLOQUEADA          -> HttpStatus.LOCKED;        // 423
            case SilaException.DEMASIADOS_INTENTOS       -> HttpStatus.TOO_MANY_REQUESTS; // 429
            case SilaException.ENTIDAD_NO_EXISTE         -> HttpStatus.NOT_FOUND;     // 404
            case SilaException.STOCK_INSUFICIENTE,
                 SilaException.LIMITE_CREDITO,
                 SilaException.PERIODO_CERRADO,
                 SilaException.OPERACION_NO_PERMITIDA,
                 SilaException.PERIODO_NO_ENCONTRADO,
                 SilaException.ESTADO_INVALIDO,
                 SilaException.REGISTRO_INMUTABLE,
                 SilaException.FACTURACION              -> HttpStatus.CONFLICT;      // 409
            default                                      -> HttpStatus.INTERNAL_SERVER_ERROR;
        };

        // Un error de negocio trae mensaje limpio; uno interno solo la referencia.
        ErrorDto cuerpo = e.getCampos() != null
                ? ErrorDto.validacion(e.getMessage(), e.getCampos())
                : e.esDeNegocio()
                    ? ErrorDto.deNegocio(e.getCodigo(), e.getMessage(), e.getReferenciaNumerica())
                    : ErrorDto.interno(e.getReferenciaNumerica());

        return ResponseEntity.status(estado).body(cuerpo);
    }

    /** Validacion de los DTOs (@Valid) antes de llegar a la base. */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorDto> validacion(MethodArgumentNotValidException e) {
        Map<String, String> campos = new LinkedHashMap<>();
        e.getBindingResult().getFieldErrors()
         .forEach(fe -> campos.putIfAbsent(nombreJson(fe.getField()), fe.getDefaultMessage()));
        return ResponseEntity.badRequest()
                .body(ErrorDto.validacion("Hay campos invalidos en la solicitud.", campos));
    }

    /** JSON mal formado, tipo equivocado o id no numerico en la ruta: mismo formato de error. */
    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class})
    public ResponseEntity<ErrorDto> solicitudMalFormada(Exception e) {
        return ResponseEntity.badRequest()
                .body(ErrorDto.validacion("La solicitud esta mal formada.", null));
    }

    /**
     * Red de seguridad: cualquier excepcion que no tenga manejador propio responde con el formato
     * uniforme y SIN detalles (ni mensaje, ni clase, ni traza). El detalle queda solo en el log del servidor.
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorDto> inesperado(Exception e) throws Exception {
        if (e instanceof AccessDeniedException || e instanceof AuthenticationException) {
            throw e;   // los resuelve la cadena de seguridad (401 / 403)
        }
        if (e instanceof ErrorResponse er) {   // 404, 405, 415...: errores de la peticion, no del servidor
            int http = er.getStatusCode().value();
            if (http >= 400 && http < 500) {
                boolean noExiste = http == 404;
                return ResponseEntity.status(http).body(ErrorDto.deNegocio(
                        noExiste ? SilaException.ENTIDAD_NO_EXISTE : SilaException.PARAMETRO_INVALIDO,
                        noExiste ? "El recurso no existe." : "La solicitud no es valida.", null));
            }
        }
        log.error("Error no controlado", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(ErrorDto.interno(null));
    }

    /** Los DTOs usan camelCase en Java y snake_case en JSON: el cliente debe ver el segundo. */
    private static String nombreJson(String campo) {
        return campo.replaceAll("([a-z0-9])([A-Z])", "$1_$2").toLowerCase();
    }
}
