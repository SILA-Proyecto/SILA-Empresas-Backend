-- =====================================================================
-- Semilla de una base SILA NUEVA (servidor). Reejecutable.
-- Se ejecuta como __USR_APP__, DESPUES de 01..20 y de crear el primer ADMIN.
--
-- Casi todo lo demas ya lo siembran los scripts de esquema:
--   parametros (02, 06, 11, 13) · categorias de gasto (02; INSUMOS queda
--   desactivada por 18) · cliente CONSUMIDOR FINAL (10).
-- Aqui solo faltan las quincenas. NO se cargan proveedores, clientes ni
-- productos de prueba: se ingresan desde la aplicacion.
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
ALTER SESSION SET CURRENT_SCHEMA = __ESQUEMA__;

DECLARE
    v_n NUMBER;
BEGIN
    pkg_seguridad.sp_iniciar_sesion('semilla.servidor', 'ADMIN');
    FOR v_anio IN 2026 .. 2027 LOOP
        pkg_periodos.sp_crear_periodos_anio(v_anio, v_n);
        DBMS_OUTPUT.PUT_LINE('Quincenas ' || v_anio || ' creadas: ' || v_n);
    END LOOP;
    pkg_seguridad.sp_cerrar_sesion;
EXCEPTION
    WHEN OTHERS THEN
        BEGIN pkg_seguridad.sp_cerrar_sesion; EXCEPTION WHEN OTHERS THEN NULL; END;
        RAISE;
END;
/

-- Verificacion rapida de lo sembrado
SELECT 'quincenas' AS que, COUNT(*) AS filas FROM vw_estado_periodos
UNION ALL SELECT 'parametros',        COUNT(*) FROM vw_parametros_sistema
UNION ALL SELECT 'categorias activas', COUNT(*) FROM vw_categorias_gasto WHERE activo = 1
UNION ALL SELECT 'consumidor final',  COUNT(*) FROM vw_clientes WHERE numero_documento = '222222222222';

exit
