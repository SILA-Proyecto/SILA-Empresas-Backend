package com.llanolat.sila.documentos.controller;

import com.llanolat.sila.documentos.dto.DocumentosDtos.*;
import com.llanolat.sila.documentos.repository.DocumentoRepository;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.SilaException;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * Registro de documentos para Google Drive: /api/v1/documentos. El backend lleva la cola y el resultado (PENDIENTE,
 * SUBIDO, ERROR); la subida real a Drive la hace quien llama y reporta aqui el resultado. Escrituras: OPERATIVO.
 * (GET /documentos/pendientes, de ConsultaController, sigue devolviendo la cola sin paginar.)
 */
@RestController
@RequestMapping("/api/v1/documentos")
public class DocumentoController {

    private final DocumentoRepository repo;

    public DocumentoController(DocumentoRepository repo) { this.repo = repo; }

    @GetMapping
    public Page<Documento> listar(
            @RequestParam(name = "tipo_entidad", required = false) String tipoEntidad,
            @RequestParam(name = "id_entidad", required = false) Long idEntidad,
            @RequestParam(name = "estado_carga", required = false) String estadoCarga,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.documentos(tipoEntidad, idEntidad, estadoCarga, page, size, sort);
    }

    @GetMapping("/{id}")
    public Documento obtener(@PathVariable long id) { return leer(id); }

    /** Encola un documento PENDIENTE. 404/20007 si la factura, nota o recepcion no existe. */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Documento registrar(@Valid @RequestBody RegistrarDocumentoRequest r) {
        String mime = r.mimeType() == null || r.mimeType().isBlank() ? "application/pdf" : r.mimeType().trim();
        return leer(repo.registrarPendiente(r.tipoEntidad().trim().toUpperCase(), r.idEntidad(), r.nombreArchivo(), mime));
    }

    /** 409/20002 si ya estaba SUBIDO. */
    @PostMapping("/{id}/subido")
    public Documento subido(@PathVariable long id, @Valid @RequestBody MarcarSubidoRequest r) {
        repo.marcarSubido(id, r.driveFileId(), r.driveUrl(), r.checksumSha256());
        return leer(id);
    }

    /** Cuenta un intento fallido y guarda el mensaje; el documento sigue en la cola para reintentar. */
    @PostMapping("/{id}/error")
    public Documento error(@PathVariable long id, @Valid @RequestBody MarcarErrorRequest r) {
        repo.marcarError(id, r.mensaje());
        return leer(id);
    }

    private Documento leer(long id) {
        return repo.documento(id).orElseThrow(() -> SilaException.noEncontrado("El documento no existe."));
    }
}
