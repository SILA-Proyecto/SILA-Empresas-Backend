package com.llanolat.sila.produccion.controller;

import com.llanolat.sila.infra.Page;
import com.llanolat.sila.produccion.dto.ProduccionDtos.Ajuste;
import com.llanolat.sila.produccion.dto.ProduccionDtos.CrearAjusteRequest;
import com.llanolat.sila.produccion.dto.ProduccionDtos.CrearLoteRequest;
import com.llanolat.sila.produccion.dto.ProduccionDtos.Lote;
import com.llanolat.sila.produccion.repository.ProduccionRepository;
import com.llanolat.sila.produccion.service.ProduccionService;
import jakarta.validation.Valid;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * Contrato del dashboard para Produccion: /api/v1/produccion. Ver docs/CONTRATO_BACKEND.md.
 * Crear un lote o un ajuste mueve stock: exige Idempotency-Key.
 */
@RestController
@RequestMapping("/api/v1/produccion")
public class ProduccionController {

    private final ProduccionService service;
    private final ProduccionRepository repo;

    public ProduccionController(ProduccionService service, ProduccionRepository repo) {
        this.service = service;
        this.repo = repo;
    }

    @GetMapping("/lotes")
    public Page<Lote> lotes(
            @RequestParam(required = false) String texto,
            @RequestParam(name = "id_producto", required = false) Long idProducto,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.lotes(texto, idProducto, desde, hasta, page, size, sort);
    }

    /** OPERATIVO. Suma al stock del producto. */
    @PostMapping("/lotes")
    @ResponseStatus(HttpStatus.CREATED)
    public Lote crearLote(@Valid @RequestBody CrearLoteRequest r) {
        return service.crearLote(r);
    }

    @GetMapping("/ajustes")
    public Page<Ajuste> ajustes(
            @RequestParam(name = "id_producto", required = false) Long idProducto,
            @RequestParam(name = "tipo_ajuste", required = false) String tipoAjuste,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.ajustes(idProducto, tipoAjuste, desde, hasta, page, size, sort);
    }

    /** MERMA, DANO, VENCIMIENTO, MUESTRA: OPERATIVO. INGRESO_INICIAL, CORRECCION_MAS y CORRECCION_MENOS: ADMIN (403/20008 si no). */
    @PostMapping("/ajustes")
    @ResponseStatus(HttpStatus.CREATED)
    public Ajuste crearAjuste(@Valid @RequestBody CrearAjusteRequest r) {
        return service.crearAjuste(r);
    }
}
