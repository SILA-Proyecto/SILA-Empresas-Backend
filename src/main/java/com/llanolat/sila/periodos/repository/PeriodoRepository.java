package com.llanolat.sila.periodos.repository;

import com.llanolat.sila.infra.SilaTemplate;
import java.sql.CallableStatement;
import java.sql.Types;
import org.springframework.stereotype.Repository;

/**
 * ESCRITURA de periodos: solo packages. Los tres procedimientos exigen ADMIN;
 * la base lo verifica y el backend solo anota que esperar un 403.
 */
@Repository
public class PeriodoRepository {

    private final SilaTemplate sila;

    public PeriodoRepository(SilaTemplate sila) { this.sila = sila; }

    /** Crea las 24 quincenas del anio; devuelve cuantas creo. Idempotente. */
    public int crearAnio(int anio) {
        return sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_periodos.sp_crear_periodos_anio(?,?)}")) {
                s.setInt(1, anio);
                s.registerOutParameter(2, Types.NUMERIC);
                s.execute();
                return s.getInt(2);
            }
        });
    }

    /** Una vez cerrada, la base rechaza escrituras con fecha en la quincena (20004). */
    public void cerrar(long idPeriodo) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_periodos.sp_cerrar_periodo(?)}")) {
                s.setLong(1, idPeriodo);
                s.execute();
                return null;
            }
        });
    }

    /** Exige motivo (minimo 10 caracteres); queda en auditoria_cambios. */
    public void reabrir(long idPeriodo, String motivo) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_periodos.sp_reabrir_periodo(?,?)}")) {
                s.setLong(1, idPeriodo);
                s.setString(2, motivo);
                s.execute();
                return null;
            }
        });
    }
}
