package com.llanolat.sila.empresa;

import static com.llanolat.sila.infra.Peticion.agente;
import static com.llanolat.sila.infra.Peticion.ip;
import com.llanolat.sila.archivos.Imagenes;
import com.llanolat.sila.empresa.EmpresaService.Datos;
import com.llanolat.sila.empresa.EmpresaService.Logo;
import com.llanolat.sila.empresa.EmpresaService.Modulo;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.seguridad.auth.ConfirmacionSegundoFactor;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.io.IOException;
import java.util.List;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.multipart.MultipartFile;

/**
 * /api/v1/empresa: los datos de la empresa, su logo y sus modulos. Nombre, nombre corto, NIT y modulos los cambia SOLO el
 * dueno del sistema (sql/empresa.sh, sql/modulos.sh). El ADMIN de la empresa puede cambiar los datos de contacto, el pie del
 * comprobante y el logo, confirmando con su codigo del segundo factor (la cadena de seguridad exige ADMIN y la base tambien).
 * Ver docs/CONTRATO_EMPRESA.md.
 */
@RestController
@RequestMapping("/api/v1/empresa")
public class EmpresaController {

    /** Un modulo tal como lo ve el dashboard. {@code nucleo}: siempre activo. */
    public record ModuloDto(String codigo, String nombre, String descripcion, boolean nucleo, boolean activo) {}

    /**
     * Cualquier usuario autenticado. {@code modulosActivos}: solo los codigos, para consultar rapido.
     * {@code versionEsquema}: numero del ultimo script de base aplicado (soporte); null si la base no lo registra.
     * {@code logoVersion}: cambia cuando cambia el logo (para pedirlo de nuevo); null si la empresa no tiene logo.
     */
    public record EmpresaDto(Datos empresa, List<ModuloDto> modulos, List<String> modulosActivos, Integer versionEsquema,
                             String logoVersion) {}

    /** Sin sesion (pantalla de login): SOLO el nombre, si hay logo y si la empresa esta suspendida. Nada de NIT, modulos ni conteos. */
    /** {@code estado}: ACTIVA o SUSPENDIDA (el login muestra el aviso en vez del formulario). */
    public record Publica(String nombre, String nombreCorto, String logoVersion, String estado) {}

    /** Lo que el ADMIN puede cambiar. Un campo vacio o ausente lo deja en blanco. */
    public record ActualizarEmpresaRequest(
            @Size(max = 200) String direccion,
            @Size(max = 40) String telefono,
            @Size(max = 80) String ciudad,
            @Size(max = 150) String correoContacto,
            @Size(max = 200) String pieComprobante,
            @NotBlank @Size(max = 30) String codigo) {}

    public record CodigoRequest(@NotBlank @Size(max = 30) String codigo) {}

    private final EmpresaService servicio;
    private final ConfirmacionSegundoFactor confirmacion;
    private final Imagenes imagenes;

    public EmpresaController(EmpresaService servicio, ConfirmacionSegundoFactor confirmacion, Imagenes imagenes) {
        this.servicio = servicio;
        this.confirmacion = confirmacion;
        this.imagenes = imagenes;
    }

    @GetMapping
    public EmpresaDto empresa() {
        List<ModuloDto> modulos = servicio.modulos().stream().map(EmpresaController::dto).toList();
        List<String> activos = modulos.stream().filter(ModuloDto::activo).map(ModuloDto::codigo).toList();
        return new EmpresaDto(servicio.datos(), modulos, activos, servicio.versionEsquema(), servicio.logoVersion());
    }

    @GetMapping("/publica")
    public ResponseEntity<Publica> publica() {
        Datos d = servicio.datos();
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(new Publica(d.nombre(), d.nombreCorto(), servicio.logoVersion(), servicio.estado()));
    }

    /** Sin sesion (lo muestra el login). 404 si no hay logo; 304 si el navegador ya tiene esa version (ETag). */
    @GetMapping("/logo")
    public ResponseEntity<byte[]> logo(WebRequest req) {
        Logo l = servicio.logo().orElseThrow(() -> SilaException.noEncontrado("La empresa no tiene logo."));
        if (req.checkNotModified('"' + l.sha256() + '"')) return null;
        return ResponseEntity.ok().eTag(l.sha256()).cacheControl(CacheControl.noCache())
                .contentType(MediaType.parseMediaType(l.tipo())).body(l.contenido());
    }

    /** ADMIN. Datos de contacto y pie del comprobante (no nombre ni NIT). */
    @PutMapping
    public EmpresaDto actualizar(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody ActualizarEmpresaRequest r,
                                 HttpServletRequest req) {
        confirmacion.exigir(jwt, r.codigo(), ip(req), agente(req));
        servicio.actualizarContacto(r.direccion(), r.telefono(), r.ciudad(), r.correoContacto(), r.pieComprobante());
        return empresa();
    }

    /** ADMIN. multipart: {@code archivo} (PNG o JPG, hasta 5 MB) y {@code codigo}. Pasa por el antivirus; se guarda recodificado a 480 px como maximo. */
    @PutMapping(value = "/logo", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public EmpresaDto subirLogo(@AuthenticationPrincipal Jwt jwt, @RequestParam("archivo") MultipartFile archivo,
                                @RequestParam("codigo") String codigo, HttpServletRequest req) throws IOException {
        confirmacion.exigir(jwt, codigo, ip(req), agente(req));
        servicio.fijarLogo(imagenes.logo(archivo.getBytes()));
        return empresa();
    }

    /** ADMIN. */
    @DeleteMapping("/logo")
    public EmpresaDto quitarLogo(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody CodigoRequest r, HttpServletRequest req) {
        confirmacion.exigir(jwt, r.codigo(), ip(req), agente(req));
        servicio.quitarLogo();
        return empresa();
    }

    private static ModuloDto dto(Modulo m) {
        return new ModuloDto(m.codigo(), m.nombre(), m.descripcion(), m.nucleo() == 1, m.activo() == 1);
    }
}
