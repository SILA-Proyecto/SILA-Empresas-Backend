package com.llanolat.sila.archivos;

import com.llanolat.sila.infra.SilaException;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * Google Drive (API v3) por HTTP, con OAuth 2.0 y el alcance minimo {@code drive.file}: SILA solo ve los archivos que ella
 * misma crea, nunca el resto del Drive. Lo que se sube ya viene CIFRADO y con nombre opaco (ruta_interna.sila): Google ve
 * bytes ilegibles, sin nombres de clientes ni estructura de carpetas (esa vive solo en nuestra base).
 *
 * El token de renovacion se guarda cifrado en el directorio de archivos (drive-oauth.sila), con la misma llave de los
 * documentos; nunca llega al dashboard. El flujo de conexion lo inicia un ADMIN y vuelve por /drive/callback con un
 * parametro "state" firmado (un solo uso, 10 minutos).
 */
@Component
public class DriveCliente {

    private static final Logger log = LoggerFactory.getLogger(DriveCliente.class);
    private static final String ARCHIVO_TOKEN = "drive-oauth.sila";
    private static final String ETIQUETA = "sila-drive-oauth-v1";
    private static final String ALCANCE = "https://www.googleapis.com/auth/drive.file";
    private static final Duration ESTADO_VIDA = Duration.ofMinutes(10);

    /** Resultado de subir: id del archivo en Drive y su enlace de visualizacion (solo lo abre la cuenta duena). */
    public record Subido(String id, String enlace) {}

    private record Credencial(String refreshToken, String folderId, String cuenta) {}

    private final ArchivosProps.Drive cfg;
    private final CifradoDocs cifrado;
    private final AlmacenArchivos almacen;
    private final JsonMapper json;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final SecureRandom azar = new SecureRandom();
    private final SecretKeySpec claveEstado;
    private final Map<String, Instant> estadosUsados = new ConcurrentHashMap<>();

    private Credencial credencial;
    private String accessToken;
    private Instant accessExpira = Instant.EPOCH;
    private volatile String ultimoError;
    private volatile boolean revocado;
    private volatile LocalDateTime ultimaSincronizacion;

    public DriveCliente(ArchivosProps props, CifradoDocs cifrado, AlmacenArchivos almacen, JsonMapper json) {
        this.cfg = props.drive();
        this.cifrado = cifrado;
        this.almacen = almacen;
        this.json = json;
        byte[] k = new byte[32];
        azar.nextBytes(k);                                   // la firma del "state" solo vale mientras el proceso viva
        this.claveEstado = new SecretKeySpec(k, "HmacSHA256");
        cargar();
    }

    // ---------------------------------------------------------------- estado

    public boolean configurado() { return cfg.configurado(); }

    /** Hay una cuenta conectada (aunque Google haya revocado el permiso: ver {@link #listo}). */
    public synchronized boolean conectado() { return credencial != null; }

    /** Conectado y sin que Google haya rechazado el token: se puede subir. */
    public synchronized boolean listo() { return credencial != null && !revocado; }

    public synchronized String cuenta() { return credencial == null ? null : credencial.cuenta(); }
    public String ultimoError() { return ultimoError; }
    public LocalDateTime ultimaSincronizacion() { return ultimaSincronizacion; }
    public String nombreCarpeta() { return cfg.carpeta(); }
    public void sincronizado() { this.ultimaSincronizacion = LocalDateTime.now(java.time.ZoneOffset.UTC); }

    public void registrarError(String mensaje) { this.ultimoError = mensaje; }
    public void limpiarError() { this.ultimoError = null; }

    // ---------------------------------------------------------- autorizacion

    /** URL a la que se manda al ADMIN para que autorice con la cuenta de Google de la empresa. */
    public String urlAutorizacion(String usuario) {
        exigirConfigurado();
        Map<String, String> p = new LinkedHashMap<>();
        p.put("client_id", cfg.clientId());
        p.put("redirect_uri", cfg.redirectUri());
        p.put("response_type", "code");
        p.put("scope", ALCANCE);
        p.put("access_type", "offline");
        p.put("prompt", "consent");                           // asegura que Google entregue el token de renovacion
        p.put("state", firmarEstado(usuario));
        return cfg.authUrl() + "?" + formulario(p);
    }

    /** Cierra el flujo: valida el state, cambia el codigo por tokens y guarda el de renovacion cifrado. */
    public synchronized void completar(String code, String state) {
        exigirConfigurado();
        verificarEstado(state);
        if (code == null || code.isBlank() || code.length() > 2048) {
            throw SilaException.parametroInvalido("Falta el codigo de autorizacion.");
        }
        Map<String, String> p = new LinkedHashMap<>();
        p.put("code", code);
        p.put("client_id", cfg.clientId());
        p.put("client_secret", cfg.clientSecret());
        p.put("redirect_uri", cfg.redirectUri());
        p.put("grant_type", "authorization_code");
        JsonNode r = pedirToken(p);
        String refresh = texto(r, "refresh_token");
        if (refresh == null) {
            throw SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE,
                    "Google no entrego el permiso de uso continuo. Revoque el acceso de SILA en la cuenta de Google y conecte de nuevo.");
        }
        this.accessToken = texto(r, "access_token");
        this.accessExpira = Instant.now().plusSeconds(Math.max(60, r.path("expires_in").asLong(3600)) - 60);
        String cuenta = null;
        try {
            JsonNode about = get("/drive/v3/about?fields=user(emailAddress)");
            cuenta = texto(about.path("user"), "emailAddress");
        } catch (RuntimeException e) {
            log.warn("No se pudo leer la cuenta de Drive conectada.", e);
        }
        this.credencial = new Credencial(refresh, null, cuenta);
        this.revocado = false;
        this.ultimoError = null;
        guardar();
        log.info("Drive conectado (cuenta {}).", cuenta);
    }

    public synchronized void desconectar() {
        this.credencial = null;
        this.accessToken = null;
        this.accessExpira = Instant.EPOCH;
        this.revocado = false;
        almacen.borrarSellado(ARCHIVO_TOKEN);
        log.info("Drive desconectado: se borro el token guardado.");
    }

    private String firmarEstado(String usuario) {
        long expira = Instant.now().plus(ESTADO_VIDA).getEpochSecond();
        byte[] nonce = new byte[12];
        azar.nextBytes(nonce);
        String carga = Base64.getUrlEncoder().withoutPadding().encodeToString(
                (expira + "|" + Base64.getUrlEncoder().withoutPadding().encodeToString(nonce) + "|" + usuario).getBytes(StandardCharsets.UTF_8));
        return carga + "." + firma(carga);
    }

    private void verificarEstado(String state) {
        try {
            String[] partes = state == null ? new String[0] : state.split("\\.");
            if (partes.length != 2 || !MessageDigest.isEqual(firma(partes[0]).getBytes(StandardCharsets.US_ASCII),
                    partes[1].getBytes(StandardCharsets.US_ASCII))) {
                throw new IllegalArgumentException();
            }
            String[] c = new String(Base64.getUrlDecoder().decode(partes[0]), StandardCharsets.UTF_8).split("\\|", 3);
            if (Instant.now().getEpochSecond() > Long.parseLong(c[0]) || estadosUsados.putIfAbsent(c[1], Instant.now()) != null) {
                throw new IllegalArgumentException();
            }
            estadosUsados.values().removeIf(t -> t.isBefore(Instant.now().minus(ESTADO_VIDA)));
        } catch (RuntimeException e) {
            throw SilaException.de(SilaException.PERMISO_DENEGADO, "El enlace de autorizacion no es valido o ya vencio. Inicie la conexion de nuevo.");
        }
    }

    private String firma(String carga) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(claveEstado);
            return Base64.getUrlEncoder().withoutPadding().encodeToString(mac.doFinal(carga.getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    // ----------------------------------------------------------------- subir

    /**
     * Sube un archivo (ya cifrado) a la carpeta de respaldo; si ya existe uno con ese nombre (un intento anterior que
     * llego a Drive pero no alcanzo a registrarse), lo reutiliza en vez de duplicarlo.
     */
    public synchronized Subido subir(String nombre, byte[] datos) {
        exigirListo();
        String carpeta = asegurarCarpeta();
        JsonNode existentes = get("/drive/v3/files?spaces=drive&fields=files(id,webViewLink)&q="
                + codificar("name = '" + nombre.replace("'", "\\'") + "' and '" + carpeta + "' in parents and trashed = false"));
        if (existentes.path("files").size() > 0) {
            JsonNode f = existentes.path("files").get(0);
            return new Subido(texto(f, "id"), texto(f, "webViewLink"));
        }
        // Subida reanudable: primero se abre la sesion con los metadatos, luego se envian los bytes.
        String metadatos = json.writeValueAsString(Map.of("name", nombre, "parents", java.util.List.of(carpeta)));
        HttpResponse<String> inicio = enviar(HttpRequest.newBuilder(URI.create(cfg.apiUrl() + "/upload/drive/v3/files?uploadType=resumable&fields=id,webViewLink"))
                .header("Authorization", "Bearer " + tokenAcceso())
                .header("Content-Type", "application/json; charset=UTF-8")
                .header("X-Upload-Content-Type", "application/octet-stream")
                .header("X-Upload-Content-Length", String.valueOf(datos.length))
                .POST(HttpRequest.BodyPublishers.ofString(metadatos)).timeout(Duration.ofSeconds(30)).build());
        String destino = inicio.headers().firstValue("Location").orElseThrow(() -> falla("Drive no devolvio la sesion de subida."));
        HttpResponse<String> fin = enviar(HttpRequest.newBuilder(URI.create(destino))
                .header("Content-Type", "application/octet-stream")
                .PUT(HttpRequest.BodyPublishers.ofByteArray(datos)).timeout(Duration.ofMinutes(2)).build());
        JsonNode r = leer(fin);
        return new Subido(texto(r, "id"), texto(r, "webViewLink"));
    }

    private String asegurarCarpeta() {
        if (credencial.folderId() != null) return credencial.folderId();
        JsonNode buscadas = get("/drive/v3/files?spaces=drive&fields=files(id)&q=" + codificar(
                "name = '" + cfg.carpeta().replace("'", "\\'") + "' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"));
        String id;
        if (buscadas.path("files").size() > 0) {
            id = texto(buscadas.path("files").get(0), "id");
        } else {
            String cuerpo = json.writeValueAsString(Map.of("name", cfg.carpeta(), "mimeType", "application/vnd.google-apps.folder"));
            JsonNode creada = leer(enviar(HttpRequest.newBuilder(URI.create(cfg.apiUrl() + "/drive/v3/files?fields=id"))
                    .header("Authorization", "Bearer " + tokenAcceso()).header("Content-Type", "application/json; charset=UTF-8")
                    .POST(HttpRequest.BodyPublishers.ofString(cuerpo)).timeout(Duration.ofSeconds(30)).build()));
            id = texto(creada, "id");
        }
        credencial = new Credencial(credencial.refreshToken(), id, credencial.cuenta());
        guardar();
        return id;
    }

    // ----------------------------------------------------------- HTTP / tokens

    private JsonNode get(String rutaYConsulta) {
        return leer(enviar(HttpRequest.newBuilder(URI.create(cfg.apiUrl() + rutaYConsulta))
                .header("Authorization", "Bearer " + tokenAcceso()).GET().timeout(Duration.ofSeconds(30)).build()));
    }

    private String tokenAcceso() {
        if (accessToken != null && Instant.now().isBefore(accessExpira)) return accessToken;
        Map<String, String> p = new LinkedHashMap<>();
        p.put("client_id", cfg.clientId());
        p.put("client_secret", cfg.clientSecret());
        p.put("refresh_token", credencial.refreshToken());
        p.put("grant_type", "refresh_token");
        JsonNode r = pedirToken(p);
        accessToken = texto(r, "access_token");
        accessExpira = Instant.now().plusSeconds(Math.max(60, r.path("expires_in").asLong(3600)) - 60);
        return accessToken;
    }

    private JsonNode pedirToken(Map<String, String> parametros) {
        HttpResponse<String> r = enviarCrudo(HttpRequest.newBuilder(URI.create(cfg.tokenUrl()))
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString(formulario(parametros))).timeout(Duration.ofSeconds(30)).build());
        if (r.statusCode() == 400 || r.statusCode() == 401) {
            JsonNode e = parsear(r.body());
            if ("invalid_grant".equals(texto(e, "error"))) {
                revocado = true;
                ultimoError = "Google rechazo el permiso (vencido o revocado). Vuelva a conectar Drive.";
                throw falla(ultimoError);
            }
        }
        return leer(r);
    }

    private HttpResponse<String> enviar(HttpRequest peticion) {
        HttpResponse<String> r = enviarCrudo(peticion);
        if (r.statusCode() / 100 != 2) {
            throw falla("Drive respondio " + r.statusCode() + ": " + resumen(r.body()));
        }
        return r;
    }

    private HttpResponse<String> enviarCrudo(HttpRequest peticion) {
        try {
            return http.send(peticion, HttpResponse.BodyHandlers.ofString());
        } catch (IOException e) {
            throw falla("No se pudo contactar a Google: " + e.getClass().getSimpleName());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw falla("Operacion con Drive interrumpida.");
        }
    }

    private JsonNode leer(HttpResponse<String> r) {
        if (r.statusCode() / 100 != 2) {
            throw falla("Google respondio " + r.statusCode() + ": " + resumen(r.body()));
        }
        return parsear(r.body());
    }

    private JsonNode parsear(String cuerpo) {
        try {
            return json.readTree(cuerpo == null || cuerpo.isBlank() ? "{}" : cuerpo);
        } catch (RuntimeException e) {
            return json.createObjectNode();
        }
    }

    private static String texto(JsonNode n, String campo) {
        JsonNode v = n.path(campo);
        return v.isMissingNode() || v.isNull() ? null : v.asString();
    }

    /** Recorta lo que devolvio Google para el log y el mensaje: nunca tokens ni cuerpos largos. */
    private static String resumen(String cuerpo) {
        String t = cuerpo == null ? "" : cuerpo.replaceAll("\\s+", " ");
        return t.length() > 200 ? t.substring(0, 200) + "..." : t;
    }

    private static SilaException falla(String mensaje) {
        return SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE, mensaje);
    }

    private void exigirConfigurado() {
        if (!cfg.configurado()) {
            throw SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE,
                    "Drive no esta configurado en el servidor (faltan SILA_DRIVE_CLIENT_ID, SILA_DRIVE_CLIENT_SECRET o SILA_DRIVE_REDIRECT_URI).");
        }
    }

    private void exigirListo() {
        exigirConfigurado();
        if (credencial == null) {
            throw SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE, "Drive no esta conectado. Un ADMIN debe conectarlo.");
        }
        if (revocado) {
            throw falla("Google rechazo el permiso de SILA. Un ADMIN debe volver a conectar Drive.");
        }
    }

    private static String formulario(Map<String, String> p) {
        StringBuilder b = new StringBuilder();
        p.forEach((k, v) -> {
            if (b.length() > 0) b.append('&');
            b.append(codificar(k)).append('=').append(codificar(v));
        });
        return b.toString();
    }

    private static String codificar(String s) { return URLEncoder.encode(s, StandardCharsets.UTF_8); }

    // ---------------------------------------------------------- persistencia

    private void cargar() {
        try {
            byte[] sellado = almacen.leerSellado(ARCHIVO_TOKEN);
            if (sellado == null) return;
            JsonNode n = json.readTree(new String(cifrado.abrir(sellado, ETIQUETA), StandardCharsets.UTF_8));
            this.credencial = new Credencial(texto(n, "refresh_token"), texto(n, "folder_id"), texto(n, "cuenta"));
        } catch (RuntimeException e) {
            log.error("No se pudo leer el acceso guardado a Drive (llave distinta o archivo danado). Hay que volver a conectar.", e);
            this.ultimoError = "No se pudo leer el acceso guardado a Drive. Vuelva a conectarlo.";
        }
    }

    private void guardar() {
        Map<String, String> m = new LinkedHashMap<>();
        m.put("refresh_token", credencial.refreshToken());
        if (credencial.folderId() != null) m.put("folder_id", credencial.folderId());
        if (credencial.cuenta() != null) m.put("cuenta", credencial.cuenta());
        almacen.escribirSellado(ARCHIVO_TOKEN, cifrado.sellar(json.writeValueAsString(m).getBytes(StandardCharsets.UTF_8), ETIQUETA));
    }
}
