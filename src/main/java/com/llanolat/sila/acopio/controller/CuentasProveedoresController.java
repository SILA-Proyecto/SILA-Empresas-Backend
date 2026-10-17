package com.llanolat.sila.acopio.controller;

import com.llanolat.sila.acopio.dto.CuentasProveedorDto.AnularPagoRequest;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.FijarPrecioRequest;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PagoProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PrecioProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.RegistrarPagoRequest;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.ResumenPagoProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.SaldoProveedor;
import com.llanolat.sila.acopio.repository.CuentasProveedoresRepository;
import com.llanolat.sila.acopio.service.CuentasProveedoresService;
import com.llanolat.sila.infra.Page;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * Cuentas con TODOS los proveedores: /api/v1/cuentas-proveedores. Se les paga por quincena lo comprado a credito
 * (las compras de contado no suman a la deuda). Las escrituras exigen Idempotency-Key y rol ADMIN.
 */
@RestController
@RequestMapping("/api/v1/cuentas-proveedores")
public class CuentasProveedoresController {

    private final CuentasProveedoresService service;
    private final CuentasProveedoresRepository repo;

    public CuentasProveedoresController(CuentasProveedoresService service, CuentasProveedoresRepository repo) {
        this.service = service;
        this.repo = repo;
    }

    /** Historial de precios pactados. solo_vigentes=true deja el precio que rige hoy de cada proveedor y materia prima. */
    @GetMapping("/precios")
    public Page<PrecioProveedor> precios(
            @RequestParam(name = "id_proveedor", required = false) Long idProveedor,
            @RequestParam(name = "id_insumo", required = false) Long idInsumo,
            @RequestParam(name = "solo_vigentes", defaultValue = "false") boolean soloVigentes,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.precios(idProveedor, idInsumo, soloVigentes, page, size, sort);
    }

    /** ADMIN. Fija el precio pactado de una materia prima con un proveedor desde una fecha (vigente_desde opcional = hoy). */
    @PostMapping("/precios")
    @ResponseStatus(HttpStatus.CREATED)
    public PrecioProveedor fijarPrecio(@Valid @RequestBody FijarPrecioRequest r) {
        return service.fijarPrecio(r);
    }

    /** Cuanto se le debe a cada proveedor en total. solo_con_saldo=true oculta a los que estan al dia. */
    @GetMapping("/saldos")
    public Page<SaldoProveedor> saldos(
            @RequestParam(name = "solo_con_saldo", required = false) Boolean soloConSaldo,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.saldos(soloConSaldo, page, size, sort);
    }

    /** Por quincena y proveedor: compras a credito, pagado y saldo. */
    @GetMapping("/resumen")
    public Page<ResumenPagoProveedor> resumen(
            @RequestParam(name = "id_periodo", required = false) Long idPeriodo,
            @RequestParam(required = false) Integer anio,
            @RequestParam(name = "id_proveedor", required = false) Long idProveedor,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.resumen(idPeriodo, anio, idProveedor, page, size, sort);
    }

    @GetMapping("/pagos")
    public Page<PagoProveedor> pagos(
            @RequestParam(name = "id_proveedor", required = false) Long idProveedor,
            @RequestParam(name = "id_periodo", required = false) Long idPeriodo,
            @RequestParam(name = "id_periodo_liquidado", required = false) Long idPeriodoLiquidado,
            @RequestParam(required = false) String estado,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.pagos(idProveedor, idPeriodo, idPeriodoLiquidado, estado, page, size, sort);
    }

    /** ADMIN. Paga (todo o parte) lo comprado a credito en una quincena. 400/20005 si supera su saldo. */
    @PostMapping("/pagos")
    @ResponseStatus(HttpStatus.CREATED)
    public PagoProveedor registrarPago(@Valid @RequestBody RegistrarPagoRequest r) {
        return service.registrarPago(r);
    }

    /** ADMIN. Motivo de 10 a 255 caracteres. */
    @PostMapping("/pagos/{id}/anular")
    public PagoProveedor anularPago(@PathVariable long id, @Valid @RequestBody AnularPagoRequest r) {
        return service.anularPago(id, r.motivo());
    }
}
