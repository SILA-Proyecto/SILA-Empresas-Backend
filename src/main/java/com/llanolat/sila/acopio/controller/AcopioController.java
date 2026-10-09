package com.llanolat.sila.acopio.controller;

import com.llanolat.sila.acopio.dto.CuentasProveedorDto.AnularPagoRequest;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.FijarPrecioRequest;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PagoProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PrecioProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.RegistrarPagoRequest;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.SaldoProveedor;
import com.llanolat.sila.acopio.dto.RecepcionDto;
import com.llanolat.sila.acopio.dto.RegistrarRecepcionRequest;
import com.llanolat.sila.acopio.dto.ResumenesAcopioDto.CalidadProveedor;
import com.llanolat.sila.acopio.dto.ResumenesAcopioDto.PagoLechero;
import com.llanolat.sila.acopio.dto.ResumenesAcopioDto.Umbrales;
import com.llanolat.sila.acopio.repository.AcopioRepository;
import com.llanolat.sila.acopio.service.AcopioService;
import com.llanolat.sila.infra.Page;
import jakarta.validation.Valid;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * Contrato del dashboard para Acopio: /api/v1/acopio. Ver docs/CONTRATO_BACKEND.md.
 * Registrar una recepcion exige Idempotency-Key (la lista de rutas obligatorias esta en application.yml).
 */
@RestController
@RequestMapping("/api/v1/acopio")
public class AcopioController {

    private final AcopioService service;
    private final AcopioRepository repo;

    public AcopioController(AcopioService service, AcopioRepository repo) {
        this.service = service;
        this.repo = repo;
    }

    @GetMapping("/recepciones")
    public Page<RecepcionDto> recepciones(
            @RequestParam(name = "id_proveedor", required = false) Long idProveedor,
            @RequestParam(name = "estado_calidad", required = false) String estadoCalidad,
            @RequestParam(name = "id_periodo", required = false) Long idPeriodo,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.recepciones(idProveedor, estadoCalidad, desde, hasta, idPeriodo, page, size, sort);
    }

    /** OPERATIVO. 201 con la recepcion; si la leche no cumple los umbrales viene con estado_calidad RECHAZADO. */
    @PostMapping("/recepciones")
    @ResponseStatus(HttpStatus.CREATED)
    public RecepcionDto registrar(@Valid @RequestBody RegistrarRecepcionRequest r) {
        return service.registrar(r);
    }

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

    @GetMapping("/pago-lecheros")
    public Page<PagoLechero> pagoLecheros(
            @RequestParam(name = "id_periodo", required = false) Long idPeriodo,
            @RequestParam(required = false) Integer anio,
            @RequestParam(name = "id_proveedor", required = false) Long idProveedor,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.pagoLecheros(idPeriodo, anio, idProveedor, page, size, sort);
    }

    // ---------- cuentas con los lecheros ----------

    /** Historial de precios por litro. solo_vigentes=true deja el precio que rige hoy de cada lechero. */
    @GetMapping("/precios")
    public Page<PrecioProveedor> precios(
            @RequestParam(name = "id_proveedor", required = false) Long idProveedor,
            @RequestParam(name = "solo_vigentes", defaultValue = "false") boolean soloVigentes,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.precios(idProveedor, soloVigentes, page, size, sort);
    }

    /** ADMIN. Fija el precio por litro desde una fecha (vigente_desde opcional = hoy). Solo rige hacia adelante. */
    @PostMapping("/precios")
    @ResponseStatus(HttpStatus.CREATED)
    public PrecioProveedor fijarPrecio(@Valid @RequestBody FijarPrecioRequest r) {
        return service.fijarPrecio(r);
    }

    /** Cuanto se le debe a cada lechero en total. solo_con_saldo=true oculta a los que estan al dia. */
    @GetMapping("/saldos")
    public Page<SaldoProveedor> saldos(
            @RequestParam(name = "solo_con_saldo", required = false) Boolean soloConSaldo,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.saldos(soloConSaldo, page, size, sort);
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

    /** ADMIN. Paga (todo o parte) la leche de una quincena. 400/20005 si supera su saldo. */
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
