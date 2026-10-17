package com.llanolat.sila.archivos;

import static com.llanolat.sila.infra.Peticion.agente;
import static com.llanolat.sila.infra.Peticion.ip;
import com.llanolat.sila.archivos.ArchivoService.Entrega;
import com.llanolat.sila.archivos.Archivos.AccesoDocumento;
import com.llanolat.sila.archivos.Archivos.ArchivarRequest;
import com.llanolat.sila.archivos.Archivos.Archivo;
import com.llanolat.sila.archivos.Archivos.Carpeta;
import com.llanolat.sila.archivos.Archivos.CrearCarpetaRequest;
import com.llanolat.sila.archivos.Archivos.DescargaRequest;
import com.llanolat.sila.archivos.Archivos.Explorador;
import com.llanolat.sila.archivos.Archivos.OpcionesDescarga;
import com.llanolat.sila.comprobantes.ComprobanteRepository;
import com.llanolat.sila.infra.Page;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;
import java.util.Set;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * Archivos: /api/v1/archivos. Lectura y descarga: ADMIN y OPERATIVO. Subir, archivar, crear/archivar carpetas, bitacora
 * y Drive: solo ADMIN (SeguridadConfig lo exige y la base lo vuelve a exigir). Ver docs/CONTRATO_BACKEND.md.
 * Estas rutas NO usan Idempotency-Key (cuerpos y respuestas binarios).
 */
@RestController
@RequestMapping("/api/v1/archivos")
public class ArchivoController {

    private static final Set<String> TIPOS_MIME_PERMITIDOS = Set.of("application/pdf", "image/jpeg", "image/png");

    private final ArchivoService service;
    private final ArchivoRepository repo;

    public ArchivoController(ArchivoService service, ArchivoRepository repo) {
        this.service = service;
        this.repo = repo;
    }

    // ------------------------------------------------------------- lectura

    @GetMapping
    public Page<Archivo> listar(
            @RequestParam(required = false) String origen,
            @RequestParam(required = false) String tipo,
            @RequestParam(required = false) Boolean archivado,
            @RequestParam(name = "estado_drive", required = false) String estadoDrive,
            @RequestParam(name = "id_carpeta", required = false) Long idCarpeta,
            @RequestParam(required = false) String version,
            @RequestParam(required = false) String texto,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.listar(service.origenListado(origen), tipo, archivado, estadoDrive, idCarpeta, version, texto, desde, hasta, page, size, sort);
    }

    /**
     * Explorador de carpetas. Sin {@code arbol}: la raiz (TIPO, CLIENTE, PROVEEDOR, MANUAL). Con {@code arbol} y
     * {@code ruta} (repetida: ruta=VENTA&ruta=2026): el contenido de esa carpeta.
     */
    @GetMapping("/explorador")
    public Explorador explorador(
            @RequestParam(required = false) String arbol,
            @RequestParam(required = false) List<String> ruta,
            @RequestParam(name = "incluir_archivados", required = false, defaultValue = "false") boolean incluirArchivados,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return service.explorar(arbol, ruta, incluirArchivados, page, size, sort);
    }

    /** Los PDF de un comprobante: el original y, si fue anulado, la version ANULADO. Lista vacia si no tiene PDF. */
    @GetMapping("/comprobante/{tipo}/{id}")
    public List<Archivo> deComprobante(@PathVariable String tipo, @PathVariable long id) {
        String t = ComprobanteRepository.validarTipo(tipo);
        return repo.deComprobante(t, id);
    }

    @GetMapping("/{id}")
    public Archivo obtener(@PathVariable long id) { return service.archivo(id); }

    @GetMapping("/{id}/opciones-descarga")
    public OpcionesDescarga opciones(@PathVariable long id) { return service.opciones(id); }

    /** Los bytes tal cual se guardaron (para verlo en pantalla). Queda en la bitacora (VER). */
    @GetMapping("/{id}/contenido")
    public ResponseEntity<byte[]> contenido(@PathVariable long id, HttpServletRequest req) {
        return respuesta(service.ver(id, ip(req), agente(req)));
    }

    /**
     * Copia protegida con clave (PDF AES-256). {@code modo_clave}: DOCUMENTO | ESCRITA (con {@code clave}) | ALEATORIA.
     * En ALEATORIA la clave generada viaja UNA vez en la cabecera {@code X-Clave-Generada}.
     */
    @PostMapping("/{id}/descarga")
    public ResponseEntity<byte[]> descargar(@PathVariable long id, @Valid @RequestBody DescargaRequest r, HttpServletRequest req) {
        return respuesta(service.descargar(id, r, ip(req), agente(req)));
    }

    // ----------------------------------------------------------- escritura

    /** ADMIN. multipart: {@code archivo} y, opcional, {@code id_carpeta}. 422 si el contenido no se admite. */
    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public Archivo subir(@RequestParam("archivo") MultipartFile archivo,
                         @RequestParam(name = "id_carpeta", required = false) Long idCarpeta,
                         HttpServletRequest req) throws IOException {
        // El tipo que declara el navegador no se usa para decidir; solo se descarta lo obviamente ajeno antes de leer.
        return service.subir(archivo.getOriginalFilename(), archivo.getBytes(), idCarpeta, ip(req), agente(req));
    }

    /** ADMIN. Los archivos no se borran: se archivan con motivo. Los comprobantes del sistema no se pueden archivar. */
    @PostMapping("/{id}/archivar")
    public Archivo archivar(@PathVariable long id, @Valid @RequestBody ArchivarRequest r, HttpServletRequest req) {
        return service.archivar(id, r.motivo(), ip(req), agente(req));
    }

    // ------------------------------------------------------------ carpetas

    /** Carpetas manuales hijas de {@code id_padre} (sin el, las de la raiz). Cualquier usuario. */
    @GetMapping("/carpetas")
    public List<Carpeta> carpetas(@RequestParam(name = "id_padre", required = false) Long idPadre,
                                  @RequestParam(name = "incluir_archivadas", required = false, defaultValue = "false") boolean incluirArchivadas) {
        return service.carpetas(idPadre, incluirArchivadas);
    }

    @PostMapping("/carpetas")
    @ResponseStatus(HttpStatus.CREATED)
    public Carpeta crearCarpeta(@Valid @RequestBody CrearCarpetaRequest r, HttpServletRequest req) {
        return service.crearCarpeta(r.idPadre(), r.nombre(), ip(req), agente(req));
    }

    /** ADMIN. Solo si no tiene archivos ni subcarpetas activas. */
    @PostMapping("/carpetas/{id}/archivar")
    public Carpeta archivarCarpeta(@PathVariable long id, @Valid @RequestBody ArchivarRequest r, HttpServletRequest req) {
        return service.archivarCarpeta(id, r.motivo(), ip(req), agente(req));
    }

    // ------------------------------------------------------ "Ver documento"

    /**
     * Descifra un archivo cifrado bajado de Drive (o del disco del servidor). multipart: {@code archivo}.
     * Responde con el documento original. Queda en la bitacora (DESCIFRAR).
     */
    @PostMapping(value = "/descifrar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<byte[]> descifrar(@RequestParam("archivo") MultipartFile archivo, HttpServletRequest req) throws IOException {
        return respuesta(service.descifrarExterno(archivo.getBytes(), ip(req), agente(req)));
    }

    // ------------------------------------------------------------ bitacora

    /** ADMIN. Quien vio, descargo o descifro que, con IP y tipo de clave. */
    @GetMapping("/accesos")
    public Page<AccesoDocumento> accesos(
            @RequestParam(name = "id_documento", required = false) Long idDocumento,
            @RequestParam(required = false) String usuario,
            @RequestParam(required = false) String accion,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size) {
        return repo.accesos(idDocumento, usuario, accion, page, size);
    }

    // ------------------------------------------------------------- helpers

    private ResponseEntity<byte[]> respuesta(Entrega e) {
        String mime = TIPOS_MIME_PERMITIDOS.contains(e.mime()) ? e.mime() : MediaType.APPLICATION_OCTET_STREAM_VALUE;
        String ascii = e.nombre().replaceAll("[^A-Za-z0-9._-]", "_");
        String utf8 = URLEncoder.encode(e.nombre(), StandardCharsets.UTF_8).replace("+", "%20");
        ResponseEntity.BodyBuilder b = ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(mime))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + ascii + "\"; filename*=UTF-8''" + utf8)
                .header("X-Content-Type-Options", "nosniff")
                .header("X-Archivo-Nombre", utf8)
                .cacheControl(CacheControl.noStore());
        if (e.idDocumento() != null) b.header("X-Archivo-Id", String.valueOf(e.idDocumento()));
        if (e.claveGenerada() != null) b.header("X-Clave-Generada", e.claveGenerada());
        return b.contentLength(e.bytes().length).body(e.bytes());
    }

    static String ip(HttpServletRequest req) { return req.getRemoteAddr(); }

    static String agente(HttpServletRequest req) {
        String ua = req.getHeader("User-Agent");
        return ua == null ? null : (ua.length() > 200 ? ua.substring(0, 200) : ua);
    }
}
