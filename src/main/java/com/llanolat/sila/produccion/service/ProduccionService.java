package com.llanolat.sila.produccion.service;

import com.llanolat.sila.infra.Fechas;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.produccion.dto.ProduccionDtos.Ajuste;
import com.llanolat.sila.produccion.dto.ProduccionDtos.CrearAjusteRequest;
import com.llanolat.sila.produccion.dto.ProduccionDtos.CrearLoteRequest;
import com.llanolat.sila.produccion.dto.ProduccionDtos.Lote;
import com.llanolat.sila.produccion.repository.ProduccionRepository;
import java.time.LocalDate;
import org.springframework.stereotype.Service;

/** Orquesta, no decide: stock, rol por tipo de ajuste y periodo abierto los resuelve Oracle. */
@Service
public class ProduccionService {

    private final ProduccionRepository repo;

    public ProduccionService(ProduccionRepository repo) { this.repo = repo; }

    public Lote crearLote(CrearLoteRequest r) {
        LocalDate fecha = Fechas.deOHoy(r.fechaProduccion(), "fecha_produccion");
        if (r.fechaVencimiento() != null && r.fechaVencimiento().isBefore(fecha)) {
            throw SilaException.parametroInvalido("El vencimiento no puede ser anterior a la produccion.", "fecha_vencimiento");
        }
        long id = repo.registrarLote(r.idProducto(), r.litrosLecheUsados(), r.cantidadObtenida(),
                r.costoPorLitro(), fecha, r.fechaVencimiento());
        return repo.lote(id).orElseThrow(() -> SilaException.noEncontrado("El lote no existe."));
    }

    public Ajuste crearAjuste(CrearAjusteRequest r) {
        long id = repo.registrarAjuste(r.idProducto(), r.tipoAjuste(), r.cantidad(), r.observacion().trim());
        return repo.ajuste(id).orElseThrow(() -> SilaException.noEncontrado("El ajuste no existe."));
    }
}
