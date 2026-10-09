package com.llanolat.sila.catalogos.repository;

import com.llanolat.sila.catalogos.dto.ClienteDto;
import com.llanolat.sila.catalogos.dto.ProductoDto;
import com.llanolat.sila.catalogos.dto.ProveedorDto;
import com.llanolat.sila.infra.ConsultaPaginada;
import com.llanolat.sila.infra.ConsultaPaginada.Filtro;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.Paginacion;
import com.llanolat.sila.infra.Texto;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * LECTURA de clientes, proveedores y productos desde sus vistas. Las vistas
 * si estan otorgadas a rol_sila_app: se consulta con SQL normal, sin sesion
 * de aplicacion (no verifican rol).
 *
 * Los filtros son los del dashboard: `texto` (nombre o documento/SKU,
 * insensible a mayusculas y tildes), `activo` (booleano) y, en proveedores,
 * `tipo_proveedor`. Los campos de orden permitidos son los nombres que el
 * dashboard conoce; cada uno se traduce a su columna.
 */
@Repository
public class CatalogoConsultaRepository {

    private static final String CLIENTES = """
            id_cliente, tipo_documento, numero_documento, nombre, email,
            telefono, direccion, limite_credito, saldo_deudor, activo""";
    private static final String PROVEEDORES = """
            id_proveedor, tipo_documento, numero_documento, nombre,
            telefono, tipo_proveedor, activo""";
    // La vista dice stock_actual; el dashboard, stock.
    private static final String PRODUCTOS = """
            id_producto, codigo_sku, nombre, unidad_medida,
            precio_base, tarifa_iva, stock_actual AS stock, activo""";

    private static final Map<String, String> ORDEN_CLIENTES = Map.of(
            "id_cliente", "id_cliente", "tipo_documento", "tipo_documento",
            "numero_documento", "numero_documento", "nombre", "nombre", "email", "email",
            "limite_credito", "limite_credito", "saldo_deudor", "saldo_deudor", "activo", "activo");
    private static final Map<String, String> ORDEN_PROVEEDORES = Map.of(
            "id_proveedor", "id_proveedor", "tipo_documento", "tipo_documento",
            "numero_documento", "numero_documento", "nombre", "nombre", "telefono", "telefono",
            "tipo_proveedor", "tipo_proveedor", "activo", "activo");
    private static final Map<String, String> ORDEN_PRODUCTOS = Map.of(
            "id_producto", "id_producto", "codigo_sku", "codigo_sku", "nombre", "nombre",
            "unidad_medida", "unidad_medida", "precio_base", "precio_base",
            "tarifa_iva", "tarifa_iva", "stock", "stock_actual", "activo", "activo");

    private final ConsultaPaginada paginada;
    private final JdbcClient jdbc;

    public CatalogoConsultaRepository(ConsultaPaginada paginada, JdbcClient jdbc) {
        this.paginada = paginada;
        this.jdbc = jdbc;
    }

    // ---------- clientes ----------

    public Page<ClienteDto> clientes(String texto, Boolean activo, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        filtrarTexto(f, texto, "numero_documento LIKE '%' || :q || '%'");
        filtrarActivo(f, activo);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_CLIENTES, "nombre,asc", "id_cliente");
        return paginada.consultar(CLIENTES, "vw_clientes", f, pag, ClienteDto.class);
    }

    public Optional<ClienteDto> cliente(long id) {
        return jdbc.sql("SELECT " + CLIENTES + " FROM vw_clientes WHERE id_cliente = :id")
                   .param("id", id).query(ClienteDto.class).optional();
    }

    // ---------- proveedores ----------

    public Page<ProveedorDto> proveedores(String texto, String tipoProveedor, Boolean activo,
                                          Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        filtrarTexto(f, texto, "numero_documento LIKE '%' || :q || '%'");
        filtrarActivo(f, activo);
        if (tipoProveedor != null && !tipoProveedor.isBlank()) {
            f.cuando("tipo_proveedor = :tipoProveedor").param("tipoProveedor", tipoProveedor.trim().toUpperCase());
        }
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_PROVEEDORES, "nombre,asc", "id_proveedor");
        return paginada.consultar(PROVEEDORES, "vw_proveedores", f, pag, ProveedorDto.class);
    }

    public Optional<ProveedorDto> proveedor(long id) {
        return jdbc.sql("SELECT " + PROVEEDORES + " FROM vw_proveedores WHERE id_proveedor = :id")
                   .param("id", id).query(ProveedorDto.class).optional();
    }

    // ---------- productos ----------

    public Page<ProductoDto> productos(String texto, Boolean activo, Integer page, Integer size, String sort) {
        Filtro f = new Filtro();
        filtrarTexto(f, texto, "UPPER(codigo_sku) LIKE UPPER('%' || :q || '%')");
        filtrarActivo(f, activo);
        Paginacion pag = Paginacion.de(page, size, sort, ORDEN_PRODUCTOS, "nombre,asc", "id_producto");
        return paginada.consultar(PRODUCTOS, "vw_productos", f, pag, ProductoDto.class);
    }

    public Optional<ProductoDto> producto(long id) {
        return jdbc.sql("SELECT " + PRODUCTOS + " FROM vw_productos WHERE id_producto = :id")
                   .param("id", id).query(ProductoDto.class).optional();
    }

    // ---------- filtros comunes ----------

    /** Nombre (sin tildes ni mayusculas) o la otra columna de identificacion de la entidad. */
    private static void filtrarTexto(Filtro f, String texto, String condicionIdentificacion) {
        if (texto == null || texto.isBlank()) return;
        f.cuando("(" + Texto.comoSinAcentos("nombre") + " OR " + condicionIdentificacion + ")")
         .param("q", texto.trim())
         .param("conAcento", Texto.ACENTOS)
         .param("sinAcento", Texto.SIN_ACENTOS);
    }

    private static void filtrarActivo(Filtro f, Boolean activo) {
        if (activo == null) return;
        f.cuando("activo = :activo").param("activo", activo ? 1 : 0);
    }
}
