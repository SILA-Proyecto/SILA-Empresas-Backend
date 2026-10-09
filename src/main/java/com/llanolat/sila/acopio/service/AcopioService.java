package com.llanolat.sila.acopio.service;

import com.llanolat.sila.acopio.dto.CuentasProveedorDto.FijarPrecioRequest;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PagoProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.PrecioProveedor;
import com.llanolat.sila.acopio.dto.CuentasProveedorDto.RegistrarPagoRequest;
import com.llanolat.sila.acopio.dto.RecepcionDto;
import com.llanolat.sila.acopio.dto.RegistrarRecepcionRequest;
import com.llanolat.sila.acopio.repository.AcopioRepository;
import com.llanolat.sila.infra.Fechas;
import com.llanolat.sila.infra.SilaException;
import java.time.LocalDate;
import org.springframework.stereotype.Service;

/** Orquesta, no decide: la calidad, el periodo abierto y el tipo de proveedor los resuelve Oracle. */
@Service
public class AcopioService {

    private final AcopioRepository repo;

    public AcopioService(AcopioRepository repo) { this.repo = repo; }

    public RecepcionDto registrar(RegistrarRecepcionRequest r) {
        // Siempre se manda la fecha explicita en hora de Colombia: la base usaria UTC y de noche seria "manana".
        LocalDate fecha = Fechas.deOHoy(r.fecha(), "fecha");
        long id = repo.registrarRecepcion(r.idProveedor(), r.litros(), r.temperatura(), r.acidez(), fecha);
        return repo.recepcion(id).orElseThrow(() -> SilaException.noEncontrado("La recepcion no existe."));
    }

    /** ADMIN. Devuelve el precio que quedo vigente (el de esa fecha). */
    public PrecioProveedor fijarPrecio(FijarPrecioRequest r) {
        LocalDate desde = Fechas.deOHoy(r.vigenteDesde(), "vigente_desde");
        repo.fijarPrecio(r.idProveedor(), r.precioLitro(), desde);
        return repo.precios(r.idProveedor(), false, 0, 100, "vigente_desde,desc").items().stream()
                   .filter(p -> p.vigenteDesde().equals(desde)).findFirst()
                   .orElseThrow(() -> SilaException.noEncontrado("El precio no existe."));
    }

    /** ADMIN. La base valida que no supere el saldo de la quincena y que la fecha caiga en una quincena abierta. */
    public PagoProveedor registrarPago(RegistrarPagoRequest r) {
        LocalDate fecha = Fechas.deOHoy(r.fechaPago(), "fecha_pago");
        long id = repo.registrarPago(r.idProveedor(), r.idPeriodoLiquidado(), r.monto(), r.metodoPago(),
                                     r.referenciaPago(), fecha);
        return repo.pago(id).orElseThrow(() -> SilaException.noEncontrado("El pago no existe."));
    }

    public PagoProveedor anularPago(long id, String motivo) {
        repo.anularPago(id, motivo);
        return repo.pago(id).orElseThrow(() -> SilaException.noEncontrado("El pago no existe."));
    }
}
