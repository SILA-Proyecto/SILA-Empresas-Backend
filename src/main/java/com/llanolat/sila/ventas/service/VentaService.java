package com.llanolat.sila.ventas.service;

import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.ventas.dto.VentasDtos.CrearVentaRequest;
import com.llanolat.sila.ventas.dto.VentasDtos.FijarPrecioRequest;
import com.llanolat.sila.ventas.dto.VentasDtos.LineaRequest;
import com.llanolat.sila.ventas.dto.VentasDtos.PagoRequest;
import com.llanolat.sila.ventas.dto.VentasDtos.PrecioCliente;
import com.llanolat.sila.ventas.dto.VentasDtos.VentaDetalle;
import com.llanolat.sila.ventas.repository.VentaRepository;
import java.util.List;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;

/**
 * Orquesta, no decide: stock, cupo de credito, precio aplicable, suma de pagos, rol y periodo abierto
 * los resuelve Oracle. Aqui solo se arma el JSON que el procedimiento espera.
 */
@Service
public class VentaService {

    private final VentaRepository repo;

    public VentaService(VentaRepository repo) { this.repo = repo; }

    public VentaDetalle registrar(CrearVentaRequest r) {
        boolean contado = "CONTADO".equals(r.tipoVenta());
        List<PagoRequest> pagos = r.pagos() == null ? List.of() : r.pagos();
        if (contado && pagos.isEmpty()) {
            throw SilaException.parametroInvalido("Una venta de contado necesita al menos un pago.", "pagos");
        }
        if (!contado && !pagos.isEmpty()) {
            throw SilaException.parametroInvalido("Una venta a credito no lleva pagos: el cobro se registra como abono en Cartera.", "pagos");
        }
        long id = repo.registrar(r.idCliente(), r.tipoVenta(), lineasJson(r.lineas()), contado ? pagosJson(pagos) : null);
        return detalle(id);
    }

    public VentaDetalle anular(long id, String motivo) {
        detalle(id);   // 404 claro si no existe
        repo.anular(id, motivo.trim());
        return detalle(id);
    }

    public VentaDetalle detalle(long id) {
        var venta = repo.venta(id).orElseThrow(() -> SilaException.noEncontrado("La venta no existe."));
        return new VentaDetalle(venta, repo.lineas(id), repo.pagos(id));
    }

    public PrecioCliente fijarPrecio(FijarPrecioRequest r) {
        long id = repo.fijarPrecio(r.idCliente(), r.idProducto(), r.precio());
        return repo.precioCliente(id).orElseThrow(() -> SilaException.noEncontrado("El precio no existe."));
    }

    public PrecioCliente quitarPrecio(long idPrecio) {
        PrecioCliente p = repo.precioCliente(idPrecio).orElseThrow(() -> SilaException.noEncontrado("El precio no existe."));
        repo.quitarPrecio(p.idCliente(), p.idProducto());
        return repo.precioCliente(idPrecio).orElseThrow();
    }

    // ---------- JSON para el procedimiento (numeros sin notacion cientifica; texto escapado) ----------

    private static String lineasJson(List<LineaRequest> lineas) {
        return lineas.stream()
                .map(l -> "{\"id_producto\":" + l.idProducto() + ",\"cantidad\":" + l.cantidad().toPlainString() + "}")
                .collect(Collectors.joining(",", "[", "]"));
    }

    private static String pagosJson(List<PagoRequest> pagos) {
        return pagos.stream()
                .map(p -> "{\"metodo_pago\":\"" + p.metodoPago() + "\",\"monto\":" + p.monto().toPlainString()
                        + ",\"referencia\":" + (p.referencia() == null || p.referencia().isBlank() ? "null" : "\"" + escapar(p.referencia().trim()) + "\"") + "}")
                .collect(Collectors.joining(",", "[", "]"));
    }

    private static String escapar(String t) {
        StringBuilder sb = new StringBuilder();
        for (char ch : t.toCharArray()) {
            if (ch == '"' || ch == '\\') sb.append('\\').append(ch);
            else if (ch < 0x20) sb.append(' ');
            else sb.append(ch);
        }
        return sb.toString();
    }
}
