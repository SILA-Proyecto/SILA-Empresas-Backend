-- =====================================================================
-- SILA Empresas - bootstrap de un esquema (objetos del esquema y objetos GLOBALES de la base).
-- EJECUTAR CONECTADO AL PDB XEPDB1 (no a CDB$ROOT) como SYSTEM, a traves de desplegar_base.sh,
-- que sustituye los marcadores de doble guion bajo (esquema, roles, perfil, contexto, cuentas y claves).
-- NO ejecutar a mano sin sustituir: sin sustituir falla a proposito.
-- Todo lo global (perfil, roles, cuentas, contexto) lleva un nombre derivado del esquema: asi dos
-- esquemas de la misma instancia nunca comparten permisos. Se usa CREATE (no CREATE OR REPLACE) para
-- que, si algun nombre ya existe, el script falle en vez de pisar el objeto de otro esquema.
-- Origen: Script 1 del documento de diseno de SILA v2.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

-- Perfil de contrasenas para las cuentas de servicio
CREATE PROFILE __PERFIL__ LIMIT
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME    1/24
    PASSWORD_LIFE_TIME    365
    PASSWORD_GRACE_TIME   14;

-- Esquema dueno: sin login propio, solo por proxy.
CREATE USER __ESQUEMA__ NO AUTHENTICATION
    DEFAULT TABLESPACE __TS_DATOS__ TEMPORARY TABLESPACE __TS_TEMP__
    QUOTA UNLIMITED ON __TS_DATOS__;

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER TO __ESQUEMA__;

ALTER USER __ESQUEMA__ GRANT CONNECT THROUGH __ADMIN_BD__;

-- Tres roles con responsabilidades separadas (los scripts de esquema los referencian muchas veces).
CREATE ROLE __ROL_APP__;
CREATE ROLE __ROL_LECTURA__;
CREATE ROLE __ROL_AUDITORIA__;

GRANT CREATE SESSION TO __ROL_APP__, __ROL_LECTURA__, __ROL_AUDITORIA__;

-- Cuenta del pool de Spring Boot: sin un solo privilegio sobre tablas.
CREATE USER __USR_APP__ IDENTIFIED BY "__PWD_APP__"
    PROFILE __PERFIL__;
GRANT __ROL_APP__ TO __USR_APP__;

-- Cuenta de BI / reportes: solo lectura sobre vistas agregadas.
CREATE USER __USR_REPORTES__ IDENTIFIED BY "__PWD_REP__"
    PROFILE __PERFIL__;
GRANT __ROL_LECTURA__ TO __USR_REPORTES__;

-- Contexto de aplicacion: solo pkg_seguridad de este esquema puede escribirlo.
CREATE CONTEXT __CTX__ USING __ESQUEMA__.pkg_seguridad;
