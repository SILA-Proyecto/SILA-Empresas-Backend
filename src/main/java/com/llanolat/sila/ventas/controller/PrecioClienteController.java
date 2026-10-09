package com.llanolat.sila.ventas.controller;

import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.ventas.dto.VentasDtos.DesactivarPrecioRequest;
import com.llanolat.sila.ventas.dto.VentasDtos.FijarPrecioRequest;
import com.llanolat.sila.ventas.dto.VentasDtos.PrecioCliente;
import com.llanolat.sila.ventas.repository.VentaRepository;
import com.llanolat.sila.ventas.service.VentaService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

/** Precios pactados por cliente: /api/v1/precios-cliente. Lectura para todos; fijar y desactivar, solo ADMIN. */
@RestController
@RequestMapping("/api/v1/precios-cliente")
public class PrecioClienteController {

    private final VentaService service;
    private final VentaRepository repo;

    public PrecioClienteController(VentaService service, VentaRepository repo) {
        this.service = service;
        this.repo = repo;
    }

    @GetMapping
    public Page<PrecioCliente> listar(
            @RequestParam(name = "id_cliente", required = false) Long idCliente,
            @RequestParam(name = "id_producto", required = false) Long idProducto,
            @RequestParam(required = false) Boolean activo,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.preciosCliente(idCliente, idProducto, activo, page, size, sort);
    }

    /** ADMIN. Crea el acuerdo o actualiza su precio (y lo deja activo). */
    @PutMapping
    public PrecioCliente fijar(@Valid @RequestBody FijarPrecioRequest r) {
        return service.fijarPrecio(r);
    }

    /** ADMIN. Solo se puede desactivar ({@code activo: false}); para reactivar se vuelve a fijar el precio con PUT. */
    @PatchMapping("/{id}/estado")
    public PrecioCliente estado(@PathVariable long id, @Valid @RequestBody DesactivarPrecioRequest r) {
        if (Boolean.TRUE.equals(r.activo())) {
            throw SilaException.parametroInvalido("Para reactivar un precio, fijelo de nuevo con PUT /precios-cliente.", "activo");
        }
        return service.quitarPrecio(id);
    }
}
