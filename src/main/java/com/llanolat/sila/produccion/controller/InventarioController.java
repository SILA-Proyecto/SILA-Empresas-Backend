package com.llanolat.sila.produccion.controller;

import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.produccion.dto.ProduccionDtos.AlertaCaducidad;
import com.llanolat.sila.produccion.dto.ProduccionDtos.ItemInventario;
import com.llanolat.sila.produccion.dto.ProduccionDtos.ResumenInventario;
import com.llanolat.sila.produccion.repository.ProduccionRepository;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Lectura del inventario: /api/v1/inventario. El stock es por producto (no por lote). */
@RestController
@RequestMapping("/api/v1/inventario")
public class InventarioController {

    private final ProduccionRepository repo;

    public InventarioController(ProduccionRepository repo) { this.repo = repo; }

    @GetMapping
    public Page<ItemInventario> inventario(
            @RequestParam(required = false) String texto,
            @RequestParam(name = "solo_con_stock", defaultValue = "false") boolean soloConStock,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.inventario(texto, soloConStock, page, size, sort);
    }

    @GetMapping("/resumen")
    public ResumenInventario resumen() {
        return repo.resumenInventario();
    }

    /** Lotes que vencen en los proximos {@code dias_maximos} (7 por defecto) o vencieron hace menos de {@code dias_vencidos} (30). */
    @GetMapping("/alertas-caducidad")
    public Page<AlertaCaducidad> alertas(
            @RequestParam(name = "dias_maximos", defaultValue = "7") int diasMaximos,
            @RequestParam(name = "dias_vencidos", defaultValue = "30") int diasVencidos,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        if (diasMaximos < 0 || diasMaximos > 60) throw SilaException.parametroInvalido("dias_maximos debe estar entre 0 y 60.");
        if (diasVencidos < 0 || diasVencidos > 365) throw SilaException.parametroInvalido("dias_vencidos debe estar entre 0 y 365.");
        return repo.alertas(-diasVencidos, diasMaximos, page, size, sort);
    }
}
