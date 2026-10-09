package com.llanolat.sila.catalogos.repository;

import com.llanolat.sila.catalogos.dto.ActualizarProveedorRequest;
import com.llanolat.sila.catalogos.dto.CrearProveedorRequest;
import com.llanolat.sila.infra.SilaTemplate;
import java.sql.CallableStatement;
import java.sql.Types;
import org.springframework.stereotype.Repository;

/** ESCRITURA de proveedores, por pkg_catalogos. Ambas operaciones: rol OPERATIVO. */
@Repository
public class ProveedorRepository {

    private final SilaTemplate sila;

    public ProveedorRepository(SilaTemplate sila) { this.sila = sila; }

    public Long crear(CrearProveedorRequest r) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_catalogos.sp_crear_proveedor(?,?,?,?,?,?)}")) {
                s.setString(1, r.tipoDocumento());
                s.setString(2, r.numeroDocumento());
                s.setString(3, r.nombre());
                s.setString(4, r.telefono());
                s.setString(5, r.tipoProveedor());
                s.registerOutParameter(6, Types.NUMERIC);
                s.execute();
                return s.getLong(6);
            }
        });
    }

    public void actualizar(long id, ActualizarProveedorRequest r) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_catalogos.sp_actualizar_proveedor(?,?,?)}")) {
                s.setLong(1, id);
                s.setString(2, r.nombre());
                s.setString(3, r.telefono());
                s.execute();
                return null;
            }
        });
    }
}
