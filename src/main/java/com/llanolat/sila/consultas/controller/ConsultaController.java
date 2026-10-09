package com.llanolat.sila.consultas.controller;

import com.llanolat.sila.consultas.dto.CategoriasGastoDto;
import com.llanolat.sila.consultas.dto.DocumentosPendientesCargaDto;
import com.llanolat.sila.consultas.dto.FacturasDto;
import com.llanolat.sila.consultas.dto.GastosPorCategoriaDto;
import com.llanolat.sila.consultas.dto.ResolucionesFacturacionDto;
import com.llanolat.sila.consultas.repository.OperacionConsultaRepository;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.infra.SilaTemplate;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.*;

/**
 * Toda la capa de LECTURA.
 *
 * No pasa por SilaTemplate: las vistas estan otorgadas a rol_sila_app y no
 * verifican rol, asi que no hace falta abrir sesion de aplicacion. Son
 * consultas normales, y las cifras calculadas vienen ya resueltas por la vista.
 */
@RestController
@RequestMapping("/api/v1")
public class ConsultaController {

    private final OperacionConsultaRepository operaciones;

    public ConsultaController(OperacionConsultaRepository operaciones) {
        this.operaciones = operaciones;
    }

    // ===================== inventario y produccion =====================

    // ===================== facturacion =====================

    @GetMapping("/facturas")
    public List<FacturasDto> facturas(@RequestParam(required = false) String estadoDian,
                                      @RequestParam(required = false) Long idVenta) {
        return operaciones.facturas(estadoDian, idVenta);
    }

    @GetMapping("/facturacion/resoluciones")
    public List<ResolucionesFacturacionDto> resoluciones(
            @RequestParam(defaultValue = "false") boolean soloActivas) {
        return operaciones.resoluciones(soloActivas);
    }

    // ===================== finanzas =====================

    @GetMapping("/finanzas/categorias")
    public List<CategoriasGastoDto> categorias(
            @RequestParam(defaultValue = "true") boolean soloActivas) {
        return operaciones.categoriasGasto(soloActivas);
    }

    @GetMapping("/finanzas/gastos")
    public List<GastosPorCategoriaDto> gastos(@RequestParam(required = false) Long idPeriodo) {
        return operaciones.gastosPorCategoria(idPeriodo);
    }

    // ===================== documentos =====================

    @GetMapping("/documentos/pendientes")
    public List<DocumentosPendientesCargaDto> documentos(
            @RequestParam(required = false) String estado) {
        return operaciones.documentosPendientes(estado);
    }
}
