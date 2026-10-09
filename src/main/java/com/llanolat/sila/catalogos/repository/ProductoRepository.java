package com.llanolat.sila.catalogos.repository;

import com.llanolat.sila.catalogos.dto.ActualizarPrecioRequest;
import com.llanolat.sila.catalogos.dto.ActualizarProductoRequest;
import com.llanolat.sila.catalogos.dto.CrearProductoRequest;
import com.llanolat.sila.infra.SilaTemplate;
import java.sql.CallableStatement;
import java.sql.Types;
import org.springframework.stereotype.Repository;

/** ESCRITURA de productos, por pkg_catalogos. */
@Repository
public class ProductoRepository {

    private final SilaTemplate sila;

    public ProductoRepository(SilaTemplate sila) { this.sila = sila; }

    /** Rol ADMIN (crear producto fija precio y tarifa de IVA). */
    public Long crear(CrearProductoRequest r) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_catalogos.sp_crear_producto(?,?,?,?,?,?)}")) {
                s.setString(1, r.codigoSku());
                s.setString(2, r.nombre());
                s.setString(3, r.unidadMedida());
                s.setBigDecimal(4, r.precioBase());
                s.setBigDecimal(5, r.tarifaIva());
                s.registerOutParameter(6, Types.NUMERIC);
                s.execute();
                return s.getLong(6);
            }
        });
    }

    /**
     * Rol OPERATIVO. El nombre cambia siempre; la unidad solo si el producto
     * no tiene movimientos ni stock (ORA-20006 si no).
     */
    public void actualizar(long idProducto, ActualizarProductoRequest r) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_catalogos.sp_actualizar_producto(?,?,?)}")) {
                s.setLong(1, idProducto);
                s.setString(2, r.nombre());
                s.setString(3, r.unidadMedida());
                s.execute();
                return null;
            }
        });
    }

    /** Rol ADMIN. El cambio queda en auditoria_cambios. */
    public void actualizarPrecio(long idProducto, ActualizarPrecioRequest r) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_catalogos.sp_actualizar_precio(?,?,?)}")) {
                s.setLong(1, idProducto);
                s.setBigDecimal(2, r.precioBase());
                s.setBigDecimal(3, r.tarifaIva());
                s.execute();
                return null;
            }
        });
    }
}
