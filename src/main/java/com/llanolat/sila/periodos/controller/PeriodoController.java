package com.llanolat.sila.periodos.controller;

import com.llanolat.sila.infra.Page;
import com.llanolat.sila.periodos.dto.CambiarEstadoPeriodoRequest;
import com.llanolat.sila.periodos.dto.CrearPeriodosResponse;
import com.llanolat.sila.periodos.dto.PeriodoDto;
import com.llanolat.sila.periodos.service.PeriodoService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * Contrato del dashboard para Periodos: /api/v1/periodos. Ver docs/CONTRATO_BACKEND.md.
 * Las rutas fijas (anios, actual) se declaran antes que /{id}.
 */
@RestController
@RequestMapping("/api/v1/periodos")
public class PeriodoController {

    private final PeriodoService service;

    public PeriodoController(PeriodoService service) { this.service = service; }

    @GetMapping
    public Page<PeriodoDto> listar(
            @RequestParam(required = false) Integer anio,
            @RequestParam(required = false) String estado,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return service.listar(anio, estado, page, size, sort);
    }

    /** Anios con quincenas creadas: alimenta el selector de anio. */
    @GetMapping("/anios")
    public List<Integer> anios() {
        return service.anios();
    }

    /** La quincena de hoy (chip de la barra superior). 404 / 20007 si no hay periodos creados. */
    @GetMapping("/actual")
    public PeriodoDto actual() {
        return service.actual();
    }

    @GetMapping("/{id}")
    public PeriodoDto obtener(@PathVariable long id) {
        return service.obtener(id);
    }

    /** ADMIN. Crea las 24 quincenas del anio. 201 si creo alguna, 200 si ya existian todas. */
    @PostMapping("/anio/{anio}")
    public ResponseEntity<CrearPeriodosResponse> crearAnio(@PathVariable int anio) {
        CrearPeriodosResponse r = service.crearAnio(anio);
        return ResponseEntity.status(r.creados() > 0 ? HttpStatus.CREATED : HttpStatus.OK).body(r);
    }

    /** ADMIN. Cerrar o reabrir (la reapertura exige motivo). Devuelve la quincena completa. */
    @PatchMapping("/{id}/estado")
    public PeriodoDto cambiarEstado(@PathVariable long id, @Valid @RequestBody CambiarEstadoPeriodoRequest r) {
        return service.cambiarEstado(id, r);
    }
}
