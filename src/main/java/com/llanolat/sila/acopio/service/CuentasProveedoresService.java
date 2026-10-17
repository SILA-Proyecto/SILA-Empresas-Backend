package com.llanolat.sila.acopio.service;

import com.llanolat.sila.acopio.dto.CuentasProveedorDto.FijarPrecioRequest;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PagoProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PrecioProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.RegistrarPagoRequest;
import com.llanolat.sila.acopio.repository.CuentasProveedoresRepository;
import com.llanolat.sila.archivos.ComprobanteArchivos;
import com.llanolat.sila.infra.Fechas;
import com.llanolat.sila.infra.SilaException;
import java.time.LocalDate;
import org.springframework.stereotype.Service;

/** Orquesta, no decide: saldo de la quincena, periodo abierto y roles los resuelve Oracle. */
@Service
public class CuentasProveedoresService {

    private final CuentasProveedoresRepository repo;
    private final ComprobanteArchivos archivos;

    public CuentasProveedoresService(CuentasProveedoresRepository repo, ComprobanteArchivos archivos) {
        this.repo = repo;
        this.archivos = archivos;
    }

    /** ADMIN. Devuelve el precio que quedo vigente en esa fecha. */
    public PrecioProveedor fijarPrecio(FijarPrecioRequest r) {
        LocalDate desde = Fechas.deOHoy(r.vigenteDesde(), "vigente_desde");
        repo.fijarPrecio(r.idProveedor(), r.idInsumo(), r.precioUnitario(), desde);
        return repo.precios(r.idProveedor(), r.idInsumo(), false, 0, 100, "vigente_desde,desc").items().stream()
                   .filter(p -> p.vigenteDesde().equals(desde)).findFirst()
                   .orElseThrow(() -> SilaException.noEncontrado("El precio no existe."));
    }

    /** ADMIN. La base valida que no supere el saldo de la quincena y que la fecha caiga en una quincena abierta. */
    public PagoProveedor registrarPago(RegistrarPagoRequest r) {
        LocalDate fecha = Fechas.deOHoy(r.fechaPago(), "fecha_pago");
        long id = repo.registrarPago(r.idProveedor(), r.idPeriodoLiquidado(), r.monto(), r.metodoPago(),
                                     r.referenciaPago(), fecha);
        archivos.alRegistrar("PAGO_PROVEEDOR", id);
        return repo.pago(id).orElseThrow(() -> SilaException.noEncontrado("El pago no existe."));
    }

    public PagoProveedor anularPago(long id, String motivo) {
        repo.anularPago(id, motivo.trim());
        archivos.alAnular("PAGO_PROVEEDOR", id);
        return repo.pago(id).orElseThrow(() -> SilaException.noEncontrado("El pago no existe."));
    }
}
