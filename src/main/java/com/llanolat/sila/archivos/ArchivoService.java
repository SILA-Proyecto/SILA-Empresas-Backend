package com.llanolat.sila.archivos;

import com.llanolat.sila.archivos.Antivirus.AntivirusNoDisponibleException;
import com.llanolat.sila.archivos.Archivos.Archivo;
import com.llanolat.sila.archivos.Archivos.Carpeta;
import com.llanolat.sila.archivos.Archivos.DescargaRequest;
import com.llanolat.sila.archivos.Archivos.Entrada;
import com.llanolat.sila.archivos.Archivos.Explorador;
import com.llanolat.sila.archivos.Archivos.Interno;
import com.llanolat.sila.archivos.Archivos.OpcionesDescarga;
import com.llanolat.sila.archivos.CifradoDocs.ArchivoIlegibleException;
import com.llanolat.sila.archivos.CifradoDocs.Descifrado;
import com.llanolat.sila.archivos.ValidadorSubida.ArchivoRechazadoException;
import com.llanolat.sila.archivos.ValidadorSubida.Validado;
import com.llanolat.sila.infra.Identidad;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.SilaException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

/**
 * Reglas de los archivos: subir (valida, escanea, limpia, cifra, guarda), ver, descargar con clave, explorar y
 * descifrar lo bajado de Drive. Cada lectura queda en la bitacora ANTES de entregar los bytes: si no se puede
 * registrar, no se entrega.
 */
@Service
public class ArchivoService {

    private static final Logger log = LoggerFactory.getLogger(ArchivoService.class);

    /** Lo que se entrega al cliente. {@code claveGenerada} solo en la clave aleatoria. */
    public record Entrega(byte[] bytes, String mime, String nombre, Long idDocumento, String claveGenerada) {}

    private final ArchivoRepository repo;
    private final CifradoDocs cifrado;
    private final AlmacenArchivos almacen;
    private final ValidadorSubida validador;
    private final Antivirus antivirus;
    private final PdfProtegido protegido;
    private final ObjectProvider<Identidad> identidad;

    public ArchivoService(ArchivoRepository repo, CifradoDocs cifrado, AlmacenArchivos almacen, ValidadorSubida validador,
                          Antivirus antivirus, PdfProtegido protegido, ObjectProvider<Identidad> identidad) {
        this.repo = repo;
        this.cifrado = cifrado;
        this.almacen = almacen;
        this.validador = validador;
        this.antivirus = antivirus;
        this.protegido = protegido;
        this.identidad = identidad;
    }

    // ----------------------------------------------------------- consulta

    public Archivo archivo(long id) {
        return repo.archivo(id).orElseThrow(() -> SilaException.noEncontrado("El archivo no existe."));
    }

    private Interno interno(long id) {
        return repo.interno(id).orElseThrow(() -> SilaException.noEncontrado("El archivo no existe."));
    }

    // ---------------------------------------------------------- lectura

    /** Ver el archivo tal cual se guardo. Queda en la bitacora (VER). */
    public Entrega ver(long id, String ip, String userAgent) {
        Interno i = interno(id);
        repo.registrarAcceso(id, "VER", null, null, ip, userAgent);
        return new Entrega(leerPlano(i), i.mimeType(), i.nombreArchivo(), id, null);
    }

    /** Opciones de clave para compartir este archivo. */
    public OpcionesDescarga opciones(long id) {
        Interno i = interno(id);
        boolean imagen = !"application/pdf".equals(i.mimeType());
        if (i.idTercero() == null || i.terceroTipo() == null) {
            return new OpcionesDescarga(false, "Este documento no esta asociado a un cliente o proveedor.", null, null, null,
                    PdfProtegido.CLAVE_MIN, PdfProtegido.CLAVE_MAX, imagen);
        }
        try {
            String clave = claveDeDocumento(i);
            return new OpcionesDescarga(true, null, i.tercero(), i.terceroTipo(), PdfProtegido.pista(clave),
                    PdfProtegido.CLAVE_MIN, PdfProtegido.CLAVE_MAX, imagen);
        } catch (SilaException e) {
            return new OpcionesDescarga(false, e.getMessage(), i.tercero(), i.terceroTipo(), null,
                    PdfProtegido.CLAVE_MIN, PdfProtegido.CLAVE_MAX, imagen);
        }
    }

    /** Descarga una COPIA protegida con clave (PDF AES-256). Queda en la bitacora (DESCARGAR + tipo de clave). */
    public Entrega descargar(long id, DescargaRequest r, String ip, String userAgent) {
        Interno i = interno(id);
        String modo = r.modoClave() == null ? "" : r.modoClave().trim().toUpperCase(Locale.ROOT);
        String clave;
        String generada = null;
        switch (modo) {
            case "DOCUMENTO" -> clave = claveDeDocumento(i);
            case "ESCRITA" -> clave = PdfProtegido.validarEscrita(r.clave());
            case "ALEATORIA" -> {
                clave = protegido.claveAleatoria();
                generada = clave;
            }
            default -> throw SilaException.parametroInvalido("modo_clave debe ser DOCUMENTO, ESCRITA o ALEATORIA.", "modo_clave");
        }
        repo.registrarAcceso(id, "DESCARGAR", modo, null, ip, userAgent);
        byte[] copia = protegido.proteger(leerPlano(i), i.mimeType(), clave);
        return new Entrega(copia, "application/pdf", nombrePdf(i.nombreArchivo()), id, generada);
    }

    private String claveDeDocumento(Interno i) {
        if (i.idTercero() == null || i.terceroTipo() == null) {
            throw SilaException.de(SilaException.OPERACION_NO_PERMITIDA,
                    "Este documento no esta asociado a un cliente o proveedor: use otra opcion de clave.");
        }
        String numero = repo.numeroDocumentoDeTercero(i.terceroTipo(), i.idTercero()).orElseThrow(() ->
                SilaException.de(SilaException.OPERACION_NO_PERMITIDA,
                        "Este tercero no tiene un documento de identidad usable como clave. Use otra opcion."));
        return PdfProtegido.claveDeDocumento(numero);
    }

    private static String nombrePdf(String nombre) {
        int punto = nombre.lastIndexOf('.');
        String base = punto > 0 ? nombre.substring(0, punto) : nombre;
        return base + ".pdf";
    }

    /** Lee del disco, descifra y verifica que sea el contenido registrado (autenticidad + huella SHA-256). */
    private byte[] leerPlano(Interno i) {
        byte[] cif = almacen.leer(i.rutaInterna());
        if (cif == null) {
            log.error("Falta en disco el archivo del documento {} (ruta {}).", i.idDocumento(), i.rutaInterna());
            throw SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE,
                    "El archivo no esta en el disco del servidor. Restaurelo desde la copia de respaldo o desde Drive.");
        }
        try {
            Descifrado d = cifrado.descifrar(cif);
            if (!i.rutaInterna().equals(d.ruta()) || !i.checksumSha256().equalsIgnoreCase(Sha256.hex(d.contenido()))) {
                throw new ArchivoIlegibleException("El contenido no coincide con lo registrado.");
            }
            return d.contenido();
        } catch (ArchivoIlegibleException e) {
            log.error("El documento {} no pasa la verificacion de integridad: {}", i.idDocumento(), e.getMessage());
            throw SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE,
                    "El archivo guardado no pasa la verificacion de integridad. No se entrega.");
        }
    }

    // ------------------------------------------------------------ subida

    /** Solo ADMIN (la base lo vuelve a exigir). Nada se guarda si el antivirus no pudo revisarlo. */
    public Archivo subir(String nombre, byte[] bytes, Long idCarpeta, String ip, String userAgent) {
        Validado v;
        try {
            v = validador.validar(nombre, bytes, b -> {
                Antivirus.Resultado r = antivirus.escanear(b);
                if (!r.limpio()) {
                    throw new ArchivoRechazadoException("El antivirus detecto una amenaza (" + r.firma()
                            + "). El archivo no se guardo.");
                }
            });
        } catch (ArchivoRechazadoException e) {
            rechazo(nombre, e.getMessage(), ip, userAgent);
            throw SilaException.de(SilaException.ARCHIVO_RECHAZADO, e.getMessage());
        } catch (AntivirusNoDisponibleException e) {
            log.error("Antivirus no disponible: se rechaza la subida de '{}'.", limpio(nombre), e);
            rechazo(nombre, "antivirus no disponible", ip, userAgent);
            throw SilaException.de(SilaException.SERVICIO_NO_DISPONIBLE,
                    "El antivirus no esta disponible, asi que el archivo no se guardo. Intente de nuevo en unos minutos.");
        }
        String ruta = cifrado.nuevaRuta();
        almacen.guardar(ruta, cifrado.cifrar(v.contenido(), ruta));
        long id;
        try {
            id = repo.registrarSubida(v.nombre(), v.mime(), ruta, v.contenido().length, Sha256.hex(v.contenido()),
                    idCarpeta, ip, userAgent);
        } catch (RuntimeException e) {
            almacen.descartar(ruta);
            throw e;
        }
        return archivo(id);
    }

    private void rechazo(String nombre, String motivo, String ip, String userAgent) {
        try {
            repo.registrarAcceso(null, "SUBIDA_RECHAZADA", null, limpio(nombre) + " - " + motivo, ip, userAgent);
        } catch (RuntimeException e) {
            log.warn("No se pudo registrar la subida rechazada.", e);
        }
    }

    private static String limpio(String s) {
        return s == null ? "" : s.replaceAll("[\\p{Cntrl}]", " ").trim();
    }

    // ----------------------------------------------------- "Ver documento"

    /**
     * Descifra un archivo bajado de Drive (o del disco). Sirve tambien de recuperacion: si la base no conoce el archivo,
     * igual se descifra (el cifrado autentico demuestra que lo hizo SILA) y se entrega con un nombre generico.
     */
    public Entrega descifrarExterno(byte[] cifradoExterno, String ip, String userAgent) {
        Descifrado d;
        try {
            d = cifrado.descifrar(cifradoExterno);
        } catch (ArchivoIlegibleException e) {
            throw SilaException.de(SilaException.ARCHIVO_RECHAZADO, e.getMessage());
        }
        Optional<Interno> registro = repo.internoPorRuta(d.ruta());
        if (registro.isPresent()) {
            Interno i = registro.get();
            if (!i.checksumSha256().equalsIgnoreCase(Sha256.hex(d.contenido()))) {
                throw SilaException.de(SilaException.ARCHIVO_RECHAZADO, "El contenido no coincide con lo registrado para ese archivo.");
            }
            repo.registrarAcceso(i.idDocumento(), "DESCIFRAR", null, "desde archivo externo", ip, userAgent);
            return new Entrega(d.contenido(), i.mimeType(), i.nombreArchivo(), i.idDocumento(), null);
        }
        String mime = ValidadorSubida.detectarMime(d.contenido());
        if (mime == null) mime = "application/octet-stream";
        repo.registrarAcceso(null, "DESCIFRAR", null, "ruta=" + d.ruta() + "; sin registro en la base", ip, userAgent);
        String ext = switch (mime) { case "application/pdf" -> ".pdf"; case "image/jpeg" -> ".jpg"; case "image/png" -> ".png"; default -> ".bin"; };
        return new Entrega(d.contenido(), mime, "recuperado-" + d.ruta().substring(0, 8) + ext, null, null);
    }

    // --------------------------------------------------------- explorador

    private static final List<String> COL_CLAVE_TIPO = List.of("n1_clave", "n2_clave", "n3_clave");
    private static final List<String> COL_NOMBRE_TIPO = List.of("n1", "n2", "n3");
    private static final List<String> COL_CLAVE_TERCERO = List.of("n2_clave", "n3_clave");
    private static final List<String> COL_NOMBRE_TERCERO = List.of("n2", "n3");

    public Explorador explorar(String arbol, List<String> ruta, boolean incluirArchivados, Integer page, Integer size, String sort) {
        boolean admin = esAdmin();
        List<String> r = ruta == null ? List.of() : ruta;
        if (arbol == null || arbol.isBlank()) {
            Map<String, Long> n = repo.conteoPorArbol();
            return new Explorador(null, List.of(), List.of(
                    new Entrada("TIPO", "Por tipo", n.get("TIPO")),
                    new Entrada("CLIENTE", "Por cliente", n.get("CLIENTE")),
                    new Entrada("PROVEEDOR", "Por proveedor", n.get("PROVEEDOR")),
                    new Entrada("MANUAL", "Mis carpetas", n.get("MANUAL"))), vacia(page, size), false);
        }
        String a = arbol.trim().toUpperCase(Locale.ROOT);
        if (r.stream().anyMatch(x -> x == null || x.isBlank() || x.length() > 100)) {
            throw SilaException.parametroInvalido("ruta invalida.", "ruta");
        }
        return switch (a) {
            case "TIPO" -> virtual(a, r, COL_CLAVE_TIPO, COL_NOMBRE_TIPO, 0, page, size, sort);
            case "CLIENTE", "PROVEEDOR" -> virtual(a, r, COL_CLAVE_TERCERO, COL_NOMBRE_TERCERO, 1, page, size, sort);
            case "MANUAL" -> manual(r, incluirArchivados, admin, page, size, sort);
            default -> throw SilaException.parametroInvalido("arbol debe ser TIPO, CLIENTE, PROVEEDOR o MANUAL.", "arbol");
        };
    }

    private Explorador virtual(String arbol, List<String> ruta, List<String> colClave, List<String> colNombre, int desfaseNombre,
                               Integer page, Integer size, String sort) {
        int niveles = colClave.size();
        int k = ruta.size();
        if (k > niveles) {
            throw SilaException.parametroInvalido("La ruta es mas profunda que el arbol.", "ruta");
        }
        List<String> fijas = colClave.subList(0, k);
        // Migas de pan: nombres de cada nivel ya elegido
        List<Entrada> migas = new ArrayList<>();
        if (k > 0) {
            String[] nombres = repo.nombresDeRuta(arbol, fijas, ruta)
                    .orElseThrow(() -> SilaException.noEncontrado("La carpeta no existe o no tiene archivos."));
            for (int i = 0; i < k; i++) migas.add(new Entrada(ruta.get(i), nombres[i + desfaseNombre], 0));
        }
        if (k < niveles) {
            // En tipo: tipo (por nombre), anio y quincena (mas reciente primero). En terceros: tercero (por nombre), anio.
            boolean descendente = k >= 1;
            List<Entrada> hijas = repo.subcarpetasVirtuales(arbol, colClave.get(k), colNombre.get(k), fijas, ruta, descendente);
            return new Explorador(arbol, migas, hijas, vacia(page, size), false);
        }
        return new Explorador(arbol, migas, List.of(), repo.archivosVirtuales(arbol, fijas, ruta, page, size, sort), false);
    }

    private Explorador manual(List<String> ruta, boolean incluirArchivados, boolean admin, Integer page, Integer size, String sort) {
        List<Entrada> migas = new ArrayList<>();
        Long actual = null;
        for (String id : ruta) {
            long n;
            try {
                n = Long.parseLong(id);
            } catch (NumberFormatException e) {
                throw SilaException.parametroInvalido("En Mis carpetas la ruta lleva ids de carpeta.", "ruta");
            }
            Carpeta c = repo.carpeta(n).orElseThrow(() -> SilaException.noEncontrado("La carpeta no existe."));
            if (!java.util.Objects.equals(c.idPadre(), actual)) {
                throw SilaException.parametroInvalido("La ruta no es una cadena de carpetas valida.", "ruta");
            }
            migas.add(new Entrada(String.valueOf(n), c.nombre(), c.nArchivos()));
            actual = n;
        }
        List<Entrada> hijas = repo.carpetasManuales(actual, incluirArchivados).stream()
                .map(c -> new Entrada(String.valueOf(c.idCarpeta()), c.nombre(), c.nArchivos() + c.nSubcarpetas())).toList();
        return new Explorador("MANUAL", migas, hijas,
                repo.archivosDeCarpetaManual(actual, incluirArchivados, page, size, sort), admin);
    }

    private static Page<Archivo> vacia(Integer page, Integer size) {
        return new Page<>(List.of(), 0, page == null ? 0 : page, size == null ? 20 : size);
    }

    // ----------------------------------------------------------- carpetas

    public List<Carpeta> carpetas(Long idPadre, boolean incluirArchivadas) {
        return repo.carpetasManuales(idPadre, incluirArchivadas);
    }

    public Carpeta crearCarpeta(Long idPadre, String nombre, String ip, String userAgent) {
        long id = repo.crearCarpeta(idPadre, nombre, ip, userAgent);
        return repo.carpeta(id).orElseThrow(() -> SilaException.noEncontrado("La carpeta no existe."));
    }

    public Carpeta archivarCarpeta(long id, String motivo, String ip, String userAgent) {
        repo.archivarCarpeta(id, motivo.trim(), ip, userAgent);
        return repo.carpeta(id).orElseThrow(() -> SilaException.noEncontrado("La carpeta no existe."));
    }

    public Archivo archivar(long id, String motivo, String ip, String userAgent) {
        repo.archivarDocumento(id, motivo.trim(), ip, userAgent);
        return archivo(id);
    }

    private boolean esAdmin() {
        try {
            return Identidad.ROL_ADMIN.equals(identidad.getObject().rol());
        } catch (RuntimeException e) {
            return false;
        }
    }
}
