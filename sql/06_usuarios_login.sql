-- =====================================================================
-- 06 - Usuarios y autenticacion (login)
-- Ejecutar como: system[__ESQUEMA__] (proxy) en XEPDB1. Reejecutable.
-- Crea: usuarios_app, sesiones_usuario, parametros de login, pkg_autenticacion
--       (sin sesion de aplicacion: lo usa el login), pkg_usuarios (solo ADMIN),
--       vw_usuarios y los permisos de __ROL_APP__.
--
-- Decisiones de seguridad:
--  * La base NUNCA ve una contrasena: solo el hash BCrypt que calcula el backend.
--  * El secreto TOTP llega ya cifrado por el backend (AES-GCM); la base no lo puede leer en claro.
--  * Los tokens de renovacion se guardan solo como hash SHA-256.
--  * La app no puede leer usuarios_app ni sesiones_usuario: solo ejecuta los packages.
--  * vw_usuarios no expone el hash ni el secreto del segundo factor.
-- =====================================================================
SET DEFINE OFF
SET ECHO ON

-- ---------- Tablas (omitidas si ya existen) ----------
DECLARE
    PROCEDURE ejecutar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-955, -1430, -2260) THEN RAISE; END IF;  -- ya existe
    END;
BEGIN
    ejecutar('
CREATE TABLE usuarios_app (
    id_usuario          NUMBER GENERATED ALWAYS AS IDENTITY,
    usuario             VARCHAR2(100 CHAR) NOT NULL,
    nombre              VARCHAR2(120 CHAR) NOT NULL,
    email               VARCHAR2(150 CHAR) NOT NULL,
    rol                 VARCHAR2(10 CHAR)  NOT NULL,
    password_hash       VARCHAR2(120 CHAR) NOT NULL,
    debe_cambiar_clave  NUMBER(1)          DEFAULT 1 NOT NULL,
    activo              NUMBER(1)          DEFAULT 1 NOT NULL,
    intentos_fallidos   NUMBER(3)          DEFAULT 0 NOT NULL,
    bloqueado_hasta     TIMESTAMP,
    mfa_activo          NUMBER(1)          DEFAULT 0 NOT NULL,
    mfa_secreto         VARCHAR2(300 CHAR),
    mfa_ultimo_paso     NUMBER(14),
    ultimo_login        TIMESTAMP,
    fecha_cambio_clave  TIMESTAMP,
    fecha_creacion      DATE               DEFAULT SYSDATE NOT NULL,
    usuario_creacion    VARCHAR2(100 CHAR) DEFAULT NVL(SYS_CONTEXT(''__CTX__'', ''USUARIO''), SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) NOT NULL,
    CONSTRAINT pk_usuarios_app PRIMARY KEY (id_usuario),
    CONSTRAINT uk_usuarios_app_usuario UNIQUE (usuario),
    CONSTRAINT uk_usuarios_app_email UNIQUE (email),
    CONSTRAINT ck_usuarios_usuario CHECK (REGEXP_LIKE(usuario, ''^[a-z0-9_.@-]{3,100}$'')),
    CONSTRAINT ck_usuarios_email CHECK (email = LOWER(email) AND INSTR(email, ''@'') > 1),
    CONSTRAINT ck_usuarios_rol CHECK (rol IN (''ADMIN'', ''OPERATIVO'')),
    CONSTRAINT ck_usuarios_flags CHECK (debe_cambiar_clave IN (0, 1) AND activo IN (0, 1) AND mfa_activo IN (0, 1)),
    CONSTRAINT ck_usuarios_intentos CHECK (intentos_fallidos >= 0),
    CONSTRAINT ck_usuarios_mfa CHECK (mfa_activo = 0 OR mfa_secreto IS NOT NULL)
)');

    ejecutar('
CREATE TABLE sesiones_usuario (
    id_sesion       NUMBER GENERATED ALWAYS AS IDENTITY,
    id_usuario      NUMBER             NOT NULL,
    familia         VARCHAR2(36 CHAR)  NOT NULL,
    token_hash      VARCHAR2(64 CHAR)  NOT NULL,
    inicio_familia  TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    fecha_creacion  TIMESTAMP          DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP) NOT NULL,
    expira          TIMESTAMP          NOT NULL,
    usado           NUMBER(1)          DEFAULT 0 NOT NULL,
    revocado        NUMBER(1)          DEFAULT 0 NOT NULL,
    ip              VARCHAR2(45 CHAR),
    user_agent      VARCHAR2(200 CHAR),
    CONSTRAINT pk_sesiones_usuario PRIMARY KEY (id_sesion),
    CONSTRAINT uk_sesiones_token UNIQUE (token_hash),
    CONSTRAINT fk_sesiones_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios_app (id_usuario),
    CONSTRAINT ck_sesiones_flags CHECK (usado IN (0, 1) AND revocado IN (0, 1))
)');
    ejecutar('CREATE INDEX ix_sesiones_familia ON sesiones_usuario (familia)');
    ejecutar('CREATE INDEX ix_sesiones_usuario ON sesiones_usuario (id_usuario)');
END;
/

COMMENT ON TABLE usuarios_app IS 'Personas que pueden iniciar sesion en SILA (hash de clave, bloqueo y segundo factor)';
COMMENT ON COLUMN usuarios_app.usuario IS 'Nombre de usuario en minusculas; es lo que se guarda en usuario_registro y la auditoria';
COMMENT ON COLUMN usuarios_app.password_hash IS 'Hash BCrypt calculado por el backend; la base nunca ve la clave';
COMMENT ON COLUMN usuarios_app.debe_cambiar_clave IS '1 = clave temporal: debe cambiarla al entrar';
COMMENT ON COLUMN usuarios_app.mfa_secreto IS 'Secreto TOTP cifrado por el backend (AES-GCM)';
COMMENT ON COLUMN usuarios_app.mfa_ultimo_paso IS 'Ultimo paso de 30 s aceptado: impide reutilizar un codigo';
COMMENT ON TABLE sesiones_usuario IS 'Tokens de renovacion (solo su hash SHA-256), agrupados en familias para detectar reutilizacion';

-- ---------- Parametros ----------
MERGE INTO parametros_sistema p
USING (SELECT 'LOGIN_MAX_INTENTOS' clave, 5 valor, 'Intentos fallidos de login antes de bloquear la cuenta' descripcion FROM dual
       UNION ALL SELECT 'LOGIN_BLOQUEO_MINUTOS', 15, 'Minutos que dura el bloqueo temporal tras superar los intentos' FROM dual
       UNION ALL SELECT 'SESION_MAX_HORAS', 24, 'Duracion maxima de una sesion aunque se renueve (horas)' FROM dual) s
ON (p.clave = s.clave)
WHEN NOT MATCHED THEN INSERT (clave, valor_numero, descripcion) VALUES (s.clave, s.valor, s.descripcion);
COMMIT;

-- ---------- Triggers ----------
CREATE OR REPLACE TRIGGER trg_usuarios_nodelete
BEFORE DELETE ON usuarios_app
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable,
        'Los usuarios no se eliminan; se desactivan.');
END trg_usuarios_nodelete;
/

CREATE OR REPLACE TRIGGER trg_aud_usuarios
AFTER UPDATE OF nombre, email, rol, activo, mfa_activo ON usuarios_app
FOR EACH ROW
BEGIN
    IF :OLD.nombre <> :NEW.nombre THEN
        pkg_auditoria.sp_registrar('USUARIOS_APP', TO_CHAR(:NEW.id_usuario), 'NOMBRE', :OLD.nombre, :NEW.nombre);
    END IF;
    IF :OLD.email <> :NEW.email THEN
        pkg_auditoria.sp_registrar('USUARIOS_APP', TO_CHAR(:NEW.id_usuario), 'EMAIL', :OLD.email, :NEW.email);
    END IF;
    IF :OLD.rol <> :NEW.rol THEN
        pkg_auditoria.sp_registrar('USUARIOS_APP', TO_CHAR(:NEW.id_usuario), 'ROL', :OLD.rol, :NEW.rol);
    END IF;
    IF :OLD.activo <> :NEW.activo THEN
        pkg_auditoria.sp_registrar('USUARIOS_APP', TO_CHAR(:NEW.id_usuario), 'ACTIVO',
                                   TO_CHAR(:OLD.activo), TO_CHAR(:NEW.activo));
    END IF;
    IF :OLD.mfa_activo <> :NEW.mfa_activo THEN
        pkg_auditoria.sp_registrar('USUARIOS_APP', TO_CHAR(:NEW.id_usuario), 'MFA_ACTIVO',
                                   TO_CHAR(:OLD.mfa_activo), TO_CHAR(:NEW.mfa_activo));
    END IF;
END trg_aud_usuarios;
/

-- ---------- pkg_autenticacion: lo usa el login, ANTES de que exista sesion de aplicacion ----------
CREATE OR REPLACE PACKAGE pkg_autenticacion AUTHID DEFINER AS
    PROCEDURE sp_obtener_credencial(
        p_usuario         IN  VARCHAR2,
        p_id_usuario      OUT NUMBER,
        p_nombre          OUT VARCHAR2,
        p_email           OUT VARCHAR2,
        p_rol             OUT VARCHAR2,
        p_hash            OUT VARCHAR2,
        p_activo          OUT NUMBER,
        p_bloqueado_min   OUT NUMBER,
        p_debe_cambiar    OUT NUMBER,
        p_mfa_activo      OUT NUMBER,
        p_mfa_secreto     OUT VARCHAR2,
        p_mfa_ultimo_paso OUT NUMBER
    );

    PROCEDURE sp_obtener_por_id(
        p_id_usuario      IN  NUMBER,
        p_usuario         OUT VARCHAR2,
        p_nombre          OUT VARCHAR2,
        p_email           OUT VARCHAR2,
        p_rol             OUT VARCHAR2,
        p_hash            OUT VARCHAR2,
        p_activo          OUT NUMBER,
        p_bloqueado_min   OUT NUMBER,
        p_debe_cambiar    OUT NUMBER,
        p_mfa_activo      OUT NUMBER,
        p_mfa_secreto     OUT VARCHAR2,
        p_mfa_ultimo_paso OUT NUMBER
    );

    -- p_motivo: CLAVE o MFA. Si el usuario no existe no hace nada (no se audita: evita inflar la bitacora).
    -- p_bloqueado_min: minutos de bloqueo restantes (0 = no bloqueado)
    PROCEDURE sp_login_fallido(
        p_usuario       IN  VARCHAR2,
        p_motivo        IN  VARCHAR2,
        p_bloqueado_min OUT NUMBER
    );
    PROCEDURE sp_login_ok(p_id_usuario IN NUMBER);

    -- El hash nuevo lo calcula el backend. Cierra todas las sesiones del usuario.
    PROCEDURE sp_cambiar_clave(p_id_usuario IN NUMBER, p_hash IN VARCHAR2);

    PROCEDURE sp_mfa_guardar_secreto(p_id_usuario IN NUMBER, p_secreto_cifrado IN VARCHAR2);
    PROCEDURE sp_mfa_activar(p_id_usuario IN NUMBER, p_paso IN NUMBER);
    -- p_ok = 1 si el paso es nuevo (mayor al ultimo aceptado); 0 si es un codigo ya usado.
    PROCEDURE sp_mfa_consumir_paso(p_id_usuario IN NUMBER, p_paso IN NUMBER, p_ok OUT NUMBER);

    PROCEDURE sp_crear_sesion(
        p_id_usuario IN NUMBER,
        p_familia    IN VARCHAR2,
        p_token_hash IN VARCHAR2,
        p_expira_seg IN NUMBER,
        p_ip         IN VARCHAR2,
        p_user_agent IN VARCHAR2
    );
    -- p_estado: OK | INVALIDA | EXPIRADA | REUSO (token ya usado: se revoca toda la familia)
    PROCEDURE sp_rotar_sesion(
        p_hash_viejo IN  VARCHAR2,
        p_hash_nuevo IN  VARCHAR2,
        p_expira_seg IN  NUMBER,
        p_ip         IN  VARCHAR2,
        p_user_agent IN  VARCHAR2,
        p_id_usuario OUT NUMBER,
        p_estado     OUT VARCHAR2,
        p_familia    OUT VARCHAR2
    );
    -- Devuelve a quien pertenecia la sesion y su familia (NULL si el token no existe).
    PROCEDURE sp_revocar_sesion(p_token_hash IN VARCHAR2, p_id_usuario OUT NUMBER, p_familia OUT VARCHAR2);

    -- Solo funciona con la tabla de usuarios vacia (primer arranque).
    PROCEDURE sp_crear_admin_inicial(
        p_usuario IN VARCHAR2,
        p_nombre  IN VARCHAR2,
        p_email   IN VARCHAR2,
        p_hash    IN VARCHAR2
    );
END pkg_autenticacion;
/
CREATE OR REPLACE PACKAGE BODY pkg_autenticacion AS

    PROCEDURE pr_auditar(p_id IN NUMBER, p_usuario IN VARCHAR2, p_evento IN VARCHAR2, p_detalle IN VARCHAR2) IS
    BEGIN
        INSERT INTO auditoria_cambios (tabla, id_registro, columna, valor_anterior, valor_nuevo, usuario)
        VALUES ('USUARIOS_APP', TO_CHAR(p_id), SUBSTR(p_evento, 1, 40), NULL, SUBSTR(p_detalle, 1, 400),
                SUBSTR(p_usuario, 1, 100));
    END pr_auditar;

    PROCEDURE pr_revocar_todas(p_id_usuario IN NUMBER) IS
    BEGIN
        UPDATE sesiones_usuario SET revocado = 1 WHERE id_usuario = p_id_usuario AND revocado = 0;
    END pr_revocar_todas;

    PROCEDURE sp_obtener_credencial(
        p_usuario IN VARCHAR2, p_id_usuario OUT NUMBER, p_nombre OUT VARCHAR2, p_email OUT VARCHAR2,
        p_rol OUT VARCHAR2, p_hash OUT VARCHAR2, p_activo OUT NUMBER, p_bloqueado_min OUT NUMBER,
        p_debe_cambiar OUT NUMBER, p_mfa_activo OUT NUMBER, p_mfa_secreto OUT VARCHAR2, p_mfa_ultimo_paso OUT NUMBER
    ) IS
    BEGIN
        SELECT id_usuario, nombre, email, rol, password_hash, activo,
               CASE WHEN bloqueado_hasta > CAST(SYSTIMESTAMP AS TIMESTAMP)
                    THEN GREATEST(1, CEIL((CAST(bloqueado_hasta AS DATE) - CAST(CAST(SYSTIMESTAMP AS TIMESTAMP) AS DATE)) * 1440))
                    ELSE 0 END,
               debe_cambiar_clave, mfa_activo, mfa_secreto, mfa_ultimo_paso
          INTO p_id_usuario, p_nombre, p_email, p_rol, p_hash, p_activo, p_bloqueado_min,
               p_debe_cambiar, p_mfa_activo, p_mfa_secreto, p_mfa_ultimo_paso
          FROM usuarios_app
         WHERE usuario = LOWER(TRIM(p_usuario));
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_id_usuario := NULL;
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_obtener_credencial');
    END sp_obtener_credencial;

    PROCEDURE sp_obtener_por_id(
        p_id_usuario IN NUMBER, p_usuario OUT VARCHAR2, p_nombre OUT VARCHAR2, p_email OUT VARCHAR2,
        p_rol OUT VARCHAR2, p_hash OUT VARCHAR2, p_activo OUT NUMBER, p_bloqueado_min OUT NUMBER,
        p_debe_cambiar OUT NUMBER, p_mfa_activo OUT NUMBER, p_mfa_secreto OUT VARCHAR2, p_mfa_ultimo_paso OUT NUMBER
    ) IS
    BEGIN
        SELECT usuario, nombre, email, rol, password_hash, activo,
               CASE WHEN bloqueado_hasta > CAST(SYSTIMESTAMP AS TIMESTAMP)
                    THEN GREATEST(1, CEIL((CAST(bloqueado_hasta AS DATE) - CAST(CAST(SYSTIMESTAMP AS TIMESTAMP) AS DATE)) * 1440))
                    ELSE 0 END,
               debe_cambiar_clave, mfa_activo, mfa_secreto, mfa_ultimo_paso
          INTO p_usuario, p_nombre, p_email, p_rol, p_hash, p_activo, p_bloqueado_min,
               p_debe_cambiar, p_mfa_activo, p_mfa_secreto, p_mfa_ultimo_paso
          FROM usuarios_app
         WHERE id_usuario = p_id_usuario;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_usuario := NULL;
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_obtener_por_id');
    END sp_obtener_por_id;

    PROCEDURE sp_login_fallido(p_usuario IN VARCHAR2, p_motivo IN VARCHAR2, p_bloqueado_min OUT NUMBER) IS
        v_max      NUMBER := pkg_parametros.fn_numero('LOGIN_MAX_INTENTOS');
        v_minutos  NUMBER := pkg_parametros.fn_numero('LOGIN_BLOQUEO_MINUTOS');
        v_id       NUMBER;
        v_nombre   VARCHAR2(100) := LOWER(TRIM(p_usuario));
        v_bloqueo  TIMESTAMP;
    BEGIN
        p_bloqueado_min := 0;
        -- Un usuario ya bloqueado no acumula mas intentos ni extiende el bloqueo.
        UPDATE usuarios_app
           SET bloqueado_hasta   = CASE WHEN intentos_fallidos + 1 >= v_max
                                        THEN CAST(SYSTIMESTAMP AS TIMESTAMP) + NUMTODSINTERVAL(v_minutos, 'MINUTE')
                                        ELSE bloqueado_hasta END,
               intentos_fallidos = CASE WHEN intentos_fallidos + 1 >= v_max THEN 0 ELSE intentos_fallidos + 1 END
         WHERE usuario = v_nombre
           AND (bloqueado_hasta IS NULL OR bloqueado_hasta <= CAST(SYSTIMESTAMP AS TIMESTAMP))
        RETURNING id_usuario, bloqueado_hasta INTO v_id, v_bloqueo;
        IF v_id IS NOT NULL THEN
            pr_auditar(v_id, v_nombre, 'LOGIN_FALLIDO', 'motivo=' || SUBSTR(p_motivo, 1, 20));
            IF v_bloqueo IS NOT NULL AND v_bloqueo > CAST(SYSTIMESTAMP AS TIMESTAMP) THEN
                p_bloqueado_min := v_minutos;
                pr_auditar(v_id, v_nombre, 'BLOQUEO', 'minutos=' || v_minutos);
            END IF;
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_login_fallido');
    END sp_login_fallido;

    PROCEDURE sp_login_ok(p_id_usuario IN NUMBER) IS
        v_usuario VARCHAR2(100);
    BEGIN
        UPDATE usuarios_app
           SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_login = CAST(SYSTIMESTAMP AS TIMESTAMP)
         WHERE id_usuario = p_id_usuario
        RETURNING usuario INTO v_usuario;
        IF v_usuario IS NOT NULL THEN
            pr_auditar(p_id_usuario, v_usuario, 'LOGIN_OK', NULL);
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_login_ok');
    END sp_login_ok;

    PROCEDURE sp_cambiar_clave(p_id_usuario IN NUMBER, p_hash IN VARCHAR2) IS
        v_usuario VARCHAR2(100);
    BEGIN
        IF p_hash IS NULL OR LENGTH(p_hash) < 20 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Hash de clave invalido.');
        END IF;
        UPDATE usuarios_app
           SET password_hash = p_hash, debe_cambiar_clave = 0, fecha_cambio_clave = CAST(SYSTIMESTAMP AS TIMESTAMP)
         WHERE id_usuario = p_id_usuario
        RETURNING usuario INTO v_usuario;
        IF v_usuario IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El usuario no existe.');
        END IF;
        pr_revocar_todas(p_id_usuario);
        pr_auditar(p_id_usuario, v_usuario, 'CLAVE_CAMBIADA', NULL);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_cambiar_clave', 'id_usuario=' || p_id_usuario);
    END sp_cambiar_clave;

    PROCEDURE sp_mfa_guardar_secreto(p_id_usuario IN NUMBER, p_secreto_cifrado IN VARCHAR2) IS
    BEGIN
        IF p_secreto_cifrado IS NULL OR LENGTH(p_secreto_cifrado) < 20 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Secreto invalido.');
        END IF;
        UPDATE usuarios_app SET mfa_secreto = p_secreto_cifrado, mfa_ultimo_paso = NULL
         WHERE id_usuario = p_id_usuario AND mfa_activo = 0;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'El usuario no existe o ya tiene el segundo factor activo.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_mfa_guardar_secreto', 'id_usuario=' || p_id_usuario);
    END sp_mfa_guardar_secreto;

    PROCEDURE sp_mfa_activar(p_id_usuario IN NUMBER, p_paso IN NUMBER) IS
    BEGIN
        UPDATE usuarios_app SET mfa_activo = 1, mfa_ultimo_paso = p_paso
         WHERE id_usuario = p_id_usuario AND mfa_activo = 0 AND mfa_secreto IS NOT NULL;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'No hay un secreto pendiente de activar para este usuario.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_mfa_activar', 'id_usuario=' || p_id_usuario);
    END sp_mfa_activar;

    PROCEDURE sp_mfa_consumir_paso(p_id_usuario IN NUMBER, p_paso IN NUMBER, p_ok OUT NUMBER) IS
    BEGIN
        UPDATE usuarios_app SET mfa_ultimo_paso = p_paso
         WHERE id_usuario = p_id_usuario AND mfa_activo = 1
           AND (mfa_ultimo_paso IS NULL OR mfa_ultimo_paso < p_paso);
        p_ok := CASE WHEN SQL%ROWCOUNT = 1 THEN 1 ELSE 0 END;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_ok := 0;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_mfa_consumir_paso', 'id_usuario=' || p_id_usuario);
    END sp_mfa_consumir_paso;

    PROCEDURE sp_crear_sesion(
        p_id_usuario IN NUMBER, p_familia IN VARCHAR2, p_token_hash IN VARCHAR2,
        p_expira_seg IN NUMBER, p_ip IN VARCHAR2, p_user_agent IN VARCHAR2
    ) IS
    BEGIN
        -- Limpieza oportunista de sesiones vencidas hace mas de 7 dias.
        DELETE FROM sesiones_usuario WHERE expira < CAST(SYSTIMESTAMP AS TIMESTAMP) - INTERVAL '7' DAY;
        INSERT INTO sesiones_usuario (id_usuario, familia, token_hash, expira, ip, user_agent)
        VALUES (p_id_usuario, p_familia, p_token_hash,
                CAST(SYSTIMESTAMP AS TIMESTAMP) + NUMTODSINTERVAL(p_expira_seg, 'SECOND'),
                SUBSTR(p_ip, 1, 45), SUBSTR(p_user_agent, 1, 200));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_sesion', 'id_usuario=' || p_id_usuario);
    END sp_crear_sesion;

    PROCEDURE sp_rotar_sesion(
        p_hash_viejo IN VARCHAR2, p_hash_nuevo IN VARCHAR2, p_expira_seg IN NUMBER,
        p_ip IN VARCHAR2, p_user_agent IN VARCHAR2, p_id_usuario OUT NUMBER, p_estado OUT VARCHAR2,
        p_familia OUT VARCHAR2
    ) IS
        v_id_sesion NUMBER;
        v_familia   VARCHAR2(36);
        v_usado     NUMBER;
        v_revocado  NUMBER;
        v_expira    TIMESTAMP;
        v_inicio    TIMESTAMP;
        v_activo    NUMBER;
        v_usuario   VARCHAR2(100);
        v_max_horas NUMBER := pkg_parametros.fn_numero('SESION_MAX_HORAS');
    BEGIN
        p_id_usuario := NULL;
        p_familia := NULL;
        BEGIN
            SELECT id_sesion, id_usuario, familia, usado, revocado, expira, inicio_familia
              INTO v_id_sesion, p_id_usuario, v_familia, v_usado, v_revocado, v_expira, v_inicio
              FROM sesiones_usuario
             WHERE token_hash = p_hash_viejo
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_estado := 'INVALIDA';
                p_id_usuario := NULL;
                ROLLBACK;
                RETURN;
        END;

        SELECT activo, usuario INTO v_activo, v_usuario FROM usuarios_app WHERE id_usuario = p_id_usuario;

        IF v_revocado = 1 THEN
            p_estado := 'INVALIDA';
            p_id_usuario := NULL;
            ROLLBACK;
        ELSIF v_usado = 1 THEN
            -- Un token de renovacion solo se usa una vez: si reaparece, alguien lo copio.
            UPDATE sesiones_usuario SET revocado = 1 WHERE familia = v_familia;
            pr_auditar(p_id_usuario, v_usuario, 'REFRESH_REUSO', 'familia=' || v_familia);
            COMMIT;
            p_estado := 'REUSO';
            p_id_usuario := NULL;
        ELSIF v_activo = 0 THEN
            UPDATE sesiones_usuario SET revocado = 1 WHERE familia = v_familia;
            COMMIT;
            p_estado := 'INVALIDA';
            p_id_usuario := NULL;
        ELSIF v_expira < CAST(SYSTIMESTAMP AS TIMESTAMP)
           OR v_inicio + NUMTODSINTERVAL(v_max_horas, 'HOUR') < CAST(SYSTIMESTAMP AS TIMESTAMP) THEN
            p_estado := 'EXPIRADA';
            p_id_usuario := NULL;
            ROLLBACK;
        ELSE
            UPDATE sesiones_usuario SET usado = 1 WHERE id_sesion = v_id_sesion;
            INSERT INTO sesiones_usuario (id_usuario, familia, token_hash, inicio_familia, expira, ip, user_agent)
            VALUES (p_id_usuario, v_familia, p_hash_nuevo, v_inicio,
                    CAST(SYSTIMESTAMP AS TIMESTAMP) + NUMTODSINTERVAL(p_expira_seg, 'SECOND'),
                    SUBSTR(p_ip, 1, 45), SUBSTR(p_user_agent, 1, 200));
            COMMIT;
            p_estado := 'OK';
            p_familia := v_familia;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_usuario := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_rotar_sesion');
    END sp_rotar_sesion;

    PROCEDURE sp_revocar_sesion(p_token_hash IN VARCHAR2, p_id_usuario OUT NUMBER, p_familia OUT VARCHAR2) IS
    BEGIN
        p_id_usuario := NULL;
        p_familia := NULL;
        BEGIN
            SELECT id_usuario, familia INTO p_id_usuario, p_familia FROM sesiones_usuario WHERE token_hash = p_token_hash;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN;
        END;
        UPDATE sesiones_usuario SET revocado = 1 WHERE familia = p_familia;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_revocar_sesion');
    END sp_revocar_sesion;

    PROCEDURE sp_crear_admin_inicial(p_usuario IN VARCHAR2, p_nombre IN VARCHAR2, p_email IN VARCHAR2, p_hash IN VARCHAR2) IS
        v_cuenta NUMBER;
        v_id     NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_cuenta FROM usuarios_app;
        IF v_cuenta > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'Ya existen usuarios: el administrador inicial solo se crea una vez.');
        END IF;
        INSERT INTO usuarios_app (usuario, nombre, email, rol, password_hash, debe_cambiar_clave)
        VALUES (LOWER(TRIM(p_usuario)), TRIM(p_nombre), LOWER(TRIM(p_email)), 'ADMIN', p_hash, 1)
        RETURNING id_usuario INTO v_id;
        pr_auditar(v_id, LOWER(TRIM(p_usuario)), 'ADMIN_INICIAL', 'creado');
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_admin_inicial');
    END sp_crear_admin_inicial;

END pkg_autenticacion;
/

-- ---------- pkg_usuarios: administracion de usuarios (solo ADMIN, con sesion de aplicacion) ----------
CREATE OR REPLACE PACKAGE pkg_usuarios AUTHID DEFINER AS
    PROCEDURE sp_crear_usuario(
        p_usuario IN VARCHAR2, p_nombre IN VARCHAR2, p_email IN VARCHAR2, p_rol IN VARCHAR2,
        p_hash_temporal IN VARCHAR2, p_id_usuario OUT NUMBER
    );
    PROCEDURE sp_actualizar_usuario(p_id_usuario IN NUMBER, p_nombre IN VARCHAR2, p_email IN VARCHAR2, p_rol IN VARCHAR2);
    PROCEDURE sp_cambiar_estado(p_id_usuario IN NUMBER, p_activo IN NUMBER);
    PROCEDURE sp_desbloquear(p_id_usuario IN NUMBER);
    PROCEDURE sp_restablecer_clave(p_id_usuario IN NUMBER, p_hash_temporal IN VARCHAR2);
    PROCEDURE sp_restablecer_mfa(p_id_usuario IN NUMBER);
    -- Cierra todas las sesiones de esa persona (un ADMIN puede hacerlo con cualquiera, incluido si mismo).
    PROCEDURE sp_cerrar_sesiones(p_id_usuario IN NUMBER);
END pkg_usuarios;
/
CREATE OR REPLACE PACKAGE BODY pkg_usuarios AS

    -- Evita que un ADMIN se quite el acceso a si mismo y que la empresa se quede sin ADMIN activo.
    PROCEDURE pr_validar_no_propio(p_id_usuario IN NUMBER, p_accion IN VARCHAR2) IS
        v_usuario VARCHAR2(100);
    BEGIN
        SELECT usuario INTO v_usuario FROM usuarios_app WHERE id_usuario = p_id_usuario;
        IF v_usuario = LOWER(pkg_seguridad.fn_usuario_actual) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'No puede ' || p_accion || ' su propia cuenta; pidale a otro administrador.');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El usuario no existe.');
    END pr_validar_no_propio;

    PROCEDURE pr_validar_queda_admin(p_id_usuario IN NUMBER) IS
        v_otros NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_otros FROM usuarios_app
         WHERE rol = 'ADMIN' AND activo = 1 AND id_usuario <> p_id_usuario;
        IF v_otros = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'Debe quedar al menos un administrador activo.');
        END IF;
    END pr_validar_queda_admin;

    PROCEDURE pr_validar_datos(p_nombre IN VARCHAR2, p_email IN VARCHAR2, p_rol IN VARCHAR2) IS
    BEGIN
        IF p_nombre IS NULL OR LENGTH(TRIM(p_nombre)) < 3 OR LENGTH(p_nombre) > 120 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Nombre invalido (3 a 120 caracteres).');
        END IF;
        IF p_email IS NULL OR LENGTH(p_email) > 150 OR NOT REGEXP_LIKE(p_email, '^[^@ ]+@[^@ ]+\.[^@ ]+$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Correo electronico invalido.');
        END IF;
        IF p_rol IS NULL OR p_rol NOT IN ('ADMIN', 'OPERATIVO') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Rol invalido (ADMIN u OPERATIVO).');
        END IF;
    END pr_validar_datos;

    PROCEDURE sp_crear_usuario(
        p_usuario IN VARCHAR2, p_nombre IN VARCHAR2, p_email IN VARCHAR2, p_rol IN VARCHAR2,
        p_hash_temporal IN VARCHAR2, p_id_usuario OUT NUMBER
    ) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_usuario IS NULL OR NOT REGEXP_LIKE(p_usuario, '^[a-z0-9_.@-]{3,100}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Usuario invalido: 3 a 100 caracteres en minuscula (letras, numeros, punto, guion, guion bajo, @).');
        END IF;
        pr_validar_datos(p_nombre, p_email, p_rol);
        IF p_hash_temporal IS NULL OR LENGTH(p_hash_temporal) < 20 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Hash de clave invalido.');
        END IF;
        INSERT INTO usuarios_app (usuario, nombre, email, rol, password_hash, debe_cambiar_clave)
        VALUES (p_usuario, TRIM(p_nombre), LOWER(TRIM(p_email)), p_rol, p_hash_temporal, 1)
        RETURNING id_usuario INTO p_id_usuario;
        pkg_auditoria.sp_registrar('USUARIOS_APP', TO_CHAR(p_id_usuario), 'CREADO', NULL, p_usuario || ' / ' || p_rol);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_usuario := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_usuario', 'usuario=' || p_usuario);
    END sp_crear_usuario;

    PROCEDURE sp_actualizar_usuario(p_id_usuario IN NUMBER, p_nombre IN VARCHAR2, p_email IN VARCHAR2, p_rol IN VARCHAR2) IS
        v_rol_actual VARCHAR2(10);
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        pr_validar_datos(p_nombre, p_email, p_rol);
        BEGIN
            SELECT rol INTO v_rol_actual FROM usuarios_app WHERE id_usuario = p_id_usuario;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El usuario no existe.');
        END;
        IF v_rol_actual <> p_rol THEN
            pr_validar_no_propio(p_id_usuario, 'cambiar el rol de');
            IF v_rol_actual = 'ADMIN' THEN
                pr_validar_queda_admin(p_id_usuario);
            END IF;
        END IF;
        UPDATE usuarios_app SET nombre = TRIM(p_nombre), email = LOWER(TRIM(p_email)), rol = p_rol
         WHERE id_usuario = p_id_usuario;
        IF v_rol_actual <> p_rol THEN
            -- el JWT vigente lleva el rol anterior: obligar a iniciar sesion de nuevo
            UPDATE sesiones_usuario SET revocado = 1 WHERE id_usuario = p_id_usuario AND revocado = 0;
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_usuario', 'id_usuario=' || p_id_usuario);
    END sp_actualizar_usuario;

    PROCEDURE sp_cambiar_estado(p_id_usuario IN NUMBER, p_activo IN NUMBER) IS
        v_rol VARCHAR2(10);
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_activo IS NULL OR p_activo NOT IN (0, 1) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Estado invalido.');
        END IF;
        BEGIN
            SELECT rol INTO v_rol FROM usuarios_app WHERE id_usuario = p_id_usuario;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El usuario no existe.');
        END;
        IF p_activo = 0 THEN
            pr_validar_no_propio(p_id_usuario, 'desactivar');
            IF v_rol = 'ADMIN' THEN
                pr_validar_queda_admin(p_id_usuario);
            END IF;
            UPDATE sesiones_usuario SET revocado = 1 WHERE id_usuario = p_id_usuario AND revocado = 0;
        END IF;
        UPDATE usuarios_app
           SET activo = p_activo,
               intentos_fallidos = CASE WHEN p_activo = 1 THEN 0 ELSE intentos_fallidos END,
               bloqueado_hasta   = CASE WHEN p_activo = 1 THEN NULL ELSE bloqueado_hasta END
         WHERE id_usuario = p_id_usuario;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_cambiar_estado', 'id_usuario=' || p_id_usuario);
    END sp_cambiar_estado;

    PROCEDURE sp_desbloquear(p_id_usuario IN NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        UPDATE usuarios_app SET intentos_fallidos = 0, bloqueado_hasta = NULL WHERE id_usuario = p_id_usuario;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El usuario no existe.');
        END IF;
        pkg_auditoria.sp_registrar('USUARIOS_APP', TO_CHAR(p_id_usuario), 'DESBLOQUEADO', NULL, 'por administrador');
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_desbloquear', 'id_usuario=' || p_id_usuario);
    END sp_desbloquear;

    PROCEDURE sp_restablecer_clave(p_id_usuario IN NUMBER, p_hash_temporal IN VARCHAR2) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_hash_temporal IS NULL OR LENGTH(p_hash_temporal) < 20 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Hash de clave invalido.');
        END IF;
        pr_validar_no_propio(p_id_usuario, 'restablecer la clave de');
        UPDATE usuarios_app
           SET password_hash = p_hash_temporal, debe_cambiar_clave = 1,
               intentos_fallidos = 0, bloqueado_hasta = NULL
         WHERE id_usuario = p_id_usuario;
        UPDATE sesiones_usuario SET revocado = 1 WHERE id_usuario = p_id_usuario AND revocado = 0;
        pkg_auditoria.sp_registrar('USUARIOS_APP', TO_CHAR(p_id_usuario), 'CLAVE_RESTABLECIDA', NULL, 'por administrador');
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_restablecer_clave', 'id_usuario=' || p_id_usuario);
    END sp_restablecer_clave;

    PROCEDURE sp_restablecer_mfa(p_id_usuario IN NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        pr_validar_no_propio(p_id_usuario, 'restablecer el segundo factor de');
        UPDATE usuarios_app SET mfa_activo = 0, mfa_secreto = NULL, mfa_ultimo_paso = NULL
         WHERE id_usuario = p_id_usuario;
        UPDATE sesiones_usuario SET revocado = 1 WHERE id_usuario = p_id_usuario AND revocado = 0;
        pkg_auditoria.sp_registrar('USUARIOS_APP', TO_CHAR(p_id_usuario), 'MFA_RESTABLECIDO', NULL, 'por administrador');
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_restablecer_mfa', 'id_usuario=' || p_id_usuario);
    END sp_restablecer_mfa;

    PROCEDURE sp_cerrar_sesiones(p_id_usuario IN NUMBER) IS
        v_n NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        UPDATE sesiones_usuario SET revocado = 1 WHERE id_usuario = p_id_usuario AND revocado = 0;
        v_n := SQL%ROWCOUNT;
        pkg_auditoria.sp_registrar('USUARIOS_APP', TO_CHAR(p_id_usuario), 'SESIONES_CERRADAS', NULL, 'por administrador: ' || v_n);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_cerrar_sesiones', 'id_usuario=' || p_id_usuario);
    END sp_cerrar_sesiones;

END pkg_usuarios;
/

-- ---------- Vista de lectura (sin hash ni secreto) ----------
CREATE OR REPLACE VIEW vw_usuarios AS
SELECT id_usuario, usuario, nombre, email, rol, activo, debe_cambiar_clave, mfa_activo,
       CASE WHEN bloqueado_hasta > CAST(SYSTIMESTAMP AS TIMESTAMP) THEN 1 ELSE 0 END AS bloqueado,
       CASE WHEN bloqueado_hasta > CAST(SYSTIMESTAMP AS TIMESTAMP)
            THEN GREATEST(1, CEIL((CAST(bloqueado_hasta AS DATE) - CAST(CAST(SYSTIMESTAMP AS TIMESTAMP) AS DATE)) * 1440))
            ELSE 0 END AS bloqueado_minutos,
       ultimo_login, fecha_cambio_clave, fecha_creacion
  FROM usuarios_app
WITH READ ONLY;

-- ---------- Permisos ----------
GRANT EXECUTE ON pkg_autenticacion TO __ROL_APP__;
GRANT EXECUTE ON pkg_usuarios      TO __ROL_APP__;
GRANT SELECT  ON vw_usuarios       TO __ROL_APP__;

SHOW ERRORS
