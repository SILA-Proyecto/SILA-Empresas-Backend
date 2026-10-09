package com.llanolat.sila.catalogos.repository;

import com.llanolat.sila.infra.SilaTemplate;
import java.sql.CallableStatement;
import java.sql.Types;
import org.springframework.stereotype.Repository;

/**
 * ESCRITURA de categorias de gasto, mas el cambio de estado (activar/desactivar)
 * comun a clientes, proveedores, productos y categorias.
 * Igual que ClienteRepository: ni un INSERT/UPDATE/DELETE, todo por packages.
 *
 * El rol que exige cada procedimiento esta anotado: lo verifica la base, aqui
 * solo se documenta para que el frontend sepa que esperar un 403.
 */
@Repository
public class CatalogoRepository {

    private final SilaTemplate sila;

    public CatalogoRepository(SilaTemplate sila) { this.sila = sila; }

    // ---------- activar / desactivar (el reemplazo del DELETE) ----------

    /**
     * Rol ADMIN. Entidades aceptadas por la lista cerrada del PL/SQL:
     * CLIENTE, PROVEEDOR, PRODUCTO, CATEGORIA_GASTO.
     */
    public void cambiarEstado(String entidad, long id, boolean activo) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_catalogos.sp_cambiar_estado(?,?,?)}")) {
                s.setString(1, entidad);
                s.setLong(2, id);
                s.setInt(3, activo ? 1 : 0);
                s.execute();
                return null;
            }
        });
    }

    // ---------- finanzas ----------

    /** Rol ADMIN. */
    public Long crearCategoriaGasto(String nombre) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall(
                    "{call pkg_finanzas.sp_crear_categoria_gasto(?,?)}")) {
                s.setString(1, nombre);
                s.registerOutParameter(2, Types.NUMERIC);
                s.execute();
                return s.getLong(2);
            }
        });
    }
}
