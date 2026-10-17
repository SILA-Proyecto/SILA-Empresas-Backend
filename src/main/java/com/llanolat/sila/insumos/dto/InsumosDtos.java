package com.llanolat.sila.insumos.dto;

import jakarta.validation.Valid;
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
import java.util.List;

/**
 * Cuerpos y filas de Materias primas (insumos y leche), recetas, compras y ajustes. La LECHE es la unica con
 * {@code requiere_calidad}. Las marcas {@code fecha_registro} van en UTC, sin zona.
 */
public final class InsumosDtos {

    private static final String UNIDADES = "KG|GR|LT|ML|UND|PAQ";

    // ---------- insumos ----------
    public record Insumo(
            Long idInsumo, String codigo, String nombre, String unidadMedida, BigDecimal costoPromedio,
            BigDecimal stockActual, BigDecimal stockMinimo, BigDecimal valorInventario, Boolean bajoMinimo,
            Long productosQueLoUsan, Boolean activo, LocalDateTime fechaCreacion, String usuarioCreacion,
            Boolean requiereCalidad) {}

    public record ResumenInsumos(Long totalInsumos, Long bajoMinimo, BigDecimal valorTotal) {}

    /** El stock y el costo promedio nacen en cero: se llenan con compras. */
    public record CrearInsumoRequest(
            @NotBlank @Pattern(regexp = "[A-Z0-9-]{3,20}", message = "3 a 20 caracteres: mayusculas, numeros o guion") String codigo,
            @NotBlank @Size(min = 2, max = 100) String nombre,
            @NotBlank @Pattern(regexp = UNIDADES, message = "debe ser KG, GR, LT, ML, UND o PAQ") String unidadMedida,
            @NotNull @DecimalMin("0") @DecimalMax("100000000") @Digits(integer = 9, fraction = 3) BigDecimal stockMinimo) {}

    public record ActualizarInsumoRequest(
            @NotBlank @Size(min = 2, max = 100) String nombre,
            @NotBlank @Pattern(regexp = UNIDADES, message = "debe ser KG, GR, LT, ML, UND o PAQ") String unidadMedida,
            @NotNull @DecimalMin("0") @DecimalMax("100000000") @Digits(integer = 9, fraction = 3) BigDecimal stockMinimo) {}

    // ---------- compras ----------
    public record Compra(
            Long idCompra, Long idInsumo, String codigo, String insumo, String unidadMedida, Long idProveedor,
            String proveedor, Long idPeriodo, LocalDate fecha, BigDecimal cantidad, BigDecimal valorTotal,
            BigDecimal costoUnitario, String referencia, String estado, String motivoAnulacion,
            String usuarioRegistro, LocalDateTime fechaRegistro,
            Boolean contado, String compradoEn, String estadoCalidad, BigDecimal temperatura, BigDecimal acidez,
            String motivoRechazo, Boolean requiereCalidad) {}

    /**
     * Entrada de una materia prima. {@code valorTotal} es lo que dice la factura y es OPCIONAL: si falta se usa el precio
     * pactado del proveedor (la leche, ademas, el precio por defecto). {@code idProveedor} es opcional: sin el la compra es de
     * contado y {@code compradoEn} dice donde se compro. {@code contado}: true = pagada al comprar (no suma a lo que se debe
     * al proveedor); si falta, es false con proveedor y true sin el. La LECHE exige proveedor, {@code temperatura} y
     * {@code acidez} (OPERATIVO la registra; una entrega fuera de los umbrales queda RECHAZADA, vale 0 y no entra al stock);
     * las demas materias primas no llevan esos dos campos y solo las registra el ADMIN.
     */
    public record CrearCompraRequest(
            @NotNull Long idInsumo,
            Long idProveedor,
            @NotNull @DecimalMin(value = "0.001", message = "debe ser mayor a cero") @Digits(integer = 11, fraction = 3) BigDecimal cantidad,
            @DecimalMin(value = "0.01", message = "debe ser mayor a cero") @DecimalMax("999999999999") @Digits(integer = 12, fraction = 2) BigDecimal valorTotal,
            @Size(max = 60) String referencia,
            LocalDate fecha,
            Boolean contado,
            @Size(max = 100) String compradoEn,
            @DecimalMin("-5") @DecimalMax("60") @Digits(integer = 3, fraction = 2) BigDecimal temperatura,
            @DecimalMin("0") @DecimalMax("40") @Digits(integer = 3, fraction = 2) BigDecimal acidez) {}

    public record AnularCompraRequest(@NotBlank @Size(min = 10, max = 255) String motivo) {}

    // ---------- ajustes ----------
    public record AjusteInsumo(
            Long idAjuste, Long idInsumo, String codigo, String insumo, String unidadMedida, String tipoAjuste,
            BigDecimal cantidadDelta, BigDecimal valorDelta, String observacion,
            String usuarioRegistro, LocalDateTime fechaRegistro) {}

    /** {@code cantidad} siempre positiva: el tipo decide si suma o resta. MERMA/DANO/VENCIMIENTO: OPERATIVO; correcciones: ADMIN. */
    public record CrearAjusteInsumoRequest(
            @NotNull Long idInsumo,
            @NotNull @Pattern(regexp = "MERMA|DANO|VENCIMIENTO|CORRECCION_MAS|CORRECCION_MENOS", message = "tipo de ajuste invalido") String tipoAjuste,
            @NotNull @DecimalMin(value = "0.001", message = "debe ser mayor a cero") @Digits(integer = 11, fraction = 3) BigDecimal cantidad,
            @NotBlank @Size(min = 5, max = 255) String observacion) {}

    // ---------- recetas ----------
    /** Cuanto de un insumo gasta UNA unidad del producto, en la unidad del insumo. */
    public record LineaReceta(
            @NotNull Long idInsumo,
            @NotNull @DecimalMin(value = "0.0001", message = "debe ser mayor a cero") @DecimalMax("100000") @Digits(integer = 6, fraction = 4) BigDecimal cantidad) {}

    /** Reemplaza la receta completa. Una lista vacia deja el producto sin receta. */
    public record DefinirRecetaRequest(@NotNull @Size(max = 30) @Valid List<LineaReceta> lineas) {}

    public record LineaRecetaDto(
            Long idInsumo, String codigoInsumo, String insumo, String unidadInsumo, BigDecimal cantidadPorUnidad,
            BigDecimal costoUnitarioInsumo, BigDecimal valorPorUnidad, BigDecimal stockInsumo, Boolean insumoActivo) {}

    /** {@code costoInsumosUnitario}: lo que cuestan los insumos de UNA unidad; {@code unidadesPosibles}: cuantas alcanza el stock. */
    public record Receta(
            Long idProducto, String codigoSku, String producto, List<LineaRecetaDto> lineas,
            BigDecimal costoInsumosUnitario, Long unidadesPosibles) {}

    // ---------- consumos ----------
    public record ConsumoLote(
            Long idConsumo, Long idLote, String codigoLote, Long idInsumo, String codigo, String insumo,
            String unidadMedida, BigDecimal cantidad, BigDecimal costoUnitario, BigDecimal valor) {}

    private InsumosDtos() {}
}
