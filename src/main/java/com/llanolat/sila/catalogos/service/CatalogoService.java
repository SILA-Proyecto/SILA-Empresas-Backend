package com.llanolat.sila.catalogos.service;

import com.llanolat.sila.catalogos.dto.ActualizarClienteRequest;
import com.llanolat.sila.catalogos.dto.ActualizarPrecioRequest;
import com.llanolat.sila.catalogos.dto.ActualizarProductoRequest;
import com.llanolat.sila.catalogos.dto.ActualizarProveedorRequest;
import com.llanolat.sila.catalogos.dto.ClienteDto;
import com.llanolat.sila.catalogos.dto.CrearClienteRequest;
import com.llanolat.sila.catalogos.dto.CrearProductoRequest;
import com.llanolat.sila.catalogos.dto.CrearProveedorRequest;
import com.llanolat.sila.catalogos.dto.ProductoDto;
import com.llanolat.sila.catalogos.dto.ProveedorDto;
import com.llanolat.sila.catalogos.repository.CatalogoConsultaRepository;
import com.llanolat.sila.catalogos.repository.CatalogoRepository;
import com.llanolat.sila.catalogos.repository.ClienteRepository;
import com.llanolat.sila.catalogos.repository.ProductoRepository;
import com.llanolat.sila.catalogos.repository.ProveedorRepository;
import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.SilaException;
import java.math.BigDecimal;
import org.springframework.stereotype.Service;

/**
 * Orquesta, no decide.
 *
 * Las reglas de negocio (cupo, estados, permisos por rol, cuando puede
 * cambiar la unidad de un producto) viven en PL/SQL. Este service solo elige
 * a quien llamar y, tras cada escritura, relee la fila desde la vista: el
 * dashboard espera la entidad completa en la respuesta (el procedimiento solo
 * devuelve el id).
 *
 * Sin @Transactional a proposito: cada procedimiento es su propia unidad de
 * trabajo y hace COMMIT o ROLLBACK por su cuenta.
 */
@Service
public class CatalogoService {

    private final ClienteRepository clientes;
    private final ProveedorRepository proveedores;
    private final ProductoRepository productos;
    private final CatalogoRepository catalogo;
    private final CatalogoConsultaRepository lectura;

    public CatalogoService(ClienteRepository clientes, ProveedorRepository proveedores,
                           ProductoRepository productos, CatalogoRepository catalogo,
                           CatalogoConsultaRepository lectura) {
        this.clientes = clientes;
        this.proveedores = proveedores;
        this.productos = productos;
        this.catalogo = catalogo;
        this.lectura = lectura;
    }

    // ---------- clientes ----------

    public Page<ClienteDto> listarClientes(String texto, Boolean activo, Integer page, Integer size, String sort) {
        return lectura.clientes(texto, activo, page, size, sort);
    }

    public ClienteDto crearCliente(CrearClienteRequest r) {
        BigDecimal limite = r.limiteCredito() == null ? BigDecimal.ZERO : r.limiteCredito();
        return cliente(clientes.crear(r, limite));
    }

    /**
     * Si llega un limite distinto al actual se cambia ANTES de editar los
     * datos: es lo unico que exige ADMIN, asi un OPERATIVO que lo toque
     * recibe 403 sin que se haya modificado nada.
     */
    public ClienteDto actualizarCliente(long id, ActualizarClienteRequest r) {
        if (r.limiteCredito() != null) {
            ClienteDto actual = cliente(id);
            if (actual.limiteCredito().compareTo(r.limiteCredito()) != 0) {
                clientes.cambiarLimiteCredito(id, r.limiteCredito());
            }
        }
        clientes.actualizar(id, r);
        return cliente(id);
    }

    public ClienteDto cambiarEstadoCliente(long id, boolean activo) {
        catalogo.cambiarEstado("CLIENTE", id, activo);
        return cliente(id);
    }

    private ClienteDto cliente(long id) {
        return lectura.cliente(id).orElseThrow(
                () -> SilaException.noEncontrado("El cliente " + id + " no existe."));
    }

    // ---------- proveedores ----------

    public Page<ProveedorDto> listarProveedores(String texto, String tipoProveedor, Boolean activo,
                                                Integer page, Integer size, String sort) {
        return lectura.proveedores(texto, tipoProveedor, activo, page, size, sort);
    }

    public ProveedorDto crearProveedor(CrearProveedorRequest r) {
        return proveedor(proveedores.crear(r));
    }

    public ProveedorDto actualizarProveedor(long id, ActualizarProveedorRequest r) {
        proveedores.actualizar(id, r);
        return proveedor(id);
    }

    public ProveedorDto cambiarEstadoProveedor(long id, boolean activo) {
        catalogo.cambiarEstado("PROVEEDOR", id, activo);
        return proveedor(id);
    }

    private ProveedorDto proveedor(long id) {
        return lectura.proveedor(id).orElseThrow(
                () -> SilaException.noEncontrado("El proveedor " + id + " no existe."));
    }

    // ---------- productos ----------

    public Page<ProductoDto> listarProductos(String texto, Boolean activo, Integer page, Integer size, String sort) {
        return lectura.productos(texto, activo, page, size, sort);
    }

    public ProductoDto crearProducto(CrearProductoRequest r) {
        return producto(productos.crear(r));
    }

    public ProductoDto actualizarProducto(long id, ActualizarProductoRequest r) {
        productos.actualizar(id, r);
        return producto(id);
    }

    public ProductoDto cambiarPrecioProducto(long id, ActualizarPrecioRequest r) {
        productos.actualizarPrecio(id, r);
        return producto(id);
    }

    public ProductoDto cambiarEstadoProducto(long id, boolean activo) {
        catalogo.cambiarEstado("PRODUCTO", id, activo);
        return producto(id);
    }

    private ProductoDto producto(long id) {
        return lectura.producto(id).orElseThrow(
                () -> SilaException.noEncontrado("El producto " + id + " no existe."));
    }
}
