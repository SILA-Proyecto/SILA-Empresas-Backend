package com.llanolat.sila.catalogos.controller;

import com.llanolat.sila.catalogos.dto.CrearCategoriaGastoRequest;
import com.llanolat.sila.catalogos.repository.CatalogoRepository;
import com.llanolat.sila.consultas.controller.ConsultaController;
import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * ESCRITURA de categorias de gasto (los periodos estan en periodos/PeriodoController). Proveedores y productos estan en
 * CatalogoController (contrato del dashboard, /api/v1/catalogos).
 * Las consultas (GET) de estas mismas entidades estan en ConsultaController.
 */
@RestController
@RequestMapping("/api/v1")
public class PeriodoFinanzaController {

    private final CatalogoRepository repo;

    public PeriodoFinanzaController(CatalogoRepository repo) { this.repo = repo; }

    // ---------- finanzas ----------

    @PostMapping("/finanzas/categorias")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> crearCategoria(@Valid @RequestBody CrearCategoriaGastoRequest r) {
        return Map.of("id", repo.crearCategoriaGasto(r.nombre()));
    }

    @DeleteMapping("/finanzas/categorias/{id}")
    public ResponseEntity<Void> desactivarCategoria(@PathVariable long id) {
        repo.cambiarEstado("CATEGORIA_GASTO", id, false);
        return ResponseEntity.noContent().build();
    }
}
