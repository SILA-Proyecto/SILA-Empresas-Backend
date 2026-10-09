package com.llanolat.sila.parametros;

import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.infra.SilaTemplate;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.*;

/**
 * Parametros del sistema: /api/v1/parametros. Leer: cualquier persona autenticada (las pantallas los muestran).
 * Cambiar: solo ADMIN; Oracle valida el rango de cada uno y cada cambio queda en la auditoria.
 */
@RestController
@RequestMapping("/api/v1/parametros")
public class ParametrosController {

    public record Parametro(String clave, BigDecimal valor, BigDecimal minimo, BigDecimal maximo, String descripcion) {}

    public record CambiarParametroRequest(
            @NotNull @DecimalMin("-1000000") @DecimalMax("1000000") @Digits(integer = 7, fraction = 2) BigDecimal valor) {}

    private final SilaTemplate sila;
    private final JdbcClient jdbc;

    public ParametrosController(SilaTemplate sila, JdbcClient jdbc) {
        this.sila = sila;
        this.jdbc = jdbc;
    }

    /** Son pocos (una decena): lista simple, ordenada por clave. */
    @GetMapping
    public List<Parametro> listar() {
        return jdbc.sql("SELECT clave, valor, minimo, maximo, descripcion FROM vw_parametros_sistema ORDER BY clave")
                   .query(Parametro.class).list();
    }

    @PutMapping("/{clave}")
    public Parametro cambiar(@PathVariable String clave, @Valid @RequestBody CambiarParametroRequest r) {
        String k = clave.trim().toUpperCase();
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_parametros.sp_actualizar(?,?)}")) {
                s.setString(1, k);
                s.setBigDecimal(2, r.valor());
                s.execute();
                return null;
            }
        });
        return jdbc.sql("SELECT clave, valor, minimo, maximo, descripcion FROM vw_parametros_sistema WHERE clave = :k")
                   .param("k", k).query(Parametro.class).optional()
                   .orElseThrow(() -> SilaException.noEncontrado("El parametro no existe."));
    }
}
