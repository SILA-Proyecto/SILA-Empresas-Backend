package com.llanolat.sila.periodos.service;

import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.periodos.dto.CambiarEstadoPeriodoRequest;
import com.llanolat.sila.periodos.dto.CrearPeriodosResponse;
import com.llanolat.sila.periodos.dto.PeriodoDto;
import com.llanolat.sila.periodos.repository.PeriodoConsultaRepository;
import com.llanolat.sila.periodos.repository.PeriodoRepository;
import java.util.List;
import org.springframework.stereotype.Service;

/**
 * Orquesta, no decide: cuando se puede cerrar o reabrir una quincena y quien
 * puede hacerlo lo decide PL/SQL. Tras escribir se relee la fila de la vista
 * para devolver la entidad completa.
 */
@Service
public class PeriodoService {

    private final PeriodoRepository escritura;
    private final PeriodoConsultaRepository lectura;

    public PeriodoService(PeriodoRepository escritura, PeriodoConsultaRepository lectura) {
        this.escritura = escritura;
        this.lectura = lectura;
    }

    public Page<PeriodoDto> listar(Integer anio, String estado, Integer page, Integer size, String sort) {
        return lectura.periodos(anio, estado, page, size, sort);
    }

    public PeriodoDto obtener(long id) {
        return lectura.periodo(id)
                .orElseThrow(() -> SilaException.noEncontrado("La quincena no existe."));
    }

    public PeriodoDto actual() {
        return lectura.actual()
                .orElseThrow(() -> SilaException.noEncontrado(
                        "No hay una quincena creada para la fecha de hoy. Cree los periodos del anio."));
    }

    public List<Integer> anios() {
        return lectura.anios();
    }

    public CrearPeriodosResponse crearAnio(int anio) {
        return new CrearPeriodosResponse(anio, escritura.crearAnio(anio));
    }

    public PeriodoDto cambiarEstado(long id, CambiarEstadoPeriodoRequest r) {
        obtener(id); // 404 claro si no existe, antes de llamar al procedimiento
        if ("CERRADA".equals(r.estado())) {
            escritura.cerrar(id);
        } else {
            escritura.reabrir(id, r.motivo());
        }
        return obtener(id);
    }
}
