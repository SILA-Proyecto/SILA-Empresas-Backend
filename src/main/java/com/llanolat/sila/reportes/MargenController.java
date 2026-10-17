package com.llanolat.sila.reportes;

import com.llanolat.sila.infra.Fechas;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.reportes.Margen.Fila;
import com.llanolat.sila.reportes.Margen.Reporte;
import java.time.LocalDate;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Reportes de gestion: /api/v1/reportes. SOLO ADMIN (muestran costos y ganancias). Solo lectura.
 * {@code GET /reportes/margen?agrupar=PRODUCTO|CLIENTE&desde=&hasta=&sort=}: por defecto el mes en curso.
 */
@RestController
@RequestMapping("/api/v1/reportes")
class MargenController {

    // sort -> ORDER BY fijo (nunca texto del cliente)
    private static final Map<String, String> ORDEN = Map.of(
            "margen,desc", "margen DESC NULLS LAST, id", "margen,asc", "margen ASC NULLS LAST, id",
            "ingreso,desc", "ingreso DESC, id", "ingreso,asc", "ingreso ASC, id",
            "nombre,asc", "nombre ASC, id", "nombre,desc", "nombre DESC, id");

    private final MargenRepository repo;

    MargenController(MargenRepository repo) { this.repo = repo; }

    @GetMapping("/margen")
    Reporte margen(
            @RequestParam(required = false) String agrupar,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) String sort) {
        String a = agrupar == null || agrupar.isBlank() ? "PRODUCTO" : agrupar.trim().toUpperCase(Locale.ROOT);
        if (!a.equals("PRODUCTO") && !a.equals("CLIENTE")) {
            throw SilaException.parametroInvalido("agrupar debe ser PRODUCTO o CLIENTE.", "agrupar");
        }
        LocalDate hoy = Fechas.hoy();
        LocalDate d = desde != null ? desde : hoy.withDayOfMonth(1);
        LocalDate h = hasta != null ? hasta : hoy;
        if (h.isBefore(d)) {
            throw SilaException.parametroInvalido("hasta no puede ser anterior a desde.", "hasta");
        }
        String clave = sort == null || sort.isBlank() ? "margen,desc" : sort.trim().toLowerCase(Locale.ROOT);
        if (!clave.contains(",")) clave += ",desc";
        String orden = ORDEN.get(clave);
        if (orden == null) {
            throw SilaException.parametroInvalido("sort debe ser margen, ingreso o nombre (con ,asc o ,desc).", "sort");
        }
        List<Fila> items = a.equals("PRODUCTO") ? repo.porProducto(d, h, orden) : repo.porCliente(d, h, orden);
        return new Reporte(a, d, h, repo.totales(d, h), items);
    }
}
