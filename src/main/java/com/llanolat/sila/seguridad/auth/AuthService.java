package com.llanolat.sila.seguridad.auth;

import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.seguridad.AccesoRegistrador;
import com.llanolat.sila.seguridad.CifradoMfa;
import com.llanolat.sila.seguridad.LimiteTasa;
import com.llanolat.sila.seguridad.PasswordService;
import com.llanolat.sila.seguridad.SeguridadProps;
import com.llanolat.sila.seguridad.TokenService;
import com.llanolat.sila.seguridad.TokenService.Tipo;
import com.llanolat.sila.seguridad.TotpService;
import com.llanolat.sila.seguridad.VerificadorUsuario;
import com.llanolat.sila.seguridad.auth.AuthDtos.AuthResponse;
import com.llanolat.sila.seguridad.auth.AuthDtos.MfaConfig;
import com.llanolat.sila.seguridad.auth.AuthDtos.SesionDto;
import com.llanolat.sila.seguridad.auth.AuthDtos.UsuarioSesion;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.OptionalLong;
import java.util.UUID;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;

/**
 * Flujo de inicio de sesion:
 *
 *   clave correcta -> CAMBIAR_CLAVE (si es temporal) -> MFA_REQUERIDO / MFA_ENROLAR -> OK
 *
 * Cada paso intermedio entrega un token temporal de UN solo proposito (claim "tipo"), que
 * no abre el resto del API. Solo el ultimo paso entrega el token de acceso y la cookie de
 * renovacion. Los mensajes de error no distinguen "usuario inexistente" de "clave mala".
 *
 * Cada sesion es una "familia" de tokens de renovacion. El token de acceso lleva su id (sid):
 * cerrar la sesion corta tambien el token de acceso vigente (ver VerificadorUsuario).
 * Todo evento relevante queda en la bitacora de accesos (IP y navegador incluidos).
 */
@Service
class AuthService {

    private static final String MSG_CREDENCIALES = "Usuario o clave incorrectos.";
    private static final String MSG_SESION = "Sesion no valida. Inicie sesion de nuevo.";
    private static final Duration UN_MINUTO = Duration.ofMinutes(1);
    /** 32 simbolos sin O, I, 0, 1: 5 bits cada uno; 10 simbolos = 50 bits por codigo de respaldo. */
    private static final String ALFABETO_CODIGO = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    static final int CODIGOS_RESPALDO = 10;

    /** Respuesta del servicio; refreshToken viaja en la cookie, nunca en el cuerpo. */
    record Resultado(AuthResponse cuerpo, String refreshToken) {}

    private final AuthRepository repo;
    private final PasswordService passwords;
    private final TokenService tokens;
    private final TotpService totp;
    private final CifradoMfa cifrado;
    private final LimiteTasa limite;
    private final SeguridadProps props;
    private final AccesoRegistrador acceso;
    private final VerificadorUsuario verificador;
    private final SecureRandom azar = new SecureRandom();

    AuthService(AuthRepository repo, PasswordService passwords, TokenService tokens, TotpService totp,
                CifradoMfa cifrado, LimiteTasa limite, SeguridadProps props, AccesoRegistrador acceso,
                VerificadorUsuario verificador) {
        this.repo = repo;
        this.passwords = passwords;
        this.tokens = tokens;
        this.totp = totp;
        this.cifrado = cifrado;
        this.limite = limite;
        this.props = props;
        this.acceso = acceso;
        this.verificador = verificador;
    }

    // ---------- login ----------

    Resultado login(String usuarioIngresado, String clave, String ip, String userAgent) {
        String usuario = usuarioIngresado.trim().toLowerCase(Locale.ROOT);
        if (!limite.permitir("login-ip:" + ip, 30, UN_MINUTO)
                || !limite.permitir("login-usuario:" + usuario + "@" + ip, 10, UN_MINUTO)) {
            acceso.registrar(usuario, "LIMITE_FRECUENCIA", ip, userAgent, "login");
            throw SilaException.de(SilaException.DEMASIADOS_INTENTOS,
                    "Demasiados intentos. Espere un minuto antes de volver a intentar.");
        }

        Credencial cred = repo.porUsuario(usuario).orElse(null);
        if (cred == null) {
            passwords.gastarTiempo(clave);
            acceso.registrar(usuario, "USUARIO_DESCONOCIDO", ip, userAgent, null);
            throw SilaException.de(SilaException.AUTENTICACION, MSG_CREDENCIALES);
        }
        if (cred.bloqueado()) {
            acceso.registrar(usuario, "CUENTA_BLOQUEADA", ip, userAgent, "intento durante el bloqueo");
            throw bloqueada(cred.bloqueadoMin());
        }
        if (!passwords.coincide(clave, cred.hash()) || !cred.activo()) {
            // Una cuenta desactivada responde igual que una clave mala, y tambien cuenta como fallo.
            fallo(usuario, "CLAVE", ip, userAgent, cred.activo() ? null : "cuenta desactivada");
            throw SilaException.de(SilaException.AUTENTICACION, MSG_CREDENCIALES);
        }
        return siguientePaso(cred, ip, userAgent);
    }

    // ---------- segundo factor ----------

    Resultado verificarMfa(Jwt temporal, String codigo, String ip, String userAgent) {
        exigirAlgunTipo(temporal, Tipo.MFA);
        Credencial cred = cargar(temporal);
        limitarMfa(cred);
        if (cred.bloqueado()) {
            throw bloqueada(cred.bloqueadoMin());
        }
        if (!cred.mfaActivo() || cred.mfaSecreto() == null) {
            throw SilaException.de(SilaException.AUTENTICACION, MSG_SESION);
        }
        long paso = pasoValido(cred, codigo, ip, userAgent);
        if (!repo.mfaConsumirPaso(cred.idUsuario(), paso)) {
            fallo(cred.usuario(), "MFA", ip, userAgent, "codigo reutilizado");
            throw SilaException.de(SilaException.AUTENTICACION, "Ese codigo ya fue usado. Espere el siguiente.");
        }
        return completar(cred, ip, userAgent);
    }

    /** Entrar con un codigo de respaldo (se perdio el telefono). Cada codigo sirve una sola vez. */
    Resultado usarCodigoRespaldo(Jwt temporal, String codigoIngresado, String ip, String userAgent) {
        exigirAlgunTipo(temporal, Tipo.MFA);
        Credencial cred = cargar(temporal);
        limitarMfa(cred);
        if (cred.bloqueado()) {
            throw bloqueada(cred.bloqueadoMin());
        }
        if (!cred.mfaActivo()) {
            throw SilaException.de(SilaException.AUTENTICACION, MSG_SESION);
        }
        String normalizado = normalizarCodigo(codigoIngresado);
        var consumo = normalizado.length() == 10
                ? repo.consumirCodigoRespaldo(cred.idUsuario(), sha256(normalizado))
                : new AuthRepository.ConsumoRespaldo(false, 0);
        if (!consumo.ok()) {
            fallo(cred.usuario(), "MFA", ip, userAgent, "codigo de respaldo");
            throw SilaException.de(SilaException.AUTENTICACION, "Codigo de respaldo incorrecto o ya usado.");
        }
        acceso.registrar(cred.usuario(), "CODIGO_RESPALDO_USADO", ip, userAgent, "restantes=" + consumo.restantes());
        Resultado r = completar(cred, ip, userAgent);
        return new Resultado(r.cuerpo().con(null, consumo.restantes()), r.refreshToken());
    }

    MfaConfig configurarMfa(Jwt jwt) {
        exigirAlgunTipo(jwt, Tipo.MFA_ENROLAR, Tipo.ACCESO);
        Credencial cred = cargar(jwt);
        if (cred.mfaActivo()) {
            throw SilaException.de(SilaException.ESTADO_INVALIDO, "El segundo factor ya esta activo.");
        }
        byte[] secreto = totp.nuevoSecreto();
        repo.mfaGuardarSecreto(cred.idUsuario(), cifrado.cifrar(secreto, cred.idUsuario()));
        return new MfaConfig(totp.aBase32(secreto), totp.uri(cred.usuario(), secreto));
    }

    /** Al activar el segundo factor se entregan, UNA sola vez, los codigos de respaldo. */
    Resultado activarMfa(Jwt jwt, String codigo, String ip, String userAgent) {
        exigirAlgunTipo(jwt, Tipo.MFA_ENROLAR, Tipo.ACCESO);
        Credencial cred = cargar(jwt);
        limitarMfa(cred);
        if (cred.mfaActivo() || cred.mfaSecreto() == null) {
            throw SilaException.de(SilaException.ESTADO_INVALIDO,
                    "No hay un segundo factor pendiente de activar. Genere el codigo QR primero.");
        }
        long paso = pasoValido(cred, codigo, ip, userAgent);
        repo.mfaActivar(cred.idUsuario(), paso);
        acceso.registrar(cred.usuario(), "MFA_ACTIVADO", ip, userAgent, null);
        List<String> codigos = generarCodigosRespaldo(cred.idUsuario());
        if (Tipo.MFA_ENROLAR.claim().equals(jwt.getClaimAsString("tipo"))) {
            Resultado r = completar(cred, ip, userAgent);
            return new Resultado(r.cuerpo().con(codigos, null), r.refreshToken());
        }
        return new Resultado(AuthResponse.estado("MFA_ACTIVADO").con(codigos, null), null);
    }

    /** Genera 10 codigos nuevos e invalida los anteriores. Pide la clave actual. */
    List<String> regenerarCodigosRespaldo(Jwt jwt, String claveActual, String codigo, String ip, String userAgent) {
        exigirAlgunTipo(jwt, Tipo.ACCESO);
        Credencial cred = cargar(jwt);
        if (!limite.permitir("respaldo-regenerar:" + cred.idUsuario(), 5, UN_MINUTO)) {
            throw SilaException.de(SilaException.DEMASIADOS_INTENTOS, "Demasiados intentos. Espere un minuto.");
        }
        if (!passwords.coincide(claveActual, cred.hash())) {
            fallo(cred.usuario(), "CLAVE", ip, userAgent, "regenerar codigos de respaldo");
            throw SilaException.de(SilaException.AUTENTICACION, "La clave actual no es correcta.");
        }
        if (!cred.mfaActivo()) {
            throw SilaException.de(SilaException.ESTADO_INVALIDO, "Active primero el segundo factor.");
        }
        exigirSegundoFactor(cred, codigo, ip, userAgent);
        List<String> codigos = generarCodigosRespaldo(cred.idUsuario());
        acceso.registrar(cred.usuario(), "CODIGOS_RESPALDO_REGENERADOS", ip, userAgent, null);
        return codigos;
    }

    int codigosRespaldoRestantes(Jwt jwt) {
        exigirAlgunTipo(jwt, Tipo.ACCESO);
        return repo.codigosRestantes(idDe(jwt));
    }

    // ---------- cambio de clave ----------

    Resultado cambiarClave(Jwt jwt, String claveActual, String claveNueva, String codigo, String ip, String userAgent) {
        exigirAlgunTipo(jwt, Tipo.CAMBIAR_CLAVE, Tipo.ACCESO);
        Credencial cred = cargar(jwt);
        if (!limite.permitir("cambiar-clave:" + cred.idUsuario(), 10, UN_MINUTO)) {
            throw SilaException.de(SilaException.DEMASIADOS_INTENTOS, "Demasiados intentos. Espere un minuto.");
        }
        if (!passwords.coincide(claveActual, cred.hash())) {
            fallo(cred.usuario(), "CLAVE", ip, userAgent, "cambio de clave");
            throw SilaException.de(SilaException.AUTENTICACION, "La clave actual no es correcta.");
        }
        passwords.validarPolitica(claveNueva, cred.usuario(), claveActual);
        if (Tipo.ACCESO.claim().equals(jwt.getClaimAsString("tipo"))) {
            exigirSegundoFactor(cred, codigo, ip, userAgent);   // el cambio obligatorio del primer ingreso aun no tiene MFA
        }
        repo.cambiarClave(cred.idUsuario(), passwords.hash(claveNueva)); // cierra todas las sesiones
        verificador.invalidar(cred.idUsuario());
        acceso.registrar(cred.usuario(), "CLAVE_CAMBIADA", ip, userAgent, null);

        if (Tipo.CAMBIAR_CLAVE.claim().equals(jwt.getClaimAsString("tipo"))) {
            return siguientePaso(cargar(jwt), ip, userAgent);
        }
        return new Resultado(AuthResponse.estado("CLAVE_CAMBIADA"), null);
    }

    // ---------- renovacion y cierre ----------

    Resultado renovar(String refreshToken, String ip, String userAgent) {
        if (refreshToken == null || refreshToken.isBlank()) {
            throw SilaException.de(SilaException.AUTENTICACION, MSG_SESION);
        }
        if (!limite.permitir("refresh-ip:" + ip, 60, UN_MINUTO)) {
            acceso.registrar(null, "LIMITE_FRECUENCIA", ip, userAgent, "refresh");
            throw SilaException.de(SilaException.DEMASIADOS_INTENTOS, "Demasiadas solicitudes. Espere un momento.");
        }
        String nuevo = tokenOpaco();
        var rot = repo.rotarSesion(sha256(refreshToken), sha256(nuevo), props.refreshTtl().toSeconds(), ip, userAgent);
        if (!"OK".equals(rot.estado()) || rot.idUsuario() == null) {
            if ("REUSO".equals(rot.estado())) {
                acceso.registrar(null, "REFRESH_REUSO", ip, userAgent, "token de renovacion usado dos veces: sesion revocada");
            }
            throw SilaException.de(SilaException.AUTENTICACION, MSG_SESION);
        }
        Credencial cred = repo.porId(rot.idUsuario()).orElse(null);
        if (cred == null || !cred.activo()) {
            throw SilaException.de(SilaException.AUTENTICACION, MSG_SESION);
        }
        return new Resultado(accesoDe(cred, rot.familia()), nuevo);
    }

    void cerrarSesion(String refreshToken, String ip, String userAgent) {
        if (refreshToken == null || refreshToken.isBlank()) {
            return;
        }
        var cerrada = repo.revocarSesion(sha256(refreshToken));
        if (cerrada != null && cerrada.idUsuario() != null) {
            verificador.invalidar(cerrada.idUsuario(), cerrada.familia());
            String usuario = repo.porId(cerrada.idUsuario()).map(Credencial::usuario).orElse(null);
            acceso.registrar(usuario, "LOGOUT", ip, userAgent, null);
        }
    }

    UsuarioSesion yo(Jwt jwt) {
        exigirAlgunTipo(jwt, Tipo.ACCESO);
        return sesionDe(cargar(jwt));
    }

    UsuarioSesion actualizarPerfil(Jwt jwt, String nombre, String email, String codigo, String ip, String userAgent) {
        exigirAlgunTipo(jwt, Tipo.ACCESO);
        Credencial cred = cargar(jwt);
        exigirSegundoFactor(cred, codigo, ip, userAgent);
        repo.actualizarPerfil(cred.idUsuario(), nombre, email);
        verificador.invalidar(cred.idUsuario());
        acceso.registrar(cred.usuario(), "PERFIL_ACTUALIZADO", ip, userAgent, null);
        return sesionDe(cargar(jwt));
    }

    // ---------- sesiones ----------

    List<SesionDto> sesiones(Jwt jwt) {
        exigirAlgunTipo(jwt, Tipo.ACCESO);
        String actual = jwt.getClaimAsString("sid");
        return repo.sesionesActivas(idDe(jwt)).stream()
                .map(s -> new SesionDto(s.familia(), s.iniciada(), s.ultimaActividad(), s.ip(), s.userAgent(),
                                        s.familia().equals(actual)))
                .toList();
    }

    void cerrarUnaSesion(Jwt jwt, String familia, String ip, String userAgent) {
        exigirAlgunTipo(jwt, Tipo.ACCESO);
        long id = idDe(jwt);
        if (repo.revocarFamilia(id, familia) == 0) {
            throw SilaException.noEncontrado("La sesion no existe o ya estaba cerrada.");
        }
        verificador.invalidar(id, familia);
        acceso.registrar(jwt.getSubject(), "SESION_CERRADA", ip, userAgent, familia.equals(jwt.getClaimAsString("sid")) ? "la actual" : "otra sesion");
    }

    /** soloOtras=true conserva la sesion desde la que se pide. Devuelve cuantas cerro. */
    int cerrarSesiones(Jwt jwt, boolean soloOtras, String ip, String userAgent) {
        exigirAlgunTipo(jwt, Tipo.ACCESO);
        long id = idDe(jwt);
        int n = repo.revocarTodas(id, soloOtras ? jwt.getClaimAsString("sid") : null);
        verificador.invalidar(id);
        acceso.registrar(jwt.getSubject(), "SESIONES_CERRADAS", ip, userAgent, (soloOtras ? "las demas: " : "todas: ") + n);
        return n;
    }

    // ---------- piezas internas ----------

    private Resultado siguientePaso(Credencial cred, String ip, String userAgent) {
        if (cred.debeCambiar()) {
            return temporal(Tipo.CAMBIAR_CLAVE, "CAMBIAR_CLAVE", cred);
        }
        if (cred.mfaActivo()) {
            return temporal(Tipo.MFA, "MFA_REQUERIDO", cred);
        }
        if (props.mfaObligatorioRoles().contains(cred.rol())) {
            return temporal(Tipo.MFA_ENROLAR, "MFA_ENROLAR", cred);
        }
        return completar(cred, ip, userAgent);
    }

    private Resultado temporal(Tipo tipo, String estado, Credencial cred) {
        String token = tokens.emitir(tipo, cred.idUsuario(), cred.usuario(), cred.rol());
        return new Resultado(new AuthResponse(estado, null, null, token, null, null, null), null);
    }

    /** Ultimo paso: registra el login, abre la sesion (familia de renovacion) y emite el acceso. */
    private Resultado completar(Credencial cred, String ip, String userAgent) {
        repo.loginOk(cred.idUsuario());
        String familia = UUID.randomUUID().toString();
        String refresh = tokenOpaco();
        repo.crearSesion(cred.idUsuario(), familia, sha256(refresh), props.refreshTtl().toSeconds(), ip, userAgent);
        acceso.registrar(cred.usuario(), "LOGIN_OK", ip, userAgent, null);
        return new Resultado(accesoDe(cred, familia), refresh);
    }

    private AuthResponse accesoDe(Credencial cred, String familia) {
        String token = tokens.emitir(Tipo.ACCESO, cred.idUsuario(), cred.usuario(), cred.rol(), familia);
        return new AuthResponse("OK", token, tokens.segundosAcceso(), null, sesionDe(cred), null, null);
    }

    private static UsuarioSesion sesionDe(Credencial c) {
        return new UsuarioSesion(c.idUsuario(), c.usuario(), c.nombre(), c.email(), c.rol(), c.mfaActivo());
    }

    private List<String> generarCodigosRespaldo(long idUsuario) {
        List<String> codigos = new ArrayList<>();
        List<String> hashes = new ArrayList<>();
        while (codigos.size() < CODIGOS_RESPALDO) {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 10; i++) {
                sb.append(ALFABETO_CODIGO.charAt(azar.nextInt(ALFABETO_CODIGO.length())));
            }
            String crudo = sb.toString();
            String h = sha256(crudo);
            if (!hashes.contains(h)) {
                codigos.add(crudo.substring(0, 5) + "-" + crudo.substring(5));
                hashes.add(h);
            }
        }
        repo.reemplazarCodigosRespaldo(idUsuario, hashes);
        return codigos;
    }

    /** Mayusculas, sin guiones ni espacios: "abcde-fghjk" == "ABCDEFGHJK". */
    static String normalizarCodigo(String codigo) {
        return codigo == null ? "" : codigo.replaceAll("[^A-Za-z0-9]", "").toUpperCase(Locale.ROOT);
    }

    /** Verifica el codigo; si es incorrecto cuenta como intento fallido (y puede bloquear la cuenta). */
    private long pasoValido(Credencial cred, String codigo, String ip, String userAgent) {
        byte[] secreto = cifrado.descifrar(cred.mfaSecreto(), cred.idUsuario());
        OptionalLong paso = totp.verificar(secreto, codigo, Instant.now());
        if (paso.isEmpty()) {
            fallo(cred.usuario(), "MFA", ip, userAgent, null);
            throw SilaException.de(SilaException.AUTENTICACION, "Codigo incorrecto.");
        }
        return paso.getAsLong();
    }

    /**
     * Acciones sensibles con la sesion ya abierta: vuelven a pedir el segundo factor. Sirve el codigo de
     * 6 digitos de la app (de un solo uso por ventana de 30 s) o un codigo de respaldo.
     */
    private void exigirSegundoFactor(Credencial cred, String codigo, String ip, String userAgent) {
        if (codigo == null || codigo.isBlank()) {
            throw SilaException.de(SilaException.PARAMETRO_INVALIDO, "Ingrese el codigo de su app de autenticacion.");
        }
        if (!cred.mfaActivo() || cred.mfaSecreto() == null) {
            throw SilaException.de(SilaException.ESTADO_INVALIDO, "Active primero el segundo factor.");
        }
        limitarMfa(cred);
        String limpio = codigo.trim();
        if (limpio.matches("\\d{6}")) {
            long paso = pasoValido(cred, limpio, ip, userAgent);
            if (!repo.mfaConsumirPaso(cred.idUsuario(), paso)) {
                fallo(cred.usuario(), "MFA", ip, userAgent, "codigo reutilizado");
                throw SilaException.de(SilaException.AUTENTICACION, "Ese codigo ya fue usado. Espere el siguiente.");
            }
            return;
        }
        String normalizado = normalizarCodigo(limpio);
        var consumo = normalizado.length() == 10
                ? repo.consumirCodigoRespaldo(cred.idUsuario(), sha256(normalizado))
                : new AuthRepository.ConsumoRespaldo(false, 0);
        if (!consumo.ok()) {
            fallo(cred.usuario(), "MFA", ip, userAgent, "codigo incorrecto en accion sensible");
            throw SilaException.de(SilaException.AUTENTICACION, "Codigo incorrecto.");
        }
        acceso.registrar(cred.usuario(), "CODIGO_RESPALDO_USADO", ip, userAgent, "restantes=" + consumo.restantes());
    }

    private void limitarMfa(Credencial cred) {
        if (!limite.permitir("mfa:" + cred.idUsuario(), 10, UN_MINUTO)) {
            throw SilaException.de(SilaException.DEMASIADOS_INTENTOS, "Demasiados intentos. Espere un minuto.");
        }
    }

    /** Registra un fallo; si con este se bloquea la cuenta, lo informa en vez de un 401 comun. */
    private void fallo(String usuario, String motivo, String ip, String userAgent, String detalle) {
        int minutos = repo.loginFallido(usuario, motivo);
        acceso.registrar(usuario, "MFA".equals(motivo) ? "MFA_FALLIDO" : "LOGIN_FALLIDO", ip, userAgent,
                detalle == null ? "motivo=" + motivo : "motivo=" + motivo + "; " + detalle);
        if (minutos > 0) {
            acceso.registrar(usuario, "CUENTA_BLOQUEADA", ip, userAgent, "minutos=" + minutos);
            throw bloqueada(minutos);
        }
    }

    private static SilaException bloqueada(int minutos) {
        return SilaException.de(SilaException.CUENTA_BLOQUEADA,
                "Cuenta bloqueada temporalmente por intentos fallidos. Intente de nuevo en "
                + minutos + (minutos == 1 ? " minuto." : " minutos."));
    }

    private Credencial cargar(Jwt jwt) {
        return repo.porId(idDe(jwt))
                .filter(Credencial::activo)
                .orElseThrow(() -> SilaException.de(SilaException.AUTENTICACION, MSG_SESION));
    }

    private static long idDe(Jwt jwt) {
        Object uid = jwt == null ? null : jwt.getClaim("uid");
        if (!(uid instanceof Number id)) {
            throw SilaException.de(SilaException.AUTENTICACION, MSG_SESION);
        }
        return id.longValue();
    }

    private static void exigirAlgunTipo(Jwt jwt, Tipo... permitidos) {
        String tipo = jwt == null ? null : jwt.getClaimAsString("tipo");
        for (Tipo t : permitidos) {
            if (t.claim().equals(tipo)) return;
        }
        throw SilaException.de(SilaException.AUTENTICACION, MSG_SESION);
    }

    /** 256 bits al azar, en base64 URL: el valor que va en la cookie de renovacion. */
    private String tokenOpaco() {
        byte[] b = new byte[32];
        azar.nextBytes(b);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }

    static String sha256(String texto) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(texto.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
