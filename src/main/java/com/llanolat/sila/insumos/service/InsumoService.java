package com.llanolat.sila.insumos.service;

import com.llanolat.sila.infra.Fechas;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.insumos.dto.InsumosDtos.*;
import com.llanolat.sila.insumos.repository.InsumoRepository;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;

/** Orquesta, no decide: roles, stock, costo promedio y periodo abierto los resuelve Oracle. */
@Service
public class InsumoService {

    private final InsumoRepository repo;

    private final com.llanolat.sila.archivos.ComprobanteArchivos archivos;

    public InsumoService(InsumoRepository repo, com.llanolat.sila.archivos.ComprobanteArchivos archivos) {
        this.repo = repo;
        this.archivos = archivos;
    }

    // ---------- insumos ----------

    public Insumo crear(CrearInsumoRequest r) {
        return insumo(repo.crear(r));
    }

    public Insumo actualizar(long id, ActualizarInsumoRequest r) {
        repo.actualizar(id, r);
        return insumo(id);
    }

    public Insumo cambiarEstado(long id, boolean activo) {
        repo.cambiarEstado(id, activo);
        return insumo(id);
    }

    public Insumo insumo(long id) {
        return repo.insumo(id).orElseThrow(() -> SilaException.noEncontrado("El insumo " + id + " no existe."));
    }

    // ---------- compras y ajustes ----------

    public Compra comprar(CrearCompraRequest r) {
        LocalDate fecha = Fechas.deOHoy(r.fecha(), "fecha");
        long id = repo.registrarCompra(r, fecha);
        archivos.alRegistrar("COMPRA_INSUMO", id);
        return repo.compra(id).orElseThrow(() -> SilaException.noEncontrado("La compra no existe."));
    }

    public Compra anularCompra(long id, String motivo) {
        repo.compra(id).orElseThrow(() -> SilaException.noEncontrado("La compra " + id + " no existe."));
        repo.anularCompra(id, motivo.trim());
        archivos.alAnular("COMPRA_INSUMO", id);
        return repo.compra(id).orElseThrow();
    }

    public AjusteInsumo ajustar(CrearAjusteInsumoRequest r) {
        long id = repo.registrarAjuste(r);
        return repo.ajuste(id).orElseThrow(() -> SilaException.noEncontrado("El ajuste no existe."));
    }

    // ---------- recetas ----------

    public Receta receta(long idProducto) {
        String[] p = repo.productoBasico(idProducto)
                .orElseThrow(() -> SilaException.noEncontrado("El producto " + idProducto + " no existe."));
        List<LineaRecetaDto> lineas = repo.lineasReceta(idProducto);
        BigDecimal[] costo = repo.costoYCapacidad(idProducto).orElse(null);
        return new Receta(idProducto, p[0], p[1], lineas,
                costo == null ? BigDecimal.ZERO : costo[0],
                costo == null ? null : costo[1].longValue());
    }

    /** ADMIN. Reemplaza la receta completa; la base valida insumos, duplicados y cantidades. */
    public Receta definirReceta(long idProducto, List<LineaReceta> lineas) {
        repo.definirReceta(idProducto, lineasJson(lineas));
        return receta(idProducto);
    }

    /** Numeros sin notacion cientifica: son ids y cantidades ya validadas por el DTO, no texto libre. */
    static String lineasJson(List<LineaReceta> lineas) {
        return lineas.stream()
                .map(l -> "{\"id_insumo\":" + l.idInsumo() + ",\"cantidad\":" + l.cantidad().toPlainString() + "}")
                .collect(Collectors.joining(",", "[", "]"));
    }
}
