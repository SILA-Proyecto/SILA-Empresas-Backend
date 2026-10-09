package com.llanolat.sila.ventas.controller;

import com.llanolat.sila.infra.Page;
import com.llanolat.sila.ventas.dto.VentasDtos.AnularRequest;
import com.llanolat.sila.ventas.dto.VentasDtos.CrearVentaRequest;
import com.llanolat.sila.ventas.dto.VentasDtos.PrecioAplicable;
import com.llanolat.sila.ventas.dto.VentasDtos.Venta;
import com.llanolat.sila.ventas.dto.VentasDtos.VentaDetalle;
import com.llanolat.sila.ventas.repository.VentaRepository;
import com.llanolat.sila.ventas.service.VentaService;
import jakarta.validation.Valid;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * Contrato del dashboard para Ventas: /api/v1/ventas. Ver docs/CONTRATO_BACKEND.md.
 * Registrar y anular una venta exigen Idempotency-Key. La anulacion es solo ADMIN.
 */
@RestController
@RequestMapping("/api/v1/ventas")
public class VentaController {

    private final VentaService service;
    private final VentaRepository repo;

    public VentaController(VentaService service, VentaRepository repo) {
        this.service = service;
        this.repo = repo;
    }

    @GetMapping
    public Page<Venta> listar(
            @RequestParam(required = false) String texto,
            @RequestParam(name = "id_cliente", required = false) Long idCliente,
            @RequestParam(name = "estado_pago", required = false) String estadoPago,
            @RequestParam(name = "tipo_venta", required = false) String tipoVenta,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.listar(texto, idCliente, estadoPago, tipoVenta, desde, hasta, page, size, sort);
    }

    @GetMapping("/{id}")
    public VentaDetalle detalle(@PathVariable long id) {
        return service.detalle(id);
    }

    /** OPERATIVO. 201 con la venta completa (lineas y pagos). */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public VentaDetalle registrar(@Valid @RequestBody CrearVentaRequest r) {
        return service.registrar(r);
    }

    /** ADMIN. Con motivo (10 a 255 caracteres). */
    @PostMapping("/{id}/anular")
    public VentaDetalle anular(@PathVariable long id, @Valid @RequestBody AnularRequest r) {
        return service.anular(id, r.motivo());
    }

    /** Punto de venta: los productos con el precio que se le cobra a ese cliente. */
    @GetMapping("/precios")
    public Page<PrecioAplicable> precios(
            @RequestParam(name = "id_cliente") long idCliente,
            @RequestParam(required = false) String texto,
            @RequestParam(name = "solo_con_stock", defaultValue = "false") boolean soloConStock,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.preciosAplicables(idCliente, texto, soloConStock, page, size, sort);
    }
}
