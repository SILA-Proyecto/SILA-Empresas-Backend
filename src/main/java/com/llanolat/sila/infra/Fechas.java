package com.llanolat.sila.infra;

import java.time.LocalDate;
import java.time.ZoneId;

/**
 * "Hoy" de SILA es el dia en Colombia. La base de datos esta en UTC: con SYSDATE, a partir de las 7 p. m.
 * hora de Colombia ya seria el dia siguiente, y una recepcion o un lote caerian en la quincena equivocada.
 */
public final class Fechas {

    public static final ZoneId COLOMBIA = ZoneId.of("America/Bogota");

    public static LocalDate hoy() {
        return LocalDate.now(COLOMBIA);
    }

    /** La fecha indicada o, si falta, hoy. Una fecha futura no es valida (se marca el campo). */
    public static LocalDate deOHoy(LocalDate indicada, String campo) {
        LocalDate hoy = hoy();
        if (indicada == null) {
            return hoy;
        }
        if (indicada.isAfter(hoy)) {
            throw SilaException.parametroInvalido("La fecha no puede ser futura.", campo);
        }
        return indicada;
    }

    private Fechas() {}
}
