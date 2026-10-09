package com.llanolat.sila.catalogos.controller;

import com.llanolat.sila.catalogos.dto.ActualizarClienteRequest;
import com.llanolat.sila.catalogos.dto.ActualizarPrecioRequest;
import com.llanolat.sila.catalogos.dto.ActualizarProductoRequest;
import com.llanolat.sila.catalogos.dto.ActualizarProveedorRequest;
import com.llanolat.sila.catalogos.dto.CambiarEstadoRequest;
import com.llanolat.sila.catalogos.dto.ClienteDto;
import com.llanolat.sila.catalogos.dto.CrearClienteRequest;
import com.llanolat.sila.catalogos.dto.CrearProductoRequest;
import com.llanolat.sila.catalogos.dto.CrearProveedorRequest;
import com.llanolat.sila.catalogos.dto.ProductoDto;
import com.llanolat.sila.catalogos.dto.ProveedorDto;
import com.llanolat.sila.catalogos.service.CatalogoService;
import com.llanolat.sila.infra.Page;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * Contrato del dashboard para Catalogos: /api/v1/catalogos/...
 * Ver docs/CONTRATO_BACKEND.md. Toda escritura devuelve la entidad completa.
 * El rol que exige cada una lo verifica la base; aqui se anota para saber
 * que esperar un 403.
 */
@RestController
@RequestMapping("/api/v1/catalogos")
public class CatalogoController {

    private final CatalogoService service;

    public CatalogoController(CatalogoService service) { this.service = service; }

    // ---------- clientes ----------

    @GetMapping("/clientes")
    public Page<ClienteDto> listarClientes(
            @RequestParam(required = false) String texto,
            @RequestParam(required = false) Boolean activo,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return service.listarClientes(texto, activo, page, size, sort);
    }

    /** OPERATIVO (ADMIN si limite_credito > 0). */
    @PostMapping("/clientes")
    @ResponseStatus(HttpStatus.CREATED)
    public ClienteDto crearCliente(@Valid @RequestBody CrearClienteRequest r) {
        return service.crearCliente(r);
    }

    /** OPERATIVO (ADMIN si cambia limite_credito). */
    @PutMapping("/clientes/{id}")
    public ClienteDto actualizarCliente(@PathVariable long id, @Valid @RequestBody ActualizarClienteRequest r) {
        return service.actualizarCliente(id, r);
    }

    /** ADMIN. No borra: activa o desactiva. */
    @PatchMapping("/clientes/{id}/estado")
    public ClienteDto estadoCliente(@PathVariable long id, @Valid @RequestBody CambiarEstadoRequest r) {
        return service.cambiarEstadoCliente(id, r.activo());
    }

    // ---------- proveedores ----------

    @GetMapping("/proveedores")
    public Page<ProveedorDto> listarProveedores(
            @RequestParam(required = false) String texto,
            @RequestParam(name = "tipo_proveedor", required = false) String tipoProveedor,
            @RequestParam(required = false) Boolean activo,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return service.listarProveedores(texto, tipoProveedor, activo, page, size, sort);
    }

    /** OPERATIVO. */
    @PostMapping("/proveedores")
    @ResponseStatus(HttpStatus.CREATED)
    public ProveedorDto crearProveedor(@Valid @RequestBody CrearProveedorRequest r) {
        return service.crearProveedor(r);
    }

    /** OPERATIVO. Documento y tipo de proveedor no se editan. */
    @PutMapping("/proveedores/{id}")
    public ProveedorDto actualizarProveedor(@PathVariable long id, @Valid @RequestBody ActualizarProveedorRequest r) {
        return service.actualizarProveedor(id, r);
    }

    /** ADMIN. */
    @PatchMapping("/proveedores/{id}/estado")
    public ProveedorDto estadoProveedor(@PathVariable long id, @Valid @RequestBody CambiarEstadoRequest r) {
        return service.cambiarEstadoProveedor(id, r.activo());
    }

    // ---------- productos ----------

    @GetMapping("/productos")
    public Page<ProductoDto> listarProductos(
            @RequestParam(required = false) String texto,
            @RequestParam(required = false) Boolean activo,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return service.listarProductos(texto, activo, page, size, sort);
    }

    /** ADMIN. */
    @PostMapping("/productos")
    @ResponseStatus(HttpStatus.CREATED)
    public ProductoDto crearProducto(@Valid @RequestBody CrearProductoRequest r) {
        return service.crearProducto(r);
    }

    /** OPERATIVO. La unidad solo cambia si el producto no tiene movimientos (ORA-20006). */
    @PutMapping("/productos/{id}")
    public ProductoDto actualizarProducto(@PathVariable long id, @Valid @RequestBody ActualizarProductoRequest r) {
        return service.actualizarProducto(id, r);
    }

    /** ADMIN. Precio y tarifa de IVA cambian juntos (SUPUESTO C-07). */
    @PatchMapping("/productos/{id}/precio")
    public ProductoDto precioProducto(@PathVariable long id, @Valid @RequestBody ActualizarPrecioRequest r) {
        return service.cambiarPrecioProducto(id, r);
    }

    /** ADMIN. */
    @PatchMapping("/productos/{id}/estado")
    public ProductoDto estadoProducto(@PathVariable long id, @Valid @RequestBody CambiarEstadoRequest r) {
        return service.cambiarEstadoProducto(id, r.activo());
    }
}
