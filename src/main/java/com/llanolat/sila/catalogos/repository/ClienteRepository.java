package com.llanolat.sila.catalogos.repository;

import com.llanolat.sila.catalogos.dto.ActualizarClienteRequest;
import com.llanolat.sila.catalogos.dto.CrearClienteRequest;
import com.llanolat.sila.infra.SilaTemplate;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Types;
import org.springframework.stereotype.Repository;

/**
 * ESCRITURA. Nunca hay un INSERT, UPDATE ni DELETE aqui: LLANOLAT_APP no
 * tiene privilegios sobre las tablas. Todo entra por los packages, que corren
 * con AUTHID DEFINER (privilegios del dueno) y validan antes de escribir.
 */
@Repository
public class ClienteRepository {

    private final SilaTemplate sila;

    public ClienteRepository(SilaTemplate sila) { this.sila = sila; }

    public Long crear(CrearClienteRequest r, BigDecimal limiteCredito) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_catalogos.sp_crear_cliente(?,?,?,?,?,?,?,?)}")) {
                s.setString(1, r.tipoDocumento());
                s.setString(2, r.numeroDocumento());
                s.setString(3, r.nombre());
                s.setString(4, r.email());
                s.setString(5, r.telefono());
                s.setString(6, r.direccion());
                s.setBigDecimal(7, limiteCredito);
                s.registerOutParameter(8, Types.NUMERIC);
                s.execute();
                return s.getLong(8);
            }
        });
    }

    public void actualizar(long idCliente, ActualizarClienteRequest r) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_catalogos.sp_actualizar_cliente(?,?,?,?,?)}")) {
                s.setLong(1, idCliente);
                s.setString(2, r.nombre());
                s.setString(3, r.email());
                s.setString(4, r.telefono());
                s.setString(5, r.direccion());
                s.execute();
                return null;
            }
        });
    }

    /** Exige rol ADMIN en la base (ORA-20008 si no lo tiene). */
    public void cambiarLimiteCredito(long idCliente, BigDecimal nuevoLimite) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_catalogos.sp_cambiar_limite_credito(?,?)}")) {
                s.setLong(1, idCliente);
                s.setBigDecimal(2, nuevoLimite);
                s.execute();
                return null;
            }
        });
    }
}
