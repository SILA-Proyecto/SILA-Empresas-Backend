package com.llanolat.sila.insumos.controller;

import com.llanolat.sila.insumos.dto.InsumosDtos.DefinirRecetaRequest;
import com.llanolat.sila.insumos.dto.InsumosDtos.Receta;
import com.llanolat.sila.insumos.service.InsumoService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

/** Receta de un producto: que insumos gasta UNA unidad y cuanto cuestan. Ver tambien POST /catalogos/productos (con receta). */
@RestController
@RequestMapping("/api/v1/catalogos/productos/{id}/receta")
public class RecetaController {

    private final InsumoService service;

    public RecetaController(InsumoService service) { this.service = service; }

    @GetMapping
    public Receta receta(@PathVariable long id) { return service.receta(id); }

    /** ADMIN. Reemplaza la receta completa; {"lineas": []} la deja vacia. */
    @PutMapping
    public Receta definir(@PathVariable long id, @Valid @RequestBody DefinirRecetaRequest r) {
        return service.definirReceta(id, r.lineas());
    }
}
