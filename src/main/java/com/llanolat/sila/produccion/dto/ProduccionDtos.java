package com.llanolat.sila.produccion.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/** Cuerpos y filas de Produccion e Inventario. Las marcas {@code fecha_registro} van en UTC, sin zona. */
public final class ProduccionDtos {

    // ---------- lotes ----------
    public record Lote(
            Long idLote, String codigoLote, Long idProducto, String producto, String codigoSku, String unidadMedida,
            LocalDate fechaProduccion, BigDecimal litrosLecheUsados, BigDecimal cantidadObtenida,
            BigDecimal porcentajeRendimiento, BigDecimal costoTotal, BigDecimal costoUnitario,
            LocalDate fechaVencimiento, Integer diasRestantes, String nivelAlerta,
            String usuarioRegistro, LocalDateTime fechaRegistro) {}

    public record CrearLoteRequest(
            @NotNull Long idProducto,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 8, fraction = 2) BigDecimal litrosLecheUsados,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 10, fraction = 2) BigDecimal cantidadObtenida,
            @NotNull @DecimalMin("0") @DecimalMax("1000000") @Digits(integer = 7, fraction = 2) BigDecimal costoPorLitro,
            LocalDate fechaProduccion,
            LocalDate fechaVencimiento) {}

    // ---------- ajustes ----------
    public record Ajuste(
            Long idAjuste, Long idProducto, String producto, String codigoSku, String unidadMedida,
            String tipoAjuste, BigDecimal cantidadDelta, String observacion,
            String usuarioRegistro, LocalDateTime fechaRegistro) {}

    /** {@code cantidad} siempre positiva: el tipo decide si suma o resta. Sumar o corregir es solo ADMIN. */
    public record CrearAjusteRequest(
            @NotNull Long idProducto,
            @NotNull @Pattern(regexp = "MERMA|DANO|VENCIMIENTO|MUESTRA|INGRESO_INICIAL|CORRECCION_MAS|CORRECCION_MENOS",
                    message = "tipo de ajuste invalido") String tipoAjuste,
            @NotNull @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @Digits(integer = 10, fraction = 2) BigDecimal cantidad,
            @NotBlank @Size(min = 5, max = 255) String observacion) {}

    // ---------- inventario ----------
    public record ItemInventario(
            Long idProducto, String codigoSku, String producto, String unidadMedida,
            BigDecimal stockActual, BigDecimal precioBase, BigDecimal valorVentaInventario) {}

    public record ResumenInventario(Long totalProductos, Long productosSinStock, BigDecimal valorTotal) {}

    /** Un lote que vence pronto (o que ya vencio). El inventario es por producto, no por lote: la cantidad es la producida. */
    public record AlertaCaducidad(
            String codigoLote, String producto, BigDecimal cantidadProducida,
            LocalDate fechaVencimiento, Integer diasRestantes, String nivelAlerta) {}

    private ProduccionDtos() {}
}
