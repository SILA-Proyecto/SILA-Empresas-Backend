package com.llanolat.sila.finanzas.service;

import com.llanolat.sila.finanzas.dto.GastosDtos.Gasto;
import com.llanolat.sila.finanzas.dto.GastosDtos.RegistrarGastoRequest;
import com.llanolat.sila.finanzas.repository.GastoRepository;
import com.llanolat.sila.infra.Fechas;
import com.llanolat.sila.infra.SilaException;
import org.springframework.stereotype.Service;

/** Orquesta, no decide: categoria activa, quincena abierta y monto los resuelve Oracle. */
@Service
public class GastoService {

    private final GastoRepository repo;

    private final com.llanolat.sila.archivos.ComprobanteArchivos archivos;

    public GastoService(GastoRepository repo, com.llanolat.sila.archivos.ComprobanteArchivos archivos) {
        this.repo = repo;
        this.archivos = archivos;
    }

    public Gasto registrar(RegistrarGastoRequest r) {
        // Fecha explicita en hora de Colombia: la base usaria UTC y de noche caeria en la quincena equivocada.
        long id = repo.registrar(r.idCategoria(), r.concepto(), r.monto(), Fechas.deOHoy(r.fechaGasto(), "fecha_gasto"));
        archivos.alRegistrar("GASTO", id);
        return gasto(id);
    }

    public Gasto anular(long id, String motivo) {
        repo.anular(id, motivo.trim());
        archivos.alAnular("GASTO", id);
        return gasto(id);
    }

    public Gasto gasto(long id) {
        return repo.gasto(id).orElseThrow(() -> SilaException.noEncontrado("El gasto no existe."));
    }
}
