package com.llanolat.sila.cartera.controller;

import com.llanolat.sila.cartera.dto.CarteraDtos.Abono;
import com.llanolat.sila.cartera.dto.CarteraDtos.AbonoRequest;
import com.llanolat.sila.cartera.dto.CarteraDtos.CastigoRequest;
import com.llanolat.sila.cartera.dto.CarteraDtos.CastigoResultado;
import com.llanolat.sila.cartera.dto.CarteraDtos.ClienteCartera;
import com.llanolat.sila.cartera.dto.CarteraDtos.Recibo;
import com.llanolat.sila.cartera.dto.CarteraDtos.Resumen;
import com.llanolat.sila.cartera.dto.CarteraDtos.VentaPendiente;
import com.llanolat.sila.cartera.repository.CarteraRepository;
import com.llanolat.sila.infra.Page;
import jakarta.validation.Valid;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * Contrato del dashboard para Cartera: /api/v1/cartera. Ver docs/CONTRATO_BACKEND.md.
 * Registrar un abono o un castigo exige Idempotency-Key. El castigo es solo ADMIN.
 */
@RestController
@RequestMapping("/api/v1/cartera")
public class CarteraController {

    private final CarteraRepository repo;

    public CarteraController(CarteraRepository repo) { this.repo = repo; }

    @GetMapping("/clientes")
    public Page<ClienteCartera> clientes(
            @RequestParam(required = false) String texto,
            @RequestParam(name = "estado_credito", required = false) String estadoCredito,
            @RequestParam(name = "solo_con_deuda", defaultValue = "true") boolean soloConDeuda,
            @RequestParam(name = "mora_minima", required = false) Integer moraMinima,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.clientes(texto, estadoCredito, soloConDeuda, moraMinima, page, size, sort);
    }

    @GetMapping("/resumen")
    public Resumen resumen() {
        return repo.resumen();
    }

    /** Las ventas que ese cliente aun debe, de la mas antigua a la mas nueva (en ese orden se aplican los abonos). */
    @GetMapping("/clientes/{id}/ventas-pendientes")
    public List<VentaPendiente> ventasPendientes(@PathVariable long id) {
        return repo.ventasPendientes(id);
    }

    @GetMapping("/abonos")
    public Page<Abono> abonos(
            @RequestParam(name = "id_cliente", required = false) Long idCliente,
            @RequestParam(name = "id_venta", required = false) Long idVenta,
            @RequestParam(name = "id_recibo", required = false) Long idRecibo,
            @RequestParam(name = "metodo_pago", required = false) String metodoPago,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.abonos(idCliente, idVenta, idRecibo, metodoPago, desde, hasta, page, size, sort);
    }

    /** OPERATIVO. 201 con el recibo: como se repartio el pago entre las ventas y cuanto queda debiendo. */
    @PostMapping("/abonos")
    @ResponseStatus(HttpStatus.CREATED)
    public Recibo registrarAbono(@Valid @RequestBody AbonoRequest r) {
        var creado = repo.registrarAbono(r.idCliente(), r.monto(), r.metodoPago(), r.referencia());
        return new Recibo(creado.idRecibo(), creado.saldoRestante(), repo.abonosDeRecibo(creado.idRecibo()));
    }

    /** ADMIN. Da de baja toda la cartera pendiente del cliente (incobrable). */
    @PostMapping("/castigos")
    public CastigoResultado castigar(@Valid @RequestBody CastigoRequest r) {
        return new CastigoResultado(r.idCliente(), repo.castigar(r.idCliente(), r.motivo().trim()));
    }
}
