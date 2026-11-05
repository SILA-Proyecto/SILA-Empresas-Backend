package com.llanolat.sila.fotos;

import com.llanolat.sila.archivos.Imagenes;
import com.llanolat.sila.fotos.FotoRepository.Foto;
import com.llanolat.sila.infra.SilaException;
import java.io.IOException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.multipart.MultipartFile;

/**
 * Foto de perfil: /api/v1/fotos. Cada usuario sube y quita la SUYA ({@code /yo}); cualquier usuario con sesion puede ver la
 * de otro (para mostrarla en listas); solo el ADMIN puede quitar la de otro, nunca subirla por el. Las imagenes piden token,
 * asi que el dashboard las trae con su cliente HTTP (no con un {@code <img src>} directo). Ver docs/CONTRATO_EMPRESA.md.
 */
@RestController
@RequestMapping("/api/v1/fotos")
class FotoController {

    record FotoVersion(String fotoVersion) {}

    private final FotoRepository repo;
    private final Imagenes imagenes;

    FotoController(FotoRepository repo, Imagenes imagenes) {
        this.repo = repo;
        this.imagenes = imagenes;
    }

    @GetMapping("/yo")
    ResponseEntity<byte[]> mia(@AuthenticationPrincipal Jwt jwt, WebRequest req) {
        return servir(idDe(jwt), req);
    }

    /** multipart: {@code archivo} (PNG o JPG, hasta 5 MB). Pasa por el antivirus; se guarda recortada al cuadrado y a 256 px. */
    @PutMapping(value = "/yo", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    FotoVersion subir(@AuthenticationPrincipal Jwt jwt, @RequestParam("archivo") MultipartFile archivo) throws IOException {
        long id = idDe(jwt);
        repo.fijarMia(imagenes.foto(archivo.getBytes()));
        return new FotoVersion(repo.version(id).orElse(null));
    }

    @DeleteMapping("/yo")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void quitarMia(@AuthenticationPrincipal Jwt jwt) {
        repo.quitar(idDe(jwt));
    }

    @GetMapping("/{id:\\d+}")
    ResponseEntity<byte[]> de(@PathVariable long id, WebRequest req) {
        return servir(id, req);
    }

    /** ADMIN: quitar la foto de otra persona (p. ej. una imagen inapropiada). */
    @DeleteMapping("/{id:\\d+}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void quitar(@PathVariable long id) {
        repo.quitar(id);
    }

    private ResponseEntity<byte[]> servir(long id, WebRequest req) {
        Foto f = repo.de(id).orElseThrow(() -> SilaException.noEncontrado("Ese usuario no tiene foto."));
        if (req.checkNotModified('"' + f.sha256() + '"')) return null;
        return ResponseEntity.ok().eTag(f.sha256()).cacheControl(CacheControl.noCache().cachePrivate())
                .contentType(MediaType.parseMediaType(f.tipo())).body(f.contenido());
    }

    private static long idDe(Jwt jwt) {
        Object uid = jwt == null ? null : jwt.getClaim("uid");
        if (!(uid instanceof Number id)) throw SilaException.de(SilaException.AUTENTICACION, "Sesion invalida.");
        return id.longValue();
    }
}
