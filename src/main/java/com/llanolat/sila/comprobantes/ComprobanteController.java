package com.llanolat.sila.comprobantes;

import com.llanolat.sila.comprobantes.Comprobantes.Comprobante;
import com.llanolat.sila.comprobantes.Comprobantes.Detalle;
import com.llanolat.sila.comprobantes.Comprobantes.Resumen;
import com.llanolat.sila.infra.Page;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Comprobantes: /api/v1/comprobantes. Solo lectura, cualquier usuario autenticado. Ver docs/CONTRATO_BACKEND.md. */
@RestController
@RequestMapping("/api/v1/comprobantes")
public class ComprobanteController {

    private final ComprobanteRepository repo;

    public ComprobanteController(ComprobanteRepository repo) { this.repo = repo; }

    @GetMapping
    public Page<Comprobante> listar(
            @RequestParam(required = false) String tipo,
            @RequestParam(required = false) String sentido,
            @RequestParam(required = false) String estado,
            @RequestParam(name = "id_periodo", required = false) Long idPeriodo,
            @RequestParam(required = false) String texto,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Integer page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {
        return repo.listar(tipo, sentido, estado, idPeriodo, texto, desde, hasta, page, size, sort);
    }

    @GetMapping("/resumen")
    public Resumen resumen(
            @RequestParam(required = false) String tipo,
            @RequestParam(required = false) String sentido,
            @RequestParam(name = "id_periodo", required = false) Long idPeriodo,
            @RequestParam(required = false) String texto,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta) {
        return repo.resumen(tipo, sentido, idPeriodo, texto, desde, hasta);
    }

    /** {tipo}: VENTA, ABONO (id = id_recibo), PAGO_PROVEEDOR, COMPRA o GASTO. */
    @GetMapping("/{tipo}/{id}")
    public Detalle detalle(@PathVariable String tipo, @PathVariable long id) {
        return repo.detalle(tipo, id);
    }
}
