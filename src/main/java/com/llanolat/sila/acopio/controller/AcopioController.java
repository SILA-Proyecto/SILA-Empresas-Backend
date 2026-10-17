package com.llanolat.sila.acopio.controller;

import com.llanolat.sila.acopio.dto.ResumenesAcopioDto.CalidadProveedor;
import com.llanolat.sila.acopio.dto.ResumenesAcopioDto.Umbrales;
import com.llanolat.sila.acopio.repository.AcopioRepository;
import com.llanolat.sila.infra.Page;
import org.springframework.web.bind.annotation.*;

/**
 * Acopio de leche: /api/v1/acopio. Solo lectura. La entrega de leche se registra como compra de la materia prima
 * LECHE (POST /api/v1/insumos/compras, OPERATIVO, con temperatura y acidez).
 */
@RestController
@RequestMapping("/api/v1/acopio")
public class AcopioController {

    private final AcopioRepository repo;

    public AcopioController(AcopioRepository repo) { this.repo = repo; }

    /** Limites vigentes de temperatura y acidez, para avisar antes de enviar. */
    @GetMapping("/umbrales")
    public Umbrales umbrales() {
        return repo.umbrales();
    }

    @GetMapping("/calidad")
    public Page<CalidadProveedor> calidad(
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.calidad(page, size, sort);
    }
}
