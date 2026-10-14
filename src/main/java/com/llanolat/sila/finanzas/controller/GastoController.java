package com.llanolat.sila.finanzas.controller;

import com.llanolat.sila.finanzas.dto.GastosDtos.AnularGastoRequest;
import com.llanolat.sila.finanzas.dto.GastosDtos.Gasto;
import com.llanolat.sila.finanzas.dto.GastosDtos.RegistrarGastoRequest;
import com.llanolat.sila.finanzas.dto.GastosDtos.ResumenGastos;
import com.llanolat.sila.finanzas.repository.GastoRepository;
import com.llanolat.sila.finanzas.service.GastoService;
import com.llanolat.sila.infra.Page;
import jakarta.validation.Valid;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * Gastos operativos: /api/v1/finanzas/gastos. Registrar: OPERATIVO, exige Idempotency-Key. Los gastos no se editan ni
 * se borran (la base lo impide): se anulan (ADMIN). Las categorias estan en catalogos/PeriodoFinanzaController.
 */
@RestController
@RequestMapping("/api/v1/finanzas/gastos")
public class GastoController {

    private final GastoService service;
    private final GastoRepository repo;

    public GastoController(GastoService service, GastoRepository repo) {
        this.service = service;
        this.repo = repo;
    }

    @GetMapping
    public Page<Gasto> listar(
            @RequestParam(name = "id_periodo", required = false) Long idPeriodo,
            @RequestParam(name = "id_categoria", required = false) Long idCategoria,
            @RequestParam(required = false) String texto,
            @RequestParam(required = false) String estado,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.gastos(idPeriodo, idCategoria, texto, estado, desde, hasta, page, size, sort);
    }

    /** Total y cantidad de los gastos VIGENTES con los filtros de la lista (los anulados no suman). */
    @GetMapping("/resumen")
    public ResumenGastos resumen(
            @RequestParam(name = "id_periodo", required = false) Long idPeriodo,
            @RequestParam(name = "id_categoria", required = false) Long idCategoria,
            @RequestParam(required = false) String texto,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta) {
        return repo.resumen(idPeriodo, idCategoria, texto, desde, hasta);
    }

    @GetMapping("/{id}")
    public Gasto obtener(@PathVariable long id) { return service.gasto(id); }

    /** OPERATIVO. 409/20010 si la quincena esta cerrada, 409/20006 si la categoria esta inactiva. */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Gasto registrar(@Valid @RequestBody RegistrarGastoRequest r) { return service.registrar(r); }

    /** ADMIN. Motivo de 10+ caracteres. 409/20010 si ya estaba anulado, 409/20004 si su quincena esta cerrada. */
    @PostMapping("/{id}/anular")
    public Gasto anular(@PathVariable long id, @Valid @RequestBody AnularGastoRequest r) {
        return service.anular(id, r.motivo());
    }
}
