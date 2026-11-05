-- =====================================================================
-- 32 - Tres modulos opcionales nuevos: AUDITORIA, PARAMETROS y RESULTADO_QUINCENA
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Lo aplica migrar.sh. Reejecutable (no toca "activo" de lo que ya existe).
--
--  * Decision del usuario (2026-10-26): ademas de los 6 opcionales de 05, el dueno puede apagar estos tres sin afectar el
--    resto del sistema. Todo lo demas sigue en el nucleo.
--  * AUDITORIA: antes era del nucleo ("Auditoria y parametros"). Ahora es opcional y SOLO cubre la CONSULTA del ADMIN
--    (/auditoria/accesos, /cambios, /errores). La auditoria SIGUE REGISTRANDO con el modulo apagado: los triggers y
--    pkg_auditoria no dependen de el. Al encenderlo de nuevo aparece todo el historial.
--  * PARAMETROS: apagado = el ADMIN no puede CAMBIARLOS (backend y base: pkg_parametros.sp_actualizar exige el modulo).
--    Leerlos sigue siendo del nucleo, porque otras pantallas los usan; los valores se quedan como estan.
--  * RESULTADO_QUINCENA: apagado = /periodos y el tablero siguen funcionando, pero sin el bloque del resultado
--    (ingresos sin IVA, costo de produccion, gastos, cartera castigada, resultado estimado y caja neta). Lo oculta el
--    backend; las vistas no cambian.
--  * Las tres empresas existentes los reciben ENCENDIDOS: nadie pierde nada sin que el dueno lo decida.
--  * Nota: 05 es reejecutable y su MERGE volveria a marcar AUDITORIA como nucleo. No se reejecuta 05 a mano; si se hiciera,
--    hay que correr este script despues.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

MERGE INTO modulos m
USING (
    SELECT 'AUDITORIA' codigo, 'Auditoria' nombre, 0 nucleo, 70 orden,
           'Consulta de la bitacora de accesos, cambios y errores. Con el modulo apagado la auditoria sigue registrando todo.' descripcion FROM dual UNION ALL
    SELECT 'PARAMETROS', 'Parametros', 0, 80,
           'Cambiar los parametros del sistema. Apagado: se pueden leer pero no cambiar.' FROM dual UNION ALL
    SELECT 'RESULTADO_QUINCENA', 'Resultado por quincena', 0, 90,
           'Resultado estimado y caja de cada quincena. Apagado: las quincenas siguen funcionando, sin esas cifras.' FROM dual
) s ON (m.codigo = s.codigo)
WHEN MATCHED THEN UPDATE SET m.nombre = s.nombre, m.descripcion = s.descripcion, m.nucleo = s.nucleo, m.orden = s.orden
WHEN NOT MATCHED THEN INSERT (codigo, nombre, descripcion, nucleo, orden, activo)
     VALUES (s.codigo, s.nombre, s.descripcion, s.nucleo, s.orden, 1);
COMMIT;

-- Mismo cuerpo de 11, mas la exigencia del modulo (despues del rol: un OPERATIVO sigue recibiendo "permiso denegado").
CREATE OR REPLACE PACKAGE BODY pkg_parametros AS

    FUNCTION fn_numero(p_clave IN VARCHAR2) RETURN NUMBER RESULT_CACHE IS
        v_valor NUMBER;
    BEGIN
        SELECT valor_numero INTO v_valor
          FROM parametros_sistema
         WHERE clave = p_clave;
        RETURN v_valor;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                                    'Parametro de sistema no configurado: ' || p_clave);
    END fn_numero;

    PROCEDURE sp_actualizar(p_clave IN VARCHAR2, p_valor IN NUMBER) IS
        v_min    NUMBER;
        v_max    NUMBER;
        v_actual NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        pkg_modulos.sp_exigir_modulo('PARAMETROS');
        IF p_clave IS NULL OR p_valor IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La clave y el valor son obligatorios.');
        END IF;
        BEGIN
            SELECT valor_minimo, valor_maximo, valor_numero INTO v_min, v_max, v_actual
              FROM parametros_sistema WHERE clave = p_clave FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El parametro no existe.');
        END;
        IF v_actual IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'Ese parametro no es numerico y no se edita aqui.');
        END IF;
        IF p_valor <> ROUND(p_valor, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El valor admite como maximo 2 decimales.');
        END IF;
        IF (v_min IS NOT NULL AND p_valor < v_min) OR (v_max IS NOT NULL AND p_valor > v_max) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'El valor debe estar entre ' || NVL(TO_CHAR(v_min), '-') || ' y ' || NVL(TO_CHAR(v_max), '-') || '.');
        END IF;
        UPDATE parametros_sistema SET valor_numero = p_valor WHERE clave = p_clave;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar', 'clave=' || p_clave);
    END sp_actualizar;

END pkg_parametros;
/

-- Verificacion: los tres opcionales y el paquete VALID
SELECT codigo, nombre, nucleo, activo, orden FROM modulos WHERE codigo IN ('AUDITORIA', 'PARAMETROS', 'RESULTADO_QUINCENA') ORDER BY orden;
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID' AND object_name IN ('PKG_PARAMETROS', 'MODULOS');
SHOW ERRORS
