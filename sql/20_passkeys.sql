-- =====================================================================
-- 20 - Passkeys (WebAuthn): Face ID / huella como segundo factor
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1, DESPUES de 08. Reejecutable.
--
--  * mfa_passkeys: una fila por dispositivo registrado. Guarda la LLAVE PUBLICA (COSE, base64url), el id de la
--    credencial y el contador de firmas. La huella o la cara NUNCA llegan aqui: se comparan dentro del telefono,
--    que solo usa la llave privada (que no sale del chip seguro) para firmar el desafio.
--  * usuarios_app.webauthn_handle: identificador aleatorio de la persona para WebAuthn (no expone el id interno).
--    Lo genera el backend (SecureRandom); la base solo lo guarda la primera vez.
--  * pkg_passkeys / vw_passkeys: registrar, usar (actualiza el contador) y quitar. Exige segundo factor activo.
--  * Al restablecer el segundo factor (mfa_activo 1 -> 0) las passkeys se borran, igual que los codigos de respaldo.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-955, -1430, -2260, -1408, -2261) THEN RAISE; END IF;
    END;
BEGIN
    ejecutar('ALTER TABLE usuarios_app ADD (webauthn_handle VARCHAR2(64 CHAR))');
    ejecutar('ALTER TABLE usuarios_app ADD CONSTRAINT uk_usuarios_webauthn UNIQUE (webauthn_handle)');
    ejecutar('
CREATE TABLE mfa_passkeys (
    id_passkey        NUMBER GENERATED ALWAYS AS IDENTITY,
    id_usuario        NUMBER              NOT NULL,
    credential_id     VARCHAR2(1400 CHAR) NOT NULL,
    llave_publica     VARCHAR2(2000 CHAR) NOT NULL,
    contador          NUMBER(20)          DEFAULT 0 NOT NULL,
    nombre            VARCHAR2(60 CHAR)   NOT NULL,
    transportes       VARCHAR2(100 CHAR),
    fecha_creacion    TIMESTAMP           DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    fecha_ultimo_uso  TIMESTAMP,
    CONSTRAINT pk_mfa_passkeys PRIMARY KEY (id_passkey),
    CONSTRAINT uk_mfa_passkeys_cred UNIQUE (credential_id),
    CONSTRAINT fk_mfa_passkeys_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios_app (id_usuario),
    CONSTRAINT ck_mfa_passkeys_contador CHECK (contador >= 0),
    CONSTRAINT ck_mfa_passkeys_cred CHECK (REGEXP_LIKE(credential_id, ''^[A-Za-z0-9_-]+$'')),
    CONSTRAINT ck_mfa_passkeys_llave CHECK (REGEXP_LIKE(llave_publica, ''^[A-Za-z0-9_-]+$''))
)');
    ejecutar('CREATE INDEX ix_mfa_passkeys_usuario ON mfa_passkeys (id_usuario)');
END;
/

COMMENT ON TABLE mfa_passkeys IS 'Passkeys (WebAuthn) por persona: solo la llave publica y el contador; la biometria no sale del dispositivo';
COMMENT ON COLUMN usuarios_app.webauthn_handle IS 'Identificador aleatorio de la persona para WebAuthn (base64url, 32 bytes)';

-- Al quitar el segundo factor (restablecerlo) las passkeys dejan de valer.
CREATE OR REPLACE TRIGGER trg_usuarios_mfa_passkeys
AFTER UPDATE OF mfa_activo ON usuarios_app
FOR EACH ROW
WHEN (NEW.mfa_activo = 0 AND OLD.mfa_activo = 1)
BEGIN
    DELETE FROM mfa_passkeys WHERE id_usuario = :NEW.id_usuario;
END trg_usuarios_mfa_passkeys;
/

CREATE OR REPLACE VIEW vw_passkeys AS
SELECT p.id_passkey, p.id_usuario, u.usuario, u.webauthn_handle, p.credential_id, p.llave_publica, p.contador,
       p.nombre, p.transportes, p.fecha_creacion, p.fecha_ultimo_uso
  FROM mfa_passkeys p
  JOIN usuarios_app u ON u.id_usuario = p.id_usuario
WITH READ ONLY;

-- ---------- pkg_passkeys ----------
-- Corre SIN sesion de aplicacion (como pkg_respaldo_mfa): el login ocurre antes de saber quien es la persona.
-- El backend ya verifico la firma WebAuthn (biblioteca Yubico); la base valida forma, limites y estado.
CREATE OR REPLACE PACKAGE pkg_passkeys AUTHID DEFINER AS
    c_maximo CONSTANT PLS_INTEGER := 10;
    -- Si la persona no tiene handle, guarda p_handle_nuevo. Devuelve el que quedo (siempre el mismo despues).
    PROCEDURE sp_asegurar_handle(p_id_usuario IN NUMBER, p_handle_nuevo IN VARCHAR2, p_handle OUT VARCHAR2);
    PROCEDURE sp_registrar(p_id_usuario IN NUMBER, p_credential_id IN VARCHAR2, p_llave IN VARCHAR2,
                           p_contador IN NUMBER, p_nombre IN VARCHAR2, p_transportes IN VARCHAR2, p_id OUT NUMBER);
    -- Tras una firma valida: guarda el contador nuevo y la fecha de uso.
    PROCEDURE sp_usar(p_credential_id IN VARCHAR2, p_contador IN NUMBER);
    -- p_n = 1 si se borro (la passkey existia y era de esa persona).
    PROCEDURE sp_quitar(p_id_usuario IN NUMBER, p_id_passkey IN NUMBER, p_n OUT NUMBER);
END pkg_passkeys;
/
CREATE OR REPLACE PACKAGE BODY pkg_passkeys AS

    PROCEDURE pr_auditar(p_id IN NUMBER, p_evento IN VARCHAR2, p_detalle IN VARCHAR2) IS
        v_usuario VARCHAR2(100);
    BEGIN
        SELECT usuario INTO v_usuario FROM usuarios_app WHERE id_usuario = p_id;
        INSERT INTO auditoria_cambios (tabla, id_registro, columna, valor_anterior, valor_nuevo, usuario)
        VALUES ('USUARIOS_APP', TO_CHAR(p_id), p_evento, NULL, SUBSTR(p_detalle, 1, 400), v_usuario);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN NULL;
    END pr_auditar;

    PROCEDURE sp_asegurar_handle(p_id_usuario IN NUMBER, p_handle_nuevo IN VARCHAR2, p_handle OUT VARCHAR2) IS
    BEGIN
        SELECT webauthn_handle INTO p_handle FROM usuarios_app WHERE id_usuario = p_id_usuario FOR UPDATE;
        IF p_handle IS NULL THEN
            IF p_handle_nuevo IS NULL OR NOT REGEXP_LIKE(p_handle_nuevo, '^[A-Za-z0-9_-]{43}$') THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Identificador WebAuthn invalido.');
            END IF;
            UPDATE usuarios_app SET webauthn_handle = p_handle_nuevo WHERE id_usuario = p_id_usuario;
            p_handle := p_handle_nuevo;
        END IF;
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El usuario no existe.');
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_asegurar_handle', 'id_usuario=' || p_id_usuario);
    END sp_asegurar_handle;

    PROCEDURE sp_registrar(p_id_usuario IN NUMBER, p_credential_id IN VARCHAR2, p_llave IN VARCHAR2,
                           p_contador IN NUMBER, p_nombre IN VARCHAR2, p_transportes IN VARCHAR2, p_id OUT NUMBER) IS
        v_mfa    NUMBER;
        v_activo NUMBER;
        v_n      NUMBER;
        v_nombre VARCHAR2(60) := TRIM(p_nombre);
    BEGIN
        SELECT mfa_activo, activo INTO v_mfa, v_activo FROM usuarios_app WHERE id_usuario = p_id_usuario FOR UPDATE;
        IF v_activo <> 1 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La cuenta esta desactivada.');
        END IF;
        IF v_mfa <> 1 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'Active primero el segundo factor (app de autenticacion).');
        END IF;
        IF v_nombre IS NULL OR LENGTH(v_nombre) > 60 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El nombre del dispositivo es obligatorio (maximo 60).');
        END IF;
        SELECT COUNT(*) INTO v_n FROM mfa_passkeys WHERE id_usuario = p_id_usuario;
        IF v_n >= c_maximo THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'Ya tiene ' || c_maximo || ' dispositivos registrados. Quite uno antes de agregar otro.');
        END IF;
        INSERT INTO mfa_passkeys (id_usuario, credential_id, llave_publica, contador, nombre, transportes)
        VALUES (p_id_usuario, p_credential_id, p_llave, NVL(p_contador, 0), v_nombre, SUBSTR(p_transportes, 1, 100))
        RETURNING id_passkey INTO p_id;
        pr_auditar(p_id_usuario, 'PASSKEY_REGISTRADA', 'id=' || p_id || '; ' || v_nombre);
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El usuario no existe.');
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'Ese dispositivo ya esta registrado.');
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar', 'id_usuario=' || p_id_usuario);
    END sp_registrar;

    PROCEDURE sp_usar(p_credential_id IN VARCHAR2, p_contador IN NUMBER) IS
    BEGIN
        UPDATE mfa_passkeys
           SET contador = GREATEST(contador, NVL(p_contador, 0)), fecha_ultimo_uso = CAST(SYSTIMESTAMP AS TIMESTAMP)
         WHERE credential_id = p_credential_id;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_usar');
    END sp_usar;

    PROCEDURE sp_quitar(p_id_usuario IN NUMBER, p_id_passkey IN NUMBER, p_n OUT NUMBER) IS
        v_nombre VARCHAR2(60);
    BEGIN
        DELETE FROM mfa_passkeys WHERE id_passkey = p_id_passkey AND id_usuario = p_id_usuario
        RETURNING nombre INTO v_nombre;
        p_n := SQL%ROWCOUNT;
        IF p_n = 1 THEN
            pr_auditar(p_id_usuario, 'PASSKEY_QUITADA', 'id=' || p_id_passkey || '; ' || v_nombre);
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_quitar', 'id_usuario=' || p_id_usuario);
    END sp_quitar;

END pkg_passkeys;
/

GRANT EXECUTE ON pkg_passkeys TO __ROL_APP__;
GRANT SELECT  ON vw_passkeys  TO __ROL_APP__;

-- La columna nueva en usuarios_app invalida los paquetes que la leen (pkg_autenticacion, pkg_usuarios...): recompilar.
EXEC DBMS_UTILITY.COMPILE_SCHEMA(schema => '__ESQUEMA__', compile_all => FALSE);

-- Verificacion
SELECT object_name, object_type, status FROM user_objects
 WHERE object_name IN ('MFA_PASSKEYS', 'PKG_PASSKEYS', 'VW_PASSKEYS', 'TRG_USUARIOS_MFA_PASSKEYS') ORDER BY 1, 2;
SELECT COUNT(*) AS invalidos FROM user_objects WHERE status <> 'VALID';
