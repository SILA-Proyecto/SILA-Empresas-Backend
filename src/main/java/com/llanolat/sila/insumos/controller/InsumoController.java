package com.llanolat.sila.insumos.controller;

import com.llanolat.sila.catalogos.dto.CambiarEstadoRequest;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.insumos.dto.InsumosDtos.*;
import com.llanolat.sila.insumos.repository.InsumoRepository;
import com.llanolat.sila.insumos.service.InsumoService;
import jakarta.validation.Valid;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * Insumos (azucar, envases...) con stock y costo promedio: /api/v1/insumos. Crear, editar, comprar y anular: ADMIN.
 * Los ajustes de resta (MERMA, DANO, VENCIMIENTO) los puede hacer OPERATIVO. Compras y ajustes (mueven stock y dinero) exigen Idempotency-Key.
 */
@RestController
@RequestMapping("/api/v1/insumos")
public class InsumoController {

    private final InsumoService service;
    private final InsumoRepository repo;

    public InsumoController(InsumoService service, InsumoRepository repo) {
        this.service = service;
        this.repo = repo;
    }

    @GetMapping
    public Page<Insumo> listar(
            @RequestParam(required = false) String texto,
            @RequestParam(required = false) Boolean activo,
            @RequestParam(name = "bajo_minimo", required = false, defaultValue = "false") boolean bajoMinimo,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.insumos(texto, activo, bajoMinimo, page, size, sort);
    }

    @GetMapping("/resumen")
    public ResumenInsumos resumen() { return repo.resumen(); }

    @GetMapping("/{id}")
    public Insumo obtener(@PathVariable long id) { return service.insumo(id); }

    /** ADMIN. */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Insumo crear(@Valid @RequestBody CrearInsumoRequest r) { return service.crear(r); }

    /** ADMIN. La unidad solo cambia si el insumo no tiene movimientos ni esta en recetas (ORA-20006). */
    @PutMapping("/{id}")
    public Insumo actualizar(@PathVariable long id, @Valid @RequestBody ActualizarInsumoRequest r) {
        return service.actualizar(id, r);
    }

    /** ADMIN. No se desactiva un insumo que esta en la receta de un producto activo (ORA-20006). */
    @PatchMapping("/{id}/estado")
    public Insumo estado(@PathVariable long id, @Valid @RequestBody CambiarEstadoRequest r) {
        return service.cambiarEstado(id, r.activo());
    }

    // ---------- compras ----------

    @GetMapping("/compras")
    public Page<Compra> compras(
            @RequestParam(name = "id_insumo", required = false) Long idInsumo,
            @RequestParam(name = "id_proveedor", required = false) Long idProveedor,
            @RequestParam(required = false) String estado,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.compras(idInsumo, idProveedor, estado, desde, hasta, page, size, sort);
    }

    /** ADMIN. Suma al stock y recalcula el costo promedio ponderado. */
    @PostMapping("/compras")
    @ResponseStatus(HttpStatus.CREATED)
    public Compra comprar(@Valid @RequestBody CrearCompraRequest r) { return service.comprar(r); }

    /** ADMIN. Solo si el stock alcanza para devolver lo comprado (ORA-20002 si ya se gasto). */
    @PostMapping("/compras/{id}/anular")
    public Compra anular(@PathVariable long id, @Valid @RequestBody AnularCompraRequest r) {
        return service.anularCompra(id, r.motivo());
    }

    // ---------- ajustes ----------

    @GetMapping("/ajustes")
    public Page<AjusteInsumo> ajustes(
            @RequestParam(name = "id_insumo", required = false) Long idInsumo,
            @RequestParam(name = "tipo_ajuste", required = false) String tipo,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.ajustes(idInsumo, tipo, desde, hasta, page, size, sort);
    }

    /** MERMA, DANO, VENCIMIENTO: OPERATIVO. CORRECCION_MAS y CORRECCION_MENOS: ADMIN (403/20008 si no). */
    @PostMapping("/ajustes")
    @ResponseStatus(HttpStatus.CREATED)
    public AjusteInsumo ajustar(@Valid @RequestBody CrearAjusteInsumoRequest r) { return service.ajustar(r); }

    // ---------- consumos por lote ----------

    /** Lo que gasto un lote de produccion, con el costo congelado al producirlo. */
    @GetMapping("/consumos")
    public List<ConsumoLote> consumos(@RequestParam(name = "id_lote") long idLote) {
        return repo.consumosDelLote(idLote);
    }
}
