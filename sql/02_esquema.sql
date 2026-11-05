
-- ============ Parte A - Tablas ============

-- ============ parametros_sistema ============
CREATE TABLE parametros_sistema (
    clave         VARCHAR2(50 CHAR)  NOT NULL,
    valor_numero  NUMBER,
    valor_texto   VARCHAR2(200 CHAR),
    descripcion   VARCHAR2(255 CHAR) NOT NULL,
    CONSTRAINT pk_parametros_sistema PRIMARY KEY (clave),
    CONSTRAINT ck_param_tiene_valor CHECK (valor_numero IS NOT NULL OR valor_texto IS NOT NULL)
);

-- ============ periodos_quincena ============
CREATE TABLE periodos_quincena (
    id_periodo    NUMBER GENERATED ALWAYS AS IDENTITY,
    anio          NUMBER(4)         NOT NULL,
    mes           NUMBER(2)         NOT NULL,
    quincena      NUMBER(1)         NOT NULL,
    fecha_inicio  DATE              NOT NULL,
    fecha_fin     DATE              NOT NULL,
    estado        VARCHAR2(10 CHAR) DEFAULT 'ABIERTA' NOT NULL,
    CONSTRAINT pk_periodos_quincena PRIMARY KEY (id_periodo),
    CONSTRAINT uk_periodos_anio_mes_q UNIQUE (anio, mes, quincena),
    CONSTRAINT ck_periodos_anio CHECK (anio BETWEEN 2000 AND 2100),
    CONSTRAINT ck_periodos_mes CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT ck_periodos_quincena CHECK (quincena IN (1, 2)),
    CONSTRAINT ck_periodos_fechas CHECK (fecha_fin >= fecha_inicio),
    CONSTRAINT ck_periodos_estado CHECK (estado IN ('ABIERTA', 'CERRADA'))
);

-- ============ categorias_gasto ============
CREATE TABLE categorias_gasto (
    id_categoria  NUMBER GENERATED ALWAYS AS IDENTITY,
    nombre        VARCHAR2(80 CHAR) NOT NULL,
    activo        NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_categorias_gasto PRIMARY KEY (id_categoria),
    CONSTRAINT uk_categorias_gasto_nombre UNIQUE (nombre),
    CONSTRAINT ck_categorias_gasto_activo CHECK (activo IN (0, 1))
);

-- ============ proveedores ============
CREATE TABLE proveedores (
    id_proveedor      NUMBER GENERATED ALWAYS AS IDENTITY,
    tipo_documento    VARCHAR2(12 CHAR)  NOT NULL,
    numero_documento  VARCHAR2(20 CHAR)  NOT NULL,
    nombre            VARCHAR2(120 CHAR) NOT NULL,
    telefono          VARCHAR2(20 CHAR),
    tipo_proveedor    VARCHAR2(10 CHAR)  DEFAULT 'LECHERO' NOT NULL,
    activo            NUMBER(1)          DEFAULT 1 NOT NULL,
    fecha_creacion    DATE               DEFAULT SYSDATE NOT NULL,
    usuario_creacion  VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    CONSTRAINT pk_proveedores PRIMARY KEY (id_proveedor),
    CONSTRAINT uk_proveedores_documento UNIQUE (tipo_documento, numero_documento),
    CONSTRAINT ck_proveedores_tipo_doc CHECK (tipo_documento IN ('CC', 'NIT', 'CE', 'PASAPORTE', 'TI')),
    CONSTRAINT ck_proveedores_tipo CHECK (tipo_proveedor IN ('LECHERO', 'INSUMOS')),
    CONSTRAINT ck_proveedores_activo CHECK (activo IN (0, 1))
);

-- ============ clientes ============
CREATE TABLE clientes (
    id_cliente        NUMBER GENERATED ALWAYS AS IDENTITY,
    tipo_documento    VARCHAR2(12 CHAR)  NOT NULL,
    numero_documento  VARCHAR2(20 CHAR)  NOT NULL,
    nombre            VARCHAR2(120 CHAR) NOT NULL,
    email             VARCHAR2(150 CHAR),
    telefono          VARCHAR2(20 CHAR),
    direccion         VARCHAR2(255 CHAR),
    limite_credito    NUMBER(12,2)       DEFAULT 0 NOT NULL,
    saldo_deudor      NUMBER(12,2)       DEFAULT 0 NOT NULL,
    activo            NUMBER(1)          DEFAULT 1 NOT NULL,
    fecha_creacion    DATE               DEFAULT SYSDATE NOT NULL,
    usuario_creacion  VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    CONSTRAINT pk_clientes PRIMARY KEY (id_cliente),
    CONSTRAINT uk_clientes_documento UNIQUE (tipo_documento, numero_documento),
    CONSTRAINT ck_clientes_tipo_doc CHECK (tipo_documento IN ('CC', 'NIT', 'CE', 'PASAPORTE', 'TI')),
    CONSTRAINT ck_clientes_limite CHECK (limite_credito >= 0),
    CONSTRAINT ck_clientes_saldo CHECK (saldo_deudor >= 0),
    CONSTRAINT ck_clientes_email CHECK (email IS NULL OR INSTR(email, '@') > 1),
    CONSTRAINT ck_clientes_activo CHECK (activo IN (0, 1))
);

-- ============ productos ============
CREATE TABLE productos (
    id_producto       NUMBER GENERATED ALWAYS AS IDENTITY,
    codigo_sku        VARCHAR2(20 CHAR)  NOT NULL,
    nombre            VARCHAR2(100 CHAR) NOT NULL,
    unidad_medida     VARCHAR2(10 CHAR)  NOT NULL,
    precio_base       NUMBER(12,2)       DEFAULT 0 NOT NULL,
    tarifa_iva        NUMBER(5,2)        DEFAULT 0 NOT NULL,
    stock_actual      NUMBER(12,2)       DEFAULT 0 NOT NULL,
    activo            NUMBER(1)          DEFAULT 1 NOT NULL,
    fecha_creacion    DATE               DEFAULT SYSDATE NOT NULL,
    usuario_creacion  VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    CONSTRAINT pk_productos PRIMARY KEY (id_producto),
    CONSTRAINT uk_productos_sku UNIQUE (codigo_sku),
    CONSTRAINT ck_productos_sku_mayus CHECK (codigo_sku = UPPER(codigo_sku)),
    CONSTRAINT ck_productos_unidad CHECK (unidad_medida IN ('KG', 'GR', 'LT', 'ML', 'UND', 'PAQ')),
    CONSTRAINT ck_productos_precio CHECK (precio_base >= 0),
    CONSTRAINT ck_productos_iva CHECK (tarifa_iva BETWEEN 0 AND 100),
    CONSTRAINT ck_prod_stock_no_negativo CHECK (stock_actual >= 0),
    CONSTRAINT ck_productos_activo CHECK (activo IN (0, 1))
);

-- ============ recepcion_leche ============
CREATE TABLE recepcion_leche (
    id_recepcion      NUMBER GENERATED ALWAYS AS IDENTITY,
    id_proveedor      NUMBER             NOT NULL,
    id_periodo        NUMBER             NOT NULL,
    fecha             DATE               NOT NULL,
    litros            NUMBER(10,2)       NOT NULL,
    temperatura       NUMBER(5,2)        NOT NULL,
    acidez            NUMBER(5,2)        NOT NULL,
    estado_calidad    VARCHAR2(10 CHAR)  DEFAULT 'APROBADO' NOT NULL,
    motivo_rechazo    VARCHAR2(200 CHAR),
    usuario_registro  VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    fecha_registro    TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_recepcion_leche PRIMARY KEY (id_recepcion),
    CONSTRAINT fk_recepcion_proveedor FOREIGN KEY (id_proveedor) REFERENCES proveedores (id_proveedor),
    CONSTRAINT fk_recepcion_periodo FOREIGN KEY (id_periodo) REFERENCES periodos_quincena (id_periodo),
    CONSTRAINT ck_recepcion_litros CHECK (litros > 0),
    CONSTRAINT ck_recepcion_temp CHECK (temperatura BETWEEN -5 AND 60),
    CONSTRAINT ck_recepcion_acidez CHECK (acidez BETWEEN 0 AND 40),
    CONSTRAINT ck_recepcion_estado CHECK (estado_calidad IN ('APROBADO', 'RECHAZADO')),
    CONSTRAINT ck_recepcion_motivo CHECK (estado_calidad = 'APROBADO' OR motivo_rechazo IS NOT NULL)
);

-- ============ produccion_lotes ============
CREATE TABLE produccion_lotes (
    id_lote              NUMBER GENERATED ALWAYS AS IDENTITY,
    codigo_lote          VARCHAR2(50 CHAR)  NOT NULL,
    id_producto          NUMBER             NOT NULL,
    fecha_produccion     DATE               NOT NULL,
    litros_leche_usados  NUMBER(10,2)       NOT NULL,
    cantidad_obtenida    NUMBER(12,2)       NOT NULL,
    costo_total          NUMBER(12,2)       DEFAULT 0 NOT NULL,
    fecha_vencimiento    DATE               NOT NULL,
    usuario_registro     VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    fecha_registro       TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_produccion_lotes PRIMARY KEY (id_lote),
    CONSTRAINT uk_lotes_codigo UNIQUE (codigo_lote),
    CONSTRAINT fk_lotes_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto),
    CONSTRAINT ck_lotes_litros CHECK (litros_leche_usados > 0),
    CONSTRAINT ck_lotes_cantidad CHECK (cantidad_obtenida > 0),
    CONSTRAINT ck_lotes_costo CHECK (costo_total >= 0),
    CONSTRAINT ck_lotes_vencimiento CHECK (fecha_vencimiento >= fecha_produccion)
);

-- ============ ajustes_inventario ============
CREATE TABLE ajustes_inventario (
    id_ajuste         NUMBER GENERATED ALWAYS AS IDENTITY,
    id_producto       NUMBER             NOT NULL,
    tipo_ajuste       VARCHAR2(20 CHAR)  NOT NULL,
    cantidad_delta    NUMBER(12,2)       NOT NULL,
    observacion       VARCHAR2(255 CHAR) NOT NULL,
    usuario_registro  VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    fecha_registro    TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ajustes_inventario PRIMARY KEY (id_ajuste),
    CONSTRAINT fk_ajustes_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto),
    CONSTRAINT ck_ajustes_tipo CHECK (tipo_ajuste IN ('MERMA', 'DANO', 'VENCIMIENTO', 'MUESTRA',
                                                      'INGRESO_INICIAL', 'CORRECCION_MAS', 'CORRECCION_MENOS')),
    CONSTRAINT ck_ajustes_delta CHECK (cantidad_delta <> 0)
);

-- ============ ventas ============
CREATE TABLE ventas (
    id_venta           NUMBER GENERATED ALWAYS AS IDENTITY,
    id_cliente         NUMBER             NOT NULL,
    id_periodo         NUMBER             NOT NULL,
    fecha_venta        DATE               DEFAULT SYSDATE NOT NULL,
    tipo_venta         VARCHAR2(10 CHAR)  NOT NULL,
    fecha_vencimiento  DATE,
    subtotal_venta     NUMBER(12,2)       DEFAULT 0 NOT NULL,
    total_iva          NUMBER(12,2)       DEFAULT 0 NOT NULL,
    total_venta        NUMBER(12,2)       DEFAULT 0 NOT NULL,
    saldo_pendiente    NUMBER(12,2)       DEFAULT 0 NOT NULL,
    monto_castigado    NUMBER(12,2)       DEFAULT 0 NOT NULL,
    estado_pago        VARCHAR2(10 CHAR)  DEFAULT 'PAGADA' NOT NULL,
    motivo_anulacion   VARCHAR2(255 CHAR),
    usuario_registro   VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    fecha_registro     TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ventas PRIMARY KEY (id_venta),
    CONSTRAINT fk_ventas_cliente FOREIGN KEY (id_cliente) REFERENCES clientes (id_cliente),
    CONSTRAINT fk_ventas_periodo FOREIGN KEY (id_periodo) REFERENCES periodos_quincena (id_periodo),
    CONSTRAINT ck_ventas_tipo CHECK (tipo_venta IN ('CONTADO', 'CREDITO')),
    CONSTRAINT ck_ventas_estado CHECK (estado_pago IN ('PAGADA', 'PENDIENTE', 'ANULADA', 'CASTIGADA')),
    CONSTRAINT ck_ventas_montos CHECK (subtotal_venta >= 0 AND total_iva >= 0
                                       AND total_venta = subtotal_venta + total_iva),
    CONSTRAINT ck_ventas_saldo CHECK (saldo_pendiente BETWEEN 0 AND total_venta AND monto_castigado >= 0),
    CONSTRAINT ck_ventas_contado CHECK (tipo_venta = 'CREDITO' OR (saldo_pendiente = 0 AND fecha_vencimiento IS NULL)),
    CONSTRAINT ck_ventas_credito CHECK (tipo_venta = 'CONTADO' OR fecha_vencimiento IS NOT NULL),
    CONSTRAINT ck_ventas_estado_saldo CHECK ((estado_pago = 'PENDIENTE' AND saldo_pendiente > 0)
                                          OR (estado_pago <> 'PENDIENTE' AND saldo_pendiente = 0)),
    CONSTRAINT ck_ventas_castigo CHECK (monto_castigado = 0 OR estado_pago = 'CASTIGADA')
);

-- ============ ventas_detalle ============
CREATE TABLE ventas_detalle (
    id_detalle       NUMBER GENERATED ALWAYS AS IDENTITY,
    id_venta         NUMBER       NOT NULL,
    id_producto      NUMBER       NOT NULL,
    cantidad         NUMBER(12,2) NOT NULL,
    precio_unitario  NUMBER(12,2) NOT NULL,
    tarifa_iva       NUMBER(5,2)  DEFAULT 0 NOT NULL,
    subtotal         NUMBER(12,2) NOT NULL,
    valor_iva        NUMBER(12,2) DEFAULT 0 NOT NULL,
    CONSTRAINT pk_ventas_detalle PRIMARY KEY (id_detalle),
    CONSTRAINT uk_ventas_det_venta_prod UNIQUE (id_venta, id_producto),
    CONSTRAINT fk_ventas_det_venta FOREIGN KEY (id_venta) REFERENCES ventas (id_venta),
    CONSTRAINT fk_ventas_det_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto),
    CONSTRAINT ck_ventas_det_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_ventas_det_precio CHECK (precio_unitario >= 0),
    CONSTRAINT ck_ventas_det_iva CHECK (tarifa_iva BETWEEN 0 AND 100),
    CONSTRAINT ck_ventas_det_subtotal CHECK (subtotal = ROUND(cantidad * precio_unitario, 2)),
    CONSTRAINT ck_ventas_det_valor_iva CHECK (valor_iva = ROUND(subtotal * tarifa_iva / 100, 2))
);

-- ============ gastos_operativos ============
CREATE TABLE gastos_operativos (
    id_gasto          NUMBER GENERATED ALWAYS AS IDENTITY,
    id_periodo        NUMBER             NOT NULL,
    id_categoria      NUMBER             NOT NULL,
    fecha_gasto       DATE               NOT NULL,
    concepto          VARCHAR2(255 CHAR) NOT NULL,
    monto             NUMBER(12,2)       NOT NULL,
    usuario_registro  VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    fecha_registro    TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_gastos_operativos PRIMARY KEY (id_gasto),
    CONSTRAINT fk_gastos_periodo FOREIGN KEY (id_periodo) REFERENCES periodos_quincena (id_periodo),
    CONSTRAINT fk_gastos_categoria FOREIGN KEY (id_categoria) REFERENCES categorias_gasto (id_categoria),
    CONSTRAINT ck_gastos_monto CHECK (monto > 0)
);

-- ============ resoluciones_facturacion ============
CREATE TABLE resoluciones_facturacion (
    id_resolucion       NUMBER GENERATED ALWAYS AS IDENTITY,
    tipo_documento      VARCHAR2(12 CHAR) NOT NULL,
    numero_resolucion   VARCHAR2(30 CHAR) NOT NULL,
    prefijo             VARCHAR2(10 CHAR) NOT NULL,
    rango_desde         NUMBER(12)        NOT NULL,
    rango_hasta         NUMBER(12)        NOT NULL,
    consecutivo_actual  NUMBER(12)        NOT NULL,
    vigente_desde       DATE              NOT NULL,
    vigente_hasta       DATE              NOT NULL,
    activa              NUMBER(1)         DEFAULT 1 NOT NULL,
    CONSTRAINT pk_resoluciones_fact PRIMARY KEY (id_resolucion),
    CONSTRAINT uk_resoluciones_numero UNIQUE (numero_resolucion),
    CONSTRAINT ck_resol_tipo CHECK (tipo_documento IN ('FACTURA', 'NOTA_CREDITO')),
    CONSTRAINT ck_resol_rango CHECK (rango_hasta >= rango_desde),
    CONSTRAINT ck_resol_consecutivo CHECK (consecutivo_actual BETWEEN rango_desde - 1 AND rango_hasta),
    CONSTRAINT ck_resol_vigencia CHECK (vigente_hasta >= vigente_desde),
    CONSTRAINT ck_resol_activa CHECK (activa IN (0, 1))
);

-- ============ facturas ============
CREATE TABLE facturas (
    id_factura         NUMBER GENERATED ALWAYS AS IDENTITY,
    id_venta           NUMBER             NOT NULL,
    id_resolucion      NUMBER             NOT NULL,
    numero_factura     VARCHAR2(30 CHAR)  NOT NULL,
    fecha_emision      DATE               DEFAULT SYSDATE NOT NULL,
    fecha_vencimiento  DATE,
    subtotal_base      NUMBER(12,2)       NOT NULL,
    total_iva          NUMBER(12,2)       DEFAULT 0 NOT NULL,
    total_factura      NUMBER(12,2)       NOT NULL,
    cufe               VARCHAR2(100 CHAR),
    qr_code_url        VARCHAR2(500 CHAR),
    estado_dian        VARCHAR2(12 CHAR)  DEFAULT 'NO_ENVIADA' NOT NULL,
    xml_documento      CLOB,
    usuario_emisor     VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    fecha_registro     TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_facturas PRIMARY KEY (id_factura),
    CONSTRAINT uk_facturas_venta UNIQUE (id_venta),
    CONSTRAINT uk_facturas_numero UNIQUE (numero_factura),
    CONSTRAINT uk_facturas_cufe UNIQUE (cufe),
    CONSTRAINT fk_facturas_venta FOREIGN KEY (id_venta) REFERENCES ventas (id_venta),
    CONSTRAINT fk_facturas_resolucion FOREIGN KEY (id_resolucion) REFERENCES resoluciones_facturacion (id_resolucion),
    CONSTRAINT ck_facturas_montos CHECK (subtotal_base >= 0 AND total_iva >= 0
                                         AND total_factura = subtotal_base + total_iva),
    CONSTRAINT ck_facturas_estado CHECK (estado_dian IN ('NO_ENVIADA', 'EN_PROCESO', 'ACEPTADA', 'RECHAZADA')),
    CONSTRAINT ck_facturas_cufe CHECK (estado_dian <> 'ACEPTADA' OR cufe IS NOT NULL)
);

-- ============ facturas_notas_credito ============
CREATE TABLE facturas_notas_credito (
    id_nota                 NUMBER GENERATED ALWAYS AS IDENTITY,
    id_factura              NUMBER             NOT NULL,
    id_resolucion           NUMBER             NOT NULL,
    numero_nota             VARCHAR2(30 CHAR)  NOT NULL,
    fecha_emision           DATE               DEFAULT SYSDATE NOT NULL,
    monto_devolucion        NUMBER(12,2)       NOT NULL,
    monto_aplicado_cartera  NUMBER(12,2)       DEFAULT 0 NOT NULL,
    motivo                  VARCHAR2(255 CHAR) NOT NULL,
    cude                    VARCHAR2(100 CHAR),
    estado_dian             VARCHAR2(12 CHAR)  DEFAULT 'NO_ENVIADA' NOT NULL,
    usuario_emisor          VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    fecha_registro          TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_facturas_notas_credito PRIMARY KEY (id_nota),
    CONSTRAINT uk_notas_numero UNIQUE (numero_nota),
    CONSTRAINT uk_notas_cude UNIQUE (cude),
    CONSTRAINT fk_notas_factura FOREIGN KEY (id_factura) REFERENCES facturas (id_factura),
    CONSTRAINT fk_notas_resolucion FOREIGN KEY (id_resolucion) REFERENCES resoluciones_facturacion (id_resolucion),
    CONSTRAINT ck_notas_monto CHECK (monto_devolucion > 0),
    CONSTRAINT ck_notas_aplicado CHECK (monto_aplicado_cartera BETWEEN 0 AND monto_devolucion),
    CONSTRAINT ck_notas_estado CHECK (estado_dian IN ('NO_ENVIADA', 'EN_PROCESO', 'ACEPTADA', 'RECHAZADA')),
    CONSTRAINT ck_notas_cude CHECK (estado_dian <> 'ACEPTADA' OR cude IS NOT NULL)
);

-- ============ notas_credito_detalle ============
CREATE TABLE notas_credito_detalle (
    id_detalle_nota  NUMBER GENERATED ALWAYS AS IDENTITY,
    id_nota          NUMBER       NOT NULL,
    id_producto      NUMBER       NOT NULL,
    cantidad         NUMBER(12,2) NOT NULL,
    valor_linea      NUMBER(12,2) NOT NULL,
    reingresa_stock  NUMBER(1)    DEFAULT 0 NOT NULL,
    CONSTRAINT pk_notas_credito_detalle PRIMARY KEY (id_detalle_nota),
    CONSTRAINT uk_notas_det_nota_prod UNIQUE (id_nota, id_producto),
    CONSTRAINT fk_notas_det_nota FOREIGN KEY (id_nota) REFERENCES facturas_notas_credito (id_nota),
    CONSTRAINT fk_notas_det_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto),
    CONSTRAINT ck_notas_det_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_notas_det_valor CHECK (valor_linea >= 0),
    CONSTRAINT ck_notas_det_reingresa CHECK (reingresa_stock IN (0, 1))
);

-- ============ abonos_cartera ============
CREATE TABLE abonos_cartera (
    id_abono          NUMBER GENERATED ALWAYS AS IDENTITY,
    id_recibo         NUMBER             NOT NULL,
    id_venta          NUMBER             NOT NULL,
    fecha_abono       DATE               DEFAULT SYSDATE NOT NULL,
    monto             NUMBER(12,2)       NOT NULL,
    metodo_pago       VARCHAR2(15 CHAR)  NOT NULL,
    referencia_pago   VARCHAR2(60 CHAR),
    usuario_registro  VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    fecha_registro    TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_abonos_cartera PRIMARY KEY (id_abono),
    CONSTRAINT fk_abonos_venta FOREIGN KEY (id_venta) REFERENCES ventas (id_venta),
    CONSTRAINT ck_abonos_monto CHECK (monto > 0),
    CONSTRAINT ck_abonos_metodo CHECK (metodo_pago IN ('EFECTIVO', 'TRANSFERENCIA', 'TARJETA', 'CHEQUE', 'OTRO'))
);

-- ============ documentos_repositorio ============
CREATE TABLE documentos_repositorio (
    id_documento     NUMBER GENERATED ALWAYS AS IDENTITY,
    tipo_entidad     VARCHAR2(20 CHAR)  NOT NULL,
    id_entidad       NUMBER             NOT NULL,
    nombre_archivo   VARCHAR2(255 CHAR) NOT NULL,
    mime_type        VARCHAR2(100 CHAR) DEFAULT 'application/pdf' NOT NULL,
    drive_file_id    VARCHAR2(150 CHAR),
    drive_url        VARCHAR2(500 CHAR),
    checksum_sha256  VARCHAR2(64 CHAR),
    estado_carga     VARCHAR2(10 CHAR)  DEFAULT 'PENDIENTE' NOT NULL,
    intentos         NUMBER(3)          DEFAULT 0 NOT NULL,
    ultimo_error     VARCHAR2(500 CHAR),
    usuario_carga    VARCHAR2(100 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    fecha_registro   TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    fecha_carga      TIMESTAMP,
    CONSTRAINT pk_documentos_repositorio PRIMARY KEY (id_documento),
    CONSTRAINT uk_documentos_drive UNIQUE (drive_file_id),
    CONSTRAINT ck_documentos_tipo CHECK (tipo_entidad IN ('FACTURA', 'NOTA_CREDITO', 'RECEPCION_LECHE')),
    CONSTRAINT ck_documentos_estado CHECK (estado_carga IN ('PENDIENTE', 'SUBIDO', 'ERROR')),
    CONSTRAINT ck_documentos_subido CHECK (estado_carga <> 'SUBIDO'
                                           OR (drive_file_id IS NOT NULL AND fecha_carga IS NOT NULL)),
    CONSTRAINT ck_documentos_intentos CHECK (intentos >= 0)
);

-- ============ auditoria_cambios ============
CREATE TABLE auditoria_cambios (
    id_auditoria    NUMBER GENERATED ALWAYS AS IDENTITY,
    tabla           VARCHAR2(30 CHAR)  NOT NULL,
    id_registro     VARCHAR2(60 CHAR)  NOT NULL,
    columna         VARCHAR2(40 CHAR)  NOT NULL,
    valor_anterior  VARCHAR2(400 CHAR),
    valor_nuevo     VARCHAR2(400 CHAR),
    usuario         VARCHAR2(100 CHAR) NOT NULL,
    fecha           TIMESTAMP          DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_auditoria_cambios PRIMARY KEY (id_auditoria)
);

-- ============ log_errores ============
CREATE TABLE log_errores (
    id_log        NUMBER GENERATED ALWAYS AS IDENTITY,
    fecha         TIMESTAMP           DEFAULT SYSTIMESTAMP NOT NULL,
    usuario       VARCHAR2(100 CHAR)  NOT NULL,
    unidad        VARCHAR2(120 CHAR)  NOT NULL,
    codigo_error  NUMBER              NOT NULL,
    mensaje       VARCHAR2(2000 CHAR) NOT NULL,
    traza         VARCHAR2(2000 CHAR),
    contexto      VARCHAR2(500 CHAR),
    CONSTRAINT pk_log_errores PRIMARY KEY (id_log)
);

-- ============ Parte B - Comentarios de tablas y columnas ============

-- ============ COMMENT ON TABLE y COMMENT ON COLUMN ============
COMMENT ON TABLE parametros_sistema IS 'Parametros de negocio ajustables sin recompilar codigo';
COMMENT ON COLUMN parametros_sistema.clave IS 'Identificador del parametro';
COMMENT ON COLUMN parametros_sistema.valor_numero IS 'Valor numerico del parametro';
COMMENT ON COLUMN parametros_sistema.valor_texto IS 'Valor textual del parametro';
COMMENT ON COLUMN parametros_sistema.descripcion IS 'Explicacion de para que sirve el parametro';
COMMENT ON TABLE periodos_quincena IS 'Quincenas contables; controlan la apertura y cierre de la escritura';
COMMENT ON COLUMN periodos_quincena.id_periodo IS 'Identificador de la quincena';
COMMENT ON COLUMN periodos_quincena.anio IS 'Anio calendario';
COMMENT ON COLUMN periodos_quincena.mes IS 'Mes (1-12)';
COMMENT ON COLUMN periodos_quincena.quincena IS '1 = dias 1-15, 2 = dia 16 a fin de mes';
COMMENT ON COLUMN periodos_quincena.fecha_inicio IS 'Primer dia de la quincena';
COMMENT ON COLUMN periodos_quincena.fecha_fin IS 'Ultimo dia de la quincena';
COMMENT ON COLUMN periodos_quincena.estado IS 'ABIERTA permite escritura; CERRADA la bloquea';
COMMENT ON TABLE categorias_gasto IS 'Catalogo de categorias de gasto operativo';
COMMENT ON COLUMN categorias_gasto.id_categoria IS 'Identificador de la categoria';
COMMENT ON COLUMN categorias_gasto.nombre IS 'Nombre unico de la categoria';
COMMENT ON COLUMN categorias_gasto.activo IS '1 = disponible, 0 = deshabilitada';
COMMENT ON TABLE proveedores IS 'Proveedores de leche e insumos';
COMMENT ON COLUMN proveedores.id_proveedor IS 'Identificador del proveedor';
COMMENT ON COLUMN proveedores.tipo_documento IS 'Tipo de documento de identidad';
COMMENT ON COLUMN proveedores.numero_documento IS 'Numero de documento o NIT';
COMMENT ON COLUMN proveedores.nombre IS 'Nombre o razon social';
COMMENT ON COLUMN proveedores.telefono IS 'Telefono de contacto';
COMMENT ON COLUMN proveedores.tipo_proveedor IS 'LECHERO o INSUMOS';
COMMENT ON COLUMN proveedores.activo IS '1 = activo, 0 = inactivo';
COMMENT ON COLUMN proveedores.fecha_creacion IS 'Fecha de alta';
COMMENT ON COLUMN proveedores.usuario_creacion IS 'Usuario de aplicacion que lo creo';
COMMENT ON TABLE clientes IS 'Clientes y control de credito';
COMMENT ON COLUMN clientes.id_cliente IS 'Identificador del cliente';
COMMENT ON COLUMN clientes.tipo_documento IS 'Tipo de documento de identidad';
COMMENT ON COLUMN clientes.numero_documento IS 'Numero de documento o NIT';
COMMENT ON COLUMN clientes.nombre IS 'Nombre o razon social';
COMMENT ON COLUMN clientes.email IS 'Correo para factura electronica';
COMMENT ON COLUMN clientes.telefono IS 'Telefono de contacto';
COMMENT ON COLUMN clientes.direccion IS 'Direccion de entrega o facturacion';
COMMENT ON COLUMN clientes.limite_credito IS 'Cupo maximo de credito autorizado';
COMMENT ON COLUMN clientes.saldo_deudor IS 'Deuda vigente total; debe igualar la suma de ventas PENDIENTES';
COMMENT ON COLUMN clientes.activo IS '1 = activo, 0 = inactivo';
COMMENT ON COLUMN clientes.fecha_creacion IS 'Fecha de alta';
COMMENT ON COLUMN clientes.usuario_creacion IS 'Usuario de aplicacion que lo creo';
COMMENT ON TABLE productos IS 'Catalogo de productos terminados e inventario actual';
COMMENT ON COLUMN productos.id_producto IS 'Identificador del producto';
COMMENT ON COLUMN productos.codigo_sku IS 'Codigo SKU unico en mayusculas';
COMMENT ON COLUMN productos.nombre IS 'Nombre comercial';
COMMENT ON COLUMN productos.unidad_medida IS 'Unidad de medida (KG, GR, LT, ML, UND, PAQ)';
COMMENT ON COLUMN productos.precio_base IS 'Precio de venta sin IVA';
COMMENT ON COLUMN productos.tarifa_iva IS 'Porcentaje de IVA aplicable (0-100)';
COMMENT ON COLUMN productos.stock_actual IS 'Existencias actuales; nunca negativas';
COMMENT ON COLUMN productos.activo IS '1 = vendible, 0 = inactivo';
COMMENT ON COLUMN productos.fecha_creacion IS 'Fecha de alta';
COMMENT ON COLUMN productos.usuario_creacion IS 'Usuario de aplicacion que lo creo';
COMMENT ON TABLE recepcion_leche IS 'Recepcion diaria de leche con control de calidad';
COMMENT ON COLUMN recepcion_leche.id_recepcion IS 'Identificador de la recepcion';
COMMENT ON COLUMN recepcion_leche.id_proveedor IS 'Proveedor que entrega';
COMMENT ON COLUMN recepcion_leche.id_periodo IS 'Quincena a la que pertenece la fecha';
COMMENT ON COLUMN recepcion_leche.fecha IS 'Fecha de la recepcion';
COMMENT ON COLUMN recepcion_leche.litros IS 'Litros recibidos';
COMMENT ON COLUMN recepcion_leche.temperatura IS 'Temperatura en grados C al recibir';
COMMENT ON COLUMN recepcion_leche.acidez IS 'Acidez en grados Dornic';
COMMENT ON COLUMN recepcion_leche.estado_calidad IS 'APROBADO o RECHAZADO segun umbrales del sistema';
COMMENT ON COLUMN recepcion_leche.motivo_rechazo IS 'Motivo cuando la leche es rechazada';
COMMENT ON COLUMN recepcion_leche.usuario_registro IS 'Usuario de aplicacion que registro';
COMMENT ON COLUMN recepcion_leche.fecha_registro IS 'Marca de tiempo del registro';
COMMENT ON TABLE produccion_lotes IS 'Lotes de produccion (solo insercion)';
COMMENT ON COLUMN produccion_lotes.id_lote IS 'Identificador del lote';
COMMENT ON COLUMN produccion_lotes.codigo_lote IS 'Codigo unico SKU-AAAAMMDD-NNN';
COMMENT ON COLUMN produccion_lotes.id_producto IS 'Producto fabricado';
COMMENT ON COLUMN produccion_lotes.fecha_produccion IS 'Fecha de produccion';
COMMENT ON COLUMN produccion_lotes.litros_leche_usados IS 'Litros de leche consumidos';
COMMENT ON COLUMN produccion_lotes.cantidad_obtenida IS 'Cantidad de producto obtenida';
COMMENT ON COLUMN produccion_lotes.costo_total IS 'Costo de la leche consumida (litros x costo por litro)';
COMMENT ON COLUMN produccion_lotes.fecha_vencimiento IS 'Fecha de caducidad del lote';
COMMENT ON COLUMN produccion_lotes.usuario_registro IS 'Usuario de aplicacion que registro';
COMMENT ON COLUMN produccion_lotes.fecha_registro IS 'Marca de tiempo del registro';
COMMENT ON TABLE ajustes_inventario IS 'Movimientos manuales de inventario: mermas, danos y correcciones (solo insercion)';
COMMENT ON COLUMN ajustes_inventario.id_ajuste IS 'Identificador del ajuste';
COMMENT ON COLUMN ajustes_inventario.id_producto IS 'Producto ajustado';
COMMENT ON COLUMN ajustes_inventario.tipo_ajuste IS 'Clase de ajuste';
COMMENT ON COLUMN ajustes_inventario.cantidad_delta IS 'Variacion de stock: negativa resta, positiva suma';
COMMENT ON COLUMN ajustes_inventario.observacion IS 'Motivo detallado del ajuste';
COMMENT ON COLUMN ajustes_inventario.usuario_registro IS 'Usuario de aplicacion que registro';
COMMENT ON COLUMN ajustes_inventario.fecha_registro IS 'Marca de tiempo del registro';
COMMENT ON TABLE ventas IS 'Cabecera de ventas';
COMMENT ON COLUMN ventas.id_venta IS 'Identificador de la venta';
COMMENT ON COLUMN ventas.id_cliente IS 'Cliente comprador';
COMMENT ON COLUMN ventas.id_periodo IS 'Quincena de la venta';
COMMENT ON COLUMN ventas.fecha_venta IS 'Fecha y hora de la venta';
COMMENT ON COLUMN ventas.tipo_venta IS 'CONTADO o CREDITO';
COMMENT ON COLUMN ventas.fecha_vencimiento IS 'Fecha limite de pago (solo credito)';
COMMENT ON COLUMN ventas.subtotal_venta IS 'Suma de bases sin IVA';
COMMENT ON COLUMN ventas.total_iva IS 'Suma de IVA de las lineas';
COMMENT ON COLUMN ventas.total_venta IS 'Subtotal mas IVA';
COMMENT ON COLUMN ventas.saldo_pendiente IS 'Saldo por cobrar; 0 en contado, anuladas y castigadas';
COMMENT ON COLUMN ventas.monto_castigado IS 'Monto dado de baja por cartera incobrable';
COMMENT ON COLUMN ventas.estado_pago IS 'PAGADA, PENDIENTE, ANULADA o CASTIGADA';
COMMENT ON COLUMN ventas.motivo_anulacion IS 'Motivo cuando la venta se anula';
COMMENT ON COLUMN ventas.usuario_registro IS 'Usuario de aplicacion que registro';
COMMENT ON COLUMN ventas.fecha_registro IS 'Marca de tiempo del registro';
COMMENT ON TABLE ventas_detalle IS 'Lineas de venta (solo insercion)';
COMMENT ON COLUMN ventas_detalle.id_detalle IS 'Identificador de la linea';
COMMENT ON COLUMN ventas_detalle.id_venta IS 'Venta a la que pertenece';
COMMENT ON COLUMN ventas_detalle.id_producto IS 'Producto vendido';
COMMENT ON COLUMN ventas_detalle.cantidad IS 'Cantidad vendida';
COMMENT ON COLUMN ventas_detalle.precio_unitario IS 'Precio unitario sin IVA al momento de la venta';
COMMENT ON COLUMN ventas_detalle.tarifa_iva IS 'Porcentaje de IVA aplicado';
COMMENT ON COLUMN ventas_detalle.subtotal IS 'Cantidad x precio, redondeado a 2 decimales';
COMMENT ON COLUMN ventas_detalle.valor_iva IS 'IVA de la linea';
COMMENT ON TABLE gastos_operativos IS 'Gastos operativos por quincena';
COMMENT ON COLUMN gastos_operativos.id_gasto IS 'Identificador del gasto';
COMMENT ON COLUMN gastos_operativos.id_periodo IS 'Quincena del gasto';
COMMENT ON COLUMN gastos_operativos.id_categoria IS 'Categoria del gasto';
COMMENT ON COLUMN gastos_operativos.fecha_gasto IS 'Fecha del gasto';
COMMENT ON COLUMN gastos_operativos.concepto IS 'Descripcion del gasto';
COMMENT ON COLUMN gastos_operativos.monto IS 'Valor del gasto (mayor a cero)';
COMMENT ON COLUMN gastos_operativos.usuario_registro IS 'Usuario de aplicacion que registro';
COMMENT ON COLUMN gastos_operativos.fecha_registro IS 'Marca de tiempo del registro';
COMMENT ON TABLE resoluciones_facturacion IS 'Resoluciones de numeracion autorizadas por la DIAN';
COMMENT ON COLUMN resoluciones_facturacion.id_resolucion IS 'Identificador de la resolucion';
COMMENT ON COLUMN resoluciones_facturacion.tipo_documento IS 'FACTURA o NOTA_CREDITO';
COMMENT ON COLUMN resoluciones_facturacion.numero_resolucion IS 'Numero de la resolucion DIAN';
COMMENT ON COLUMN resoluciones_facturacion.prefijo IS 'Prefijo autorizado';
COMMENT ON COLUMN resoluciones_facturacion.rango_desde IS 'Primer consecutivo autorizado';
COMMENT ON COLUMN resoluciones_facturacion.rango_hasta IS 'Ultimo consecutivo autorizado';
COMMENT ON COLUMN resoluciones_facturacion.consecutivo_actual IS 'Ultimo consecutivo usado';
COMMENT ON COLUMN resoluciones_facturacion.vigente_desde IS 'Inicio de vigencia';
COMMENT ON COLUMN resoluciones_facturacion.vigente_hasta IS 'Fin de vigencia';
COMMENT ON COLUMN resoluciones_facturacion.activa IS '1 = en uso, 0 = deshabilitada';
COMMENT ON TABLE facturas IS 'Factura legal de venta, una por venta';
COMMENT ON COLUMN facturas.id_factura IS 'Identificador de la factura';
COMMENT ON COLUMN facturas.id_venta IS 'Venta facturada';
COMMENT ON COLUMN facturas.id_resolucion IS 'Resolucion de la que salio el consecutivo';
COMMENT ON COLUMN facturas.numero_factura IS 'Numero oficial con prefijo';
COMMENT ON COLUMN facturas.fecha_emision IS 'Fecha de emision';
COMMENT ON COLUMN facturas.fecha_vencimiento IS 'Vencimiento de pago';
COMMENT ON COLUMN facturas.subtotal_base IS 'Base gravable total';
COMMENT ON COLUMN facturas.total_iva IS 'IVA total';
COMMENT ON COLUMN facturas.total_factura IS 'Base mas IVA';
COMMENT ON COLUMN facturas.cufe IS 'Codigo unico de factura electronica';
COMMENT ON COLUMN facturas.qr_code_url IS 'URL del codigo QR';
COMMENT ON COLUMN facturas.estado_dian IS 'NO_ENVIADA, EN_PROCESO, ACEPTADA o RECHAZADA';
COMMENT ON COLUMN facturas.xml_documento IS 'XML firmado; no se expone por vistas';
COMMENT ON COLUMN facturas.usuario_emisor IS 'Usuario de aplicacion que emitio';
COMMENT ON COLUMN facturas.fecha_registro IS 'Marca de tiempo del registro';
COMMENT ON TABLE facturas_notas_credito IS 'Notas credito por devoluciones de mercancia';
COMMENT ON COLUMN facturas_notas_credito.id_nota IS 'Identificador de la nota';
COMMENT ON COLUMN facturas_notas_credito.id_factura IS 'Factura afectada';
COMMENT ON COLUMN facturas_notas_credito.id_resolucion IS 'Resolucion de numeracion';
COMMENT ON COLUMN facturas_notas_credito.numero_nota IS 'Numero oficial de la nota';
COMMENT ON COLUMN facturas_notas_credito.fecha_emision IS 'Fecha de emision';
COMMENT ON COLUMN facturas_notas_credito.monto_devolucion IS 'Valor total devuelto con IVA';
COMMENT ON COLUMN facturas_notas_credito.monto_aplicado_cartera IS 'Parte aplicada a reducir la deuda; el resto es reembolso';
COMMENT ON COLUMN facturas_notas_credito.motivo IS 'Motivo de la devolucion';
COMMENT ON COLUMN facturas_notas_credito.cude IS 'Codigo unico de documento electronico';
COMMENT ON COLUMN facturas_notas_credito.estado_dian IS 'Estado ante la DIAN';
COMMENT ON COLUMN facturas_notas_credito.usuario_emisor IS 'Usuario de aplicacion que emitio';
COMMENT ON COLUMN facturas_notas_credito.fecha_registro IS 'Marca de tiempo del registro';
COMMENT ON TABLE notas_credito_detalle IS 'Productos devueltos por nota credito (solo insercion)';
COMMENT ON COLUMN notas_credito_detalle.id_detalle_nota IS 'Identificador de la linea';
COMMENT ON COLUMN notas_credito_detalle.id_nota IS 'Nota credito';
COMMENT ON COLUMN notas_credito_detalle.id_producto IS 'Producto devuelto';
COMMENT ON COLUMN notas_credito_detalle.cantidad IS 'Cantidad devuelta';
COMMENT ON COLUMN notas_credito_detalle.valor_linea IS 'Valor de la linea con IVA';
COMMENT ON COLUMN notas_credito_detalle.reingresa_stock IS '1 = vuelve al inventario, 0 = se descarta';
COMMENT ON TABLE abonos_cartera IS 'Recaudos aplicados a ventas a credito (solo insercion)';
COMMENT ON COLUMN abonos_cartera.id_abono IS 'Identificador del abono';
COMMENT ON COLUMN abonos_cartera.id_recibo IS 'Numero de recibo; agrupa el reparto de un pago';
COMMENT ON COLUMN abonos_cartera.id_venta IS 'Venta a la que se aplica';
COMMENT ON COLUMN abonos_cartera.fecha_abono IS 'Fecha del pago';
COMMENT ON COLUMN abonos_cartera.monto IS 'Valor aplicado a esta venta';
COMMENT ON COLUMN abonos_cartera.metodo_pago IS 'Medio de pago';
COMMENT ON COLUMN abonos_cartera.referencia_pago IS 'Referencia bancaria o comprobante';
COMMENT ON COLUMN abonos_cartera.usuario_registro IS 'Usuario de aplicacion que registro';
COMMENT ON COLUMN abonos_cartera.fecha_registro IS 'Marca de tiempo del registro';
COMMENT ON TABLE documentos_repositorio IS 'Cola y registro de documentos subidos a Google Drive';
COMMENT ON COLUMN documentos_repositorio.id_documento IS 'Identificador del documento';
COMMENT ON COLUMN documentos_repositorio.tipo_entidad IS 'Tipo de entidad de origen';
COMMENT ON COLUMN documentos_repositorio.id_entidad IS 'Identificador de la entidad de origen';
COMMENT ON COLUMN documentos_repositorio.nombre_archivo IS 'Nombre del archivo';
COMMENT ON COLUMN documentos_repositorio.mime_type IS 'Tipo MIME';
COMMENT ON COLUMN documentos_repositorio.drive_file_id IS 'Id devuelto por Drive; nulo mientras esta PENDIENTE';
COMMENT ON COLUMN documentos_repositorio.drive_url IS 'Enlace de visualizacion en Drive';
COMMENT ON COLUMN documentos_repositorio.checksum_sha256 IS 'Huella SHA-256 del archivo subido';
COMMENT ON COLUMN documentos_repositorio.estado_carga IS 'PENDIENTE, SUBIDO o ERROR';
COMMENT ON COLUMN documentos_repositorio.intentos IS 'Numero de intentos de carga';
COMMENT ON COLUMN documentos_repositorio.ultimo_error IS 'Ultimo mensaje de error de carga';
COMMENT ON COLUMN documentos_repositorio.usuario_carga IS 'Usuario de aplicacion';
COMMENT ON COLUMN documentos_repositorio.fecha_registro IS 'Cuando se encolo';
COMMENT ON COLUMN documentos_repositorio.fecha_carga IS 'Cuando se subio con exito';
COMMENT ON TABLE auditoria_cambios IS 'Bitacora de cambios sensibles (solo insercion)';
COMMENT ON COLUMN auditoria_cambios.id_auditoria IS 'Identificador del evento';
COMMENT ON COLUMN auditoria_cambios.tabla IS 'Tabla afectada';
COMMENT ON COLUMN auditoria_cambios.id_registro IS 'Clave del registro afectado';
COMMENT ON COLUMN auditoria_cambios.columna IS 'Columna modificada';
COMMENT ON COLUMN auditoria_cambios.valor_anterior IS 'Valor previo';
COMMENT ON COLUMN auditoria_cambios.valor_nuevo IS 'Valor nuevo';
COMMENT ON COLUMN auditoria_cambios.usuario IS 'Usuario de aplicacion que hizo el cambio';
COMMENT ON COLUMN auditoria_cambios.fecha IS 'Marca de tiempo del cambio';
COMMENT ON TABLE log_errores IS 'Registro tecnico de errores internos';
COMMENT ON COLUMN log_errores.id_log IS 'Numero de referencia de soporte';
COMMENT ON COLUMN log_errores.fecha IS 'Momento del error';
COMMENT ON COLUMN log_errores.usuario IS 'Usuario de aplicacion';
COMMENT ON COLUMN log_errores.unidad IS 'Package y procedimiento donde ocurrio';
COMMENT ON COLUMN log_errores.codigo_error IS 'Codigo SQLCODE';
COMMENT ON COLUMN log_errores.mensaje IS 'Mensaje del motor';
COMMENT ON COLUMN log_errores.traza IS 'Traza de la pila de llamadas';
COMMENT ON COLUMN log_errores.contexto IS 'Parametros relevantes de la llamada';

-- ============ Parte C - Secuencia, índices y datos iniciales ============

-- ============ Secuencia de recibos de caja ============
CREATE SEQUENCE seq_recibo_caja START WITH 1 INCREMENT BY 1 NOCYCLE CACHE 20;

-- ============ Índices sobre claves foráneas y filtros frecuentes ============
CREATE INDEX ix_periodos_fechas        ON periodos_quincena (fecha_inicio, fecha_fin);
CREATE INDEX ix_recepcion_periodo      ON recepcion_leche (id_periodo, id_proveedor, estado_calidad);
CREATE INDEX ix_recepcion_proveedor    ON recepcion_leche (id_proveedor, fecha);
CREATE INDEX ix_lotes_producto_fecha   ON produccion_lotes (id_producto, fecha_produccion);
CREATE INDEX ix_lotes_vencimiento      ON produccion_lotes (fecha_vencimiento);
CREATE INDEX ix_ajustes_producto       ON ajustes_inventario (id_producto, fecha_registro);
CREATE INDEX ix_ventas_cliente_estado  ON ventas (id_cliente, estado_pago, fecha_venta, id_venta);
CREATE INDEX ix_ventas_periodo         ON ventas (id_periodo, estado_pago);
CREATE INDEX ix_ventas_det_producto    ON ventas_detalle (id_producto);
CREATE INDEX ix_gastos_periodo         ON gastos_operativos (id_periodo, id_categoria);
CREATE INDEX ix_gastos_categoria       ON gastos_operativos (id_categoria);
CREATE INDEX ix_facturas_resolucion    ON facturas (id_resolucion);
CREATE INDEX ix_facturas_estado        ON facturas (estado_dian, fecha_emision);
CREATE INDEX ix_notas_factura          ON facturas_notas_credito (id_factura);
CREATE INDEX ix_notas_resolucion       ON facturas_notas_credito (id_resolucion);
CREATE INDEX ix_notas_det_producto     ON notas_credito_detalle (id_producto);
CREATE INDEX ix_abonos_venta           ON abonos_cartera (id_venta);
CREATE INDEX ix_abonos_recibo          ON abonos_cartera (id_recibo);
CREATE INDEX ix_documentos_entidad     ON documentos_repositorio (tipo_entidad, id_entidad);
CREATE INDEX ix_documentos_estado      ON documentos_repositorio (estado_carga, fecha_registro);
CREATE INDEX ix_auditoria_registro     ON auditoria_cambios (tabla, id_registro, fecha);
CREATE INDEX ix_log_errores_fecha      ON log_errores (fecha);

-- ============ Datos iniciales ============
INSERT INTO parametros_sistema (clave, valor_numero, descripcion) VALUES ('TEMP_MAX_LECHE_C', 10, 'Temperatura maxima en grados C aceptada al recibir leche');
INSERT INTO parametros_sistema (clave, valor_numero, descripcion) VALUES ('ACIDEZ_MAX_DORNIC', 18, 'Acidez maxima en grados Dornic aceptada al recibir leche');
INSERT INTO parametros_sistema (clave, valor_numero, descripcion) VALUES ('DIAS_VIDA_UTIL_DEFAULT', 21, 'Dias de vida util por defecto de un lote nuevo');
INSERT INTO parametros_sistema (clave, valor_numero, descripcion) VALUES ('PLAZO_CREDITO_DIAS', 30, 'Dias de plazo para pagar una venta a credito');
INSERT INTO parametros_sistema (clave, valor_numero, descripcion) VALUES ('MAX_LINEAS_DOCUMENTO', 200, 'Maximo de lineas por venta o nota credito');

INSERT INTO categorias_gasto (nombre) VALUES ('COMBUSTIBLE');
INSERT INTO categorias_gasto (nombre) VALUES ('INSUMOS');
INSERT INTO categorias_gasto (nombre) VALUES ('NOMINA');
INSERT INTO categorias_gasto (nombre) VALUES ('SERVICIOS PUBLICOS');
INSERT INTO categorias_gasto (nombre) VALUES ('MANTENIMIENTO');
INSERT INTO categorias_gasto (nombre) VALUES ('TRANSPORTE');
INSERT INTO categorias_gasto (nombre) VALUES ('OTROS');

COMMIT;

-- ============ Parte D - Infraestructura: log, errores, seguridad, parámetros y auditoría ============

-- ============ pkg_log ============
CREATE OR REPLACE PACKAGE pkg_log AUTHID DEFINER AS
    PROCEDURE sp_error(
        p_unidad   IN  VARCHAR2,
        p_codigo   IN  NUMBER,
        p_mensaje  IN  VARCHAR2,
        p_traza    IN  VARCHAR2,
        p_contexto IN  VARCHAR2,
        p_id_log   OUT NUMBER
    );
END pkg_log;
/
CREATE OR REPLACE PACKAGE BODY pkg_log AS

    PROCEDURE sp_error(
        p_unidad   IN  VARCHAR2,
        p_codigo   IN  NUMBER,
        p_mensaje  IN  VARCHAR2,
        p_traza    IN  VARCHAR2,
        p_contexto IN  VARCHAR2,
        p_id_log   OUT NUMBER
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO log_errores (usuario, unidad, codigo_error, mensaje, traza, contexto)
        VALUES (NVL(SYS_CONTEXT('__CTX__', 'USUARIO'), SYS_CONTEXT('USERENV', 'SESSION_USER')),
                SUBSTR(p_unidad, 1, 120),
                p_codigo,
                SUBSTR(NVL(p_mensaje, 'sin mensaje'), 1, 2000),
                SUBSTR(p_traza, 1, 2000),
                SUBSTR(p_contexto, 1, 500))
        RETURNING id_log INTO p_id_log;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_id_log := NULL;
    END sp_error;

END pkg_log;
/

-- ============ pkg_errores ============
CREATE OR REPLACE PACKAGE pkg_errores AUTHID DEFINER AS
    c_parametro_invalido     CONSTANT PLS_INTEGER := -20001;
    c_stock_insuficiente     CONSTANT PLS_INTEGER := -20002;
    c_limite_credito         CONSTANT PLS_INTEGER := -20003;
    c_periodo_cerrado        CONSTANT PLS_INTEGER := -20004;
    c_abono_invalido         CONSTANT PLS_INTEGER := -20005;
    c_operacion_no_permitida CONSTANT PLS_INTEGER := -20006;
    c_entidad_no_existe      CONSTANT PLS_INTEGER := -20007;
    c_permiso_denegado       CONSTANT PLS_INTEGER := -20008;
    c_periodo_no_encontrado  CONSTANT PLS_INTEGER := -20009;
    c_estado_invalido        CONSTANT PLS_INTEGER := -20010;
    c_registro_inmutable     CONSTANT PLS_INTEGER := -20011;
    c_facturacion            CONSTANT PLS_INTEGER := -20012;
    c_error_interno          CONSTANT PLS_INTEGER := -20999;

    -- Uso: EXCEPTION WHEN OTHERS THEN pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_x', 'contexto');
    PROCEDURE sp_propagar(p_unidad IN VARCHAR2, p_contexto IN VARCHAR2 DEFAULT NULL);
END pkg_errores;
/
CREATE OR REPLACE PACKAGE BODY pkg_errores AS

    PROCEDURE sp_propagar(p_unidad IN VARCHAR2, p_contexto IN VARCHAR2 DEFAULT NULL) IS
        v_codigo     PLS_INTEGER    := SQLCODE;
        v_mensaje    VARCHAR2(2000) := SUBSTR(SQLERRM, 1, 2000);
        v_traza      VARCHAR2(2000) := SUBSTR(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 1, 2000);
        v_id_log     NUMBER;
        v_codigo_app PLS_INTEGER;
        v_amigable   VARCHAR2(300);
    BEGIN
        ROLLBACK;

        -- Error de negocio controlado (RAISE_APPLICATION_ERROR): se reenvia limpio.
        IF v_codigo BETWEEN -20999 AND -20000 THEN
            RAISE_APPLICATION_ERROR(v_codigo, REGEXP_REPLACE(v_mensaje, '^ORA-[0-9]{5}: ', ''));
        END IF;

        pkg_log.sp_error(p_unidad, v_codigo, v_mensaje, v_traza, p_contexto, v_id_log);

        CASE v_codigo
            WHEN -1 THEN
                v_codigo_app := c_operacion_no_permitida;
                v_amigable   := 'Ya existe un registro con los mismos datos unicos.';
            WHEN -2290 THEN
                v_codigo_app := c_parametro_invalido;
                v_amigable   := 'Uno de los valores enviados incumple una regla de validacion.';
            WHEN -2291 THEN
                v_codigo_app := c_entidad_no_existe;
                v_amigable   := 'Se hace referencia a un registro que no existe.';
            WHEN -2292 THEN
                v_codigo_app := c_operacion_no_permitida;
                v_amigable   := 'El registro tiene informacion asociada y no puede eliminarse.';
            WHEN -54 THEN
                v_codigo_app := c_operacion_no_permitida;
                v_amigable   := 'El registro esta siendo usado por otro proceso. Intente de nuevo.';
            WHEN -30006 THEN
                v_codigo_app := c_operacion_no_permitida;
                v_amigable   := 'El registro esta bloqueado por otro proceso. Intente de nuevo.';
            WHEN -60 THEN
                v_codigo_app := c_operacion_no_permitida;
                v_amigable   := 'Conflicto de concurrencia. Intente de nuevo.';
            ELSE
                v_codigo_app := c_error_interno;
                v_amigable   := 'Error interno del sistema.';
        END CASE;

        RAISE_APPLICATION_ERROR(v_codigo_app,
            v_amigable || ' (ref. soporte: ' || NVL(TO_CHAR(v_id_log), 'n/d') || ')');
    END sp_propagar;

END pkg_errores;
/

-- ============ pkg_seguridad ============
CREATE OR REPLACE PACKAGE pkg_seguridad AUTHID DEFINER AS
    c_rol_admin     CONSTANT VARCHAR2(10) := 'ADMIN';
    c_rol_operativo CONSTANT VARCHAR2(10) := 'OPERATIVO';

    PROCEDURE sp_iniciar_sesion(p_usuario IN VARCHAR2, p_rol IN VARCHAR2);
    PROCEDURE sp_cerrar_sesion;
    FUNCTION  fn_usuario_actual RETURN VARCHAR2;
    FUNCTION  fn_rol_actual RETURN VARCHAR2;
    -- Exige que la sesion tenga al menos el rol indicado (ADMIN incluye OPERATIVO).
    PROCEDURE sp_exigir_rol(p_rol_minimo IN VARCHAR2);
END pkg_seguridad;
/
CREATE OR REPLACE PACKAGE BODY pkg_seguridad AS

    PROCEDURE sp_iniciar_sesion(p_usuario IN VARCHAR2, p_rol IN VARCHAR2) IS
    BEGIN
        IF p_usuario IS NULL OR NOT REGEXP_LIKE(p_usuario, '^[A-Za-z0-9_.@-]{3,100}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Identificador de usuario invalido.');
        END IF;
        IF p_rol IS NULL OR p_rol NOT IN (c_rol_admin, c_rol_operativo) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Rol de aplicacion invalido.');
        END IF;
        DBMS_SESSION.SET_CONTEXT('__CTX__', 'USUARIO', p_usuario);
        DBMS_SESSION.SET_CONTEXT('__CTX__', 'ROL', p_rol);
        DBMS_SESSION.SET_IDENTIFIER(p_usuario);
    END sp_iniciar_sesion;

    PROCEDURE sp_cerrar_sesion IS
    BEGIN
        DBMS_SESSION.CLEAR_CONTEXT('__CTX__');
        DBMS_SESSION.CLEAR_IDENTIFIER;
    END sp_cerrar_sesion;

    FUNCTION fn_usuario_actual RETURN VARCHAR2 IS
    BEGIN
        RETURN SYS_CONTEXT('__CTX__', 'USUARIO');
    END fn_usuario_actual;

    FUNCTION fn_rol_actual RETURN VARCHAR2 IS
    BEGIN
        RETURN SYS_CONTEXT('__CTX__', 'ROL');
    END fn_rol_actual;

    PROCEDURE sp_exigir_rol(p_rol_minimo IN VARCHAR2) IS
        v_rol    VARCHAR2(20) := SYS_CONTEXT('__CTX__', 'ROL');
        v_id_log NUMBER;
    BEGIN
        IF v_rol IS NULL THEN
            pkg_log.sp_error('PKG_SEGURIDAD.sp_exigir_rol', pkg_errores.c_permiso_denegado,
                             'Intento sin sesion de aplicacion', NULL, 'exigido=' || p_rol_minimo, v_id_log);
            RAISE_APPLICATION_ERROR(pkg_errores.c_permiso_denegado, 'No hay una sesion de aplicacion iniciada.');
        END IF;
        IF p_rol_minimo = c_rol_admin AND v_rol <> c_rol_admin THEN
            pkg_log.sp_error('PKG_SEGURIDAD.sp_exigir_rol', pkg_errores.c_permiso_denegado,
                             'Rol insuficiente', NULL, 'rol=' || v_rol || ';exigido=' || p_rol_minimo, v_id_log);
            RAISE_APPLICATION_ERROR(pkg_errores.c_permiso_denegado, 'Operacion reservada al rol ADMIN.');
        END IF;
    END sp_exigir_rol;

END pkg_seguridad;
/

-- ============ pkg_parametros ============
CREATE OR REPLACE PACKAGE pkg_parametros AUTHID DEFINER AS
    FUNCTION fn_numero(p_clave IN VARCHAR2) RETURN NUMBER RESULT_CACHE;
END pkg_parametros;
/
CREATE OR REPLACE PACKAGE BODY pkg_parametros AS

    FUNCTION fn_numero(p_clave IN VARCHAR2) RETURN NUMBER RESULT_CACHE IS
        v_valor NUMBER;
    BEGIN
        SELECT valor_numero INTO v_valor
          FROM parametros_sistema
         WHERE clave = p_clave;
        RETURN v_valor;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                                    'Parametro de sistema no configurado: ' || p_clave);
    END fn_numero;

END pkg_parametros;
/

-- ============ pkg_auditoria ============
CREATE OR REPLACE PACKAGE pkg_auditoria AUTHID DEFINER AS
    PROCEDURE sp_registrar(
        p_tabla       IN VARCHAR2,
        p_id_registro IN VARCHAR2,
        p_columna     IN VARCHAR2,
        p_anterior    IN VARCHAR2,
        p_nuevo       IN VARCHAR2
    );
END pkg_auditoria;
/
CREATE OR REPLACE PACKAGE BODY pkg_auditoria AS

    PROCEDURE sp_registrar(
        p_tabla       IN VARCHAR2,
        p_id_registro IN VARCHAR2,
        p_columna     IN VARCHAR2,
        p_anterior    IN VARCHAR2,
        p_nuevo       IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO auditoria_cambios (tabla, id_registro, columna, valor_anterior, valor_nuevo, usuario)
        VALUES (SUBSTR(p_tabla, 1, 30), SUBSTR(p_id_registro, 1, 60), SUBSTR(p_columna, 1, 40),
                SUBSTR(p_anterior, 1, 400), SUBSTR(p_nuevo, 1, 400),
                NVL(SYS_CONTEXT('__CTX__', 'USUARIO'), SYS_CONTEXT('USERENV', 'SESSION_USER')));
    END sp_registrar;

END pkg_auditoria;
/

-- ============ Parte E - Períodos contables ============

-- ============ pkg_periodos ============
CREATE OR REPLACE PACKAGE pkg_periodos AUTHID DEFINER AS
    FUNCTION fn_id_periodo(p_fecha IN DATE) RETURN NUMBER;

    PROCEDURE sp_validar_abierto(p_id_periodo IN NUMBER, p_fecha IN DATE DEFAULT NULL);

    PROCEDURE sp_crear_periodos_anio(p_anio IN NUMBER, p_creados OUT NUMBER);
    PROCEDURE sp_cerrar_periodo(p_id_periodo IN NUMBER);
    PROCEDURE sp_reabrir_periodo(p_id_periodo IN NUMBER, p_motivo IN VARCHAR2);
END pkg_periodos;
/
CREATE OR REPLACE PACKAGE BODY pkg_periodos AS

    FUNCTION fn_id_periodo(p_fecha IN DATE) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        IF p_fecha IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La fecha es obligatoria.');
        END IF;
        SELECT id_periodo INTO v_id
          FROM periodos_quincena
         WHERE TRUNC(p_fecha) BETWEEN fecha_inicio AND fecha_fin;
        RETURN v_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_periodo_no_encontrado,
                'No existe una quincena para la fecha ' || TO_CHAR(p_fecha, 'YYYY-MM-DD') ||
                '. Cree los periodos del anio.');
        WHEN TOO_MANY_ROWS THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'Hay quincenas solapadas para la fecha ' || TO_CHAR(p_fecha, 'YYYY-MM-DD') || '.');
    END fn_id_periodo;

    PROCEDURE sp_validar_abierto(p_id_periodo IN NUMBER, p_fecha IN DATE DEFAULT NULL) IS
        v_estado VARCHAR2(10);
        v_inicio DATE;
        v_fin    DATE;
    BEGIN
        SELECT estado, fecha_inicio, fecha_fin
          INTO v_estado, v_inicio, v_fin
          FROM periodos_quincena
         WHERE id_periodo = p_id_periodo;

        IF v_estado = 'CERRADA' THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_periodo_cerrado,
                'La quincena ' || TO_CHAR(v_inicio, 'YYYY-MM-DD') || ' a ' ||
                TO_CHAR(v_fin, 'YYYY-MM-DD') || ' esta CERRADA.');
        END IF;
        IF p_fecha IS NOT NULL AND TRUNC(p_fecha) NOT BETWEEN v_inicio AND v_fin THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'La fecha ' || TO_CHAR(p_fecha, 'YYYY-MM-DD') || ' no pertenece a la quincena indicada.');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_periodo_no_encontrado, 'La quincena indicada no existe.');
    END sp_validar_abierto;

    PROCEDURE sp_crear_periodos_anio(p_anio IN NUMBER, p_creados OUT NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_anio IS NULL OR p_anio <> TRUNC(p_anio) OR p_anio NOT BETWEEN 2000 AND 2100 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Anio invalido.');
        END IF;

        INSERT INTO periodos_quincena (anio, mes, quincena, fecha_inicio, fecha_fin, estado)
        SELECT p_anio, m.mes, q.quincena,
               CASE q.quincena
                   WHEN 1 THEN TO_DATE(p_anio || '-' || LPAD(m.mes, 2, '0') || '-01', 'YYYY-MM-DD')
                   ELSE        TO_DATE(p_anio || '-' || LPAD(m.mes, 2, '0') || '-16', 'YYYY-MM-DD')
               END,
               CASE q.quincena
                   WHEN 1 THEN TO_DATE(p_anio || '-' || LPAD(m.mes, 2, '0') || '-15', 'YYYY-MM-DD')
                   ELSE LAST_DAY(TO_DATE(p_anio || '-' || LPAD(m.mes, 2, '0') || '-01', 'YYYY-MM-DD'))
               END,
               'ABIERTA'
          FROM (SELECT LEVEL AS mes FROM dual CONNECT BY LEVEL <= 12) m
         CROSS JOIN (SELECT LEVEL AS quincena FROM dual CONNECT BY LEVEL <= 2) q
         WHERE NOT EXISTS (SELECT 1
                             FROM periodos_quincena x
                            WHERE x.anio = p_anio AND x.mes = m.mes AND x.quincena = q.quincena);

        p_creados := SQL%ROWCOUNT;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_creados := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_periodos_anio', 'anio=' || p_anio);
    END sp_crear_periodos_anio;

    PROCEDURE sp_cerrar_periodo(p_id_periodo IN NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        UPDATE periodos_quincena
           SET estado = 'CERRADA'
         WHERE id_periodo = p_id_periodo AND estado = 'ABIERTA';
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La quincena no existe o ya esta cerrada.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_cerrar_periodo', 'id_periodo=' || p_id_periodo);
    END sp_cerrar_periodo;

    PROCEDURE sp_reabrir_periodo(p_id_periodo IN NUMBER, p_motivo IN VARCHAR2) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 10 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Reabrir una quincena exige un motivo de al menos 10 caracteres.');
        END IF;
        UPDATE periodos_quincena
           SET estado = 'ABIERTA'
         WHERE id_periodo = p_id_periodo AND estado = 'CERRADA';
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La quincena no existe o ya esta abierta.');
        END IF;
        pkg_auditoria.sp_registrar('PERIODOS_QUINCENA', TO_CHAR(p_id_periodo), 'MOTIVO_REAPERTURA',
                                   NULL, SUBSTR(TRIM(p_motivo), 1, 400));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_reabrir_periodo', 'id_periodo=' || p_id_periodo);
    END sp_reabrir_periodo;

END pkg_periodos;
/

-- ============ Parte F - Funciones SQL-callable (PRAGMA UDF) ============

-- ============ fn_rendimiento_pct ============
CREATE OR REPLACE FUNCTION fn_rendimiento_pct(
    p_cantidad_obtenida IN NUMBER,
    p_litros_usados     IN NUMBER
) RETURN NUMBER
    AUTHID DEFINER
    DETERMINISTIC
IS
    PRAGMA UDF;
BEGIN
    IF p_litros_usados IS NULL OR p_litros_usados <= 0 THEN
        RETURN NULL;
    END IF;
    RETURN ROUND(p_cantidad_obtenida / p_litros_usados * 100, 2);
END fn_rendimiento_pct;
/

-- ============ fn_estado_credito ============
CREATE OR REPLACE FUNCTION fn_estado_credito(
    p_limite    IN NUMBER,
    p_saldo     IN NUMBER,
    p_dias_mora IN NUMBER
) RETURN VARCHAR2
    AUTHID DEFINER
    DETERMINISTIC
IS
    PRAGMA UDF;
BEGIN
    IF NVL(p_saldo, 0) = 0 THEN
        RETURN 'AL_DIA';
    ELSIF NVL(p_dias_mora, 0) > 0 THEN
        RETURN 'EN_MORA';
    ELSIF p_saldo > NVL(p_limite, 0) THEN
        RETURN 'EXCEDIDO';
    END IF;
    RETURN 'VIGENTE';
END fn_estado_credito;
/

-- ============ fn_semaforo_caducidad ============
CREATE OR REPLACE FUNCTION fn_semaforo_caducidad(p_dias_restantes IN NUMBER)
RETURN VARCHAR2
    AUTHID DEFINER
    DETERMINISTIC
IS
    PRAGMA UDF;
BEGIN
    IF p_dias_restantes IS NULL THEN
        RETURN NULL;
    ELSIF p_dias_restantes < 0 THEN
        RETURN 'VENCIDO';
    ELSIF p_dias_restantes <= 2 THEN
        RETURN 'CRITICO';
    END IF;
    RETURN 'PROXIMO';
END fn_semaforo_caducidad;
/

-- ============ Parte G - Triggers ============

-- ============ Guardas de período y protección contra borrado ============
CREATE OR REPLACE TRIGGER trg_recepcion_guard
BEFORE INSERT OR UPDATE OR DELETE ON recepcion_leche
FOR EACH ROW
BEGIN
    IF DELETING THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Las recepciones de leche no pueden eliminarse.');
    END IF;
    pkg_periodos.sp_validar_abierto(:NEW.id_periodo, :NEW.fecha);
    IF UPDATING AND :OLD.id_periodo <> :NEW.id_periodo THEN
        pkg_periodos.sp_validar_abierto(:OLD.id_periodo);
    END IF;
END trg_recepcion_guard;
/
CREATE OR REPLACE TRIGGER trg_gastos_guard
BEFORE INSERT OR UPDATE OR DELETE ON gastos_operativos
FOR EACH ROW
BEGIN
    IF DELETING THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los gastos no pueden eliminarse.');
    END IF;
    pkg_periodos.sp_validar_abierto(:NEW.id_periodo, :NEW.fecha_gasto);
    IF UPDATING AND :OLD.id_periodo <> :NEW.id_periodo THEN
        pkg_periodos.sp_validar_abierto(:OLD.id_periodo);
    END IF;
END trg_gastos_guard;
/
CREATE OR REPLACE TRIGGER trg_ventas_guard
BEFORE INSERT OR DELETE
    OR UPDATE OF id_cliente, id_periodo, fecha_venta, tipo_venta, subtotal_venta, total_iva, total_venta
ON ventas
FOR EACH ROW
BEGIN
    IF DELETING THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable,
            'Las ventas no pueden eliminarse; use la anulacion.');
    ELSIF UPDATING THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable,
            'Los datos comerciales de una venta no pueden modificarse; anule la venta y registre otra.');
    END IF;
    pkg_periodos.sp_validar_abierto(:NEW.id_periodo, :NEW.fecha_venta);
END trg_ventas_guard;
/
CREATE OR REPLACE TRIGGER trg_ventas_det_guard
BEFORE INSERT OR UPDATE OR DELETE ON ventas_detalle
FOR EACH ROW
DECLARE
    v_id_periodo NUMBER;
    v_fecha      DATE;
BEGIN
    IF UPDATING OR DELETING THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable,
            'Las lineas de una venta no pueden modificarse ni eliminarse.');
    END IF;
    SELECT id_periodo, fecha_venta
      INTO v_id_periodo, v_fecha
      FROM ventas
     WHERE id_venta = :NEW.id_venta;
    pkg_periodos.sp_validar_abierto(v_id_periodo, v_fecha);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La venta de la linea no existe.');
END trg_ventas_det_guard;
/
CREATE OR REPLACE TRIGGER trg_facturas_nodelete
BEFORE DELETE ON facturas
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Las facturas no pueden eliminarse.');
END trg_facturas_nodelete;
/
CREATE OR REPLACE TRIGGER trg_notas_nodelete
BEFORE DELETE ON facturas_notas_credito
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Las notas credito no pueden eliminarse.');
END trg_notas_nodelete;
/

-- ============ Tablas de solo inserción (append-only) ============
CREATE OR REPLACE TRIGGER trg_ro_produccion_lotes
BEFORE UPDATE OR DELETE ON produccion_lotes
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los lotes de produccion son de solo insercion.');
END trg_ro_produccion_lotes;
/
CREATE OR REPLACE TRIGGER trg_ro_abonos_cartera
BEFORE UPDATE OR DELETE ON abonos_cartera
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los abonos son de solo insercion.');
END trg_ro_abonos_cartera;
/
CREATE OR REPLACE TRIGGER trg_ro_ajustes_inventario
BEFORE UPDATE OR DELETE ON ajustes_inventario
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'Los ajustes de inventario son de solo insercion.');
END trg_ro_ajustes_inventario;
/
CREATE OR REPLACE TRIGGER trg_ro_notas_detalle
BEFORE UPDATE OR DELETE ON notas_credito_detalle
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'El detalle de notas credito es de solo insercion.');
END trg_ro_notas_detalle;
/
CREATE OR REPLACE TRIGGER trg_ro_auditoria
BEFORE UPDATE OR DELETE ON auditoria_cambios
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(pkg_errores.c_registro_inmutable, 'La bitacora de auditoria es de solo insercion.');
END trg_ro_auditoria;
/

-- ============ Integridad polimórfica de documentos ============
CREATE OR REPLACE TRIGGER trg_documentos_valida_entidad
BEFORE INSERT ON documentos_repositorio
FOR EACH ROW
DECLARE
    v_existe NUMBER := 0;
BEGIN
    IF :NEW.tipo_entidad = 'FACTURA' THEN
        SELECT COUNT(*) INTO v_existe FROM facturas WHERE id_factura = :NEW.id_entidad;
    ELSIF :NEW.tipo_entidad = 'NOTA_CREDITO' THEN
        SELECT COUNT(*) INTO v_existe FROM facturas_notas_credito WHERE id_nota = :NEW.id_entidad;
    ELSIF :NEW.tipo_entidad = 'RECEPCION_LECHE' THEN
        SELECT COUNT(*) INTO v_existe FROM recepcion_leche WHERE id_recepcion = :NEW.id_entidad;
    END IF;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe,
            'La entidad referenciada (' || :NEW.tipo_entidad || ' ' || :NEW.id_entidad || ') no existe.');
    END IF;
END trg_documentos_valida_entidad;
/

-- ============ Triggers de auditoría ============
CREATE OR REPLACE TRIGGER trg_aud_clientes
AFTER UPDATE OF limite_credito, activo ON clientes
FOR EACH ROW
BEGIN
    IF :OLD.limite_credito <> :NEW.limite_credito THEN
        pkg_auditoria.sp_registrar('CLIENTES', TO_CHAR(:NEW.id_cliente), 'LIMITE_CREDITO',
                                   TO_CHAR(:OLD.limite_credito), TO_CHAR(:NEW.limite_credito));
    END IF;
    IF :OLD.activo <> :NEW.activo THEN
        pkg_auditoria.sp_registrar('CLIENTES', TO_CHAR(:NEW.id_cliente), 'ACTIVO',
                                   TO_CHAR(:OLD.activo), TO_CHAR(:NEW.activo));
    END IF;
END trg_aud_clientes;
/
CREATE OR REPLACE TRIGGER trg_aud_proveedores
AFTER UPDATE OF activo ON proveedores
FOR EACH ROW
BEGIN
    IF :OLD.activo <> :NEW.activo THEN
        pkg_auditoria.sp_registrar('PROVEEDORES', TO_CHAR(:NEW.id_proveedor), 'ACTIVO',
                                   TO_CHAR(:OLD.activo), TO_CHAR(:NEW.activo));
    END IF;
END trg_aud_proveedores;
/
CREATE OR REPLACE TRIGGER trg_aud_productos
AFTER UPDATE OF nombre, unidad_medida, precio_base, tarifa_iva, activo ON productos
FOR EACH ROW
BEGIN
    IF :OLD.nombre <> :NEW.nombre THEN
        pkg_auditoria.sp_registrar('PRODUCTOS', TO_CHAR(:NEW.id_producto), 'NOMBRE',
                                   :OLD.nombre, :NEW.nombre);
    END IF;
    IF :OLD.unidad_medida <> :NEW.unidad_medida THEN
        pkg_auditoria.sp_registrar('PRODUCTOS', TO_CHAR(:NEW.id_producto), 'UNIDAD_MEDIDA',
                                   :OLD.unidad_medida, :NEW.unidad_medida);
    END IF;
    IF :OLD.precio_base <> :NEW.precio_base THEN
        pkg_auditoria.sp_registrar('PRODUCTOS', TO_CHAR(:NEW.id_producto), 'PRECIO_BASE',
                                   TO_CHAR(:OLD.precio_base), TO_CHAR(:NEW.precio_base));
    END IF;
    IF :OLD.tarifa_iva <> :NEW.tarifa_iva THEN
        pkg_auditoria.sp_registrar('PRODUCTOS', TO_CHAR(:NEW.id_producto), 'TARIFA_IVA',
                                   TO_CHAR(:OLD.tarifa_iva), TO_CHAR(:NEW.tarifa_iva));
    END IF;
    IF :OLD.activo <> :NEW.activo THEN
        pkg_auditoria.sp_registrar('PRODUCTOS', TO_CHAR(:NEW.id_producto), 'ACTIVO',
                                   TO_CHAR(:OLD.activo), TO_CHAR(:NEW.activo));
    END IF;
END trg_aud_productos;
/
CREATE OR REPLACE TRIGGER trg_aud_periodos
AFTER UPDATE OF estado ON periodos_quincena
FOR EACH ROW
BEGIN
    IF :OLD.estado <> :NEW.estado THEN
        pkg_auditoria.sp_registrar('PERIODOS_QUINCENA', TO_CHAR(:NEW.id_periodo), 'ESTADO', :OLD.estado, :NEW.estado);
    END IF;
END trg_aud_periodos;
/
CREATE OR REPLACE TRIGGER trg_aud_ventas
AFTER UPDATE OF estado_pago ON ventas
FOR EACH ROW
BEGIN
    IF :OLD.estado_pago <> :NEW.estado_pago THEN
        pkg_auditoria.sp_registrar('VENTAS', TO_CHAR(:NEW.id_venta), 'ESTADO_PAGO', :OLD.estado_pago, :NEW.estado_pago);
    END IF;
END trg_aud_ventas;
/
CREATE OR REPLACE TRIGGER trg_aud_facturas
AFTER UPDATE OF estado_dian ON facturas
FOR EACH ROW
BEGIN
    IF :OLD.estado_dian <> :NEW.estado_dian THEN
        pkg_auditoria.sp_registrar('FACTURAS', TO_CHAR(:NEW.id_factura), 'ESTADO_DIAN', :OLD.estado_dian, :NEW.estado_dian);
    END IF;
END trg_aud_facturas;
/
CREATE OR REPLACE TRIGGER trg_aud_parametros
AFTER UPDATE OF valor_numero ON parametros_sistema
FOR EACH ROW
BEGIN
    -- CORRECCION: DECODE solo existe en SQL (PLS-00204). Comparacion
    -- explicita que preserva la semantica NULL-segura del original.
    IF (:OLD.valor_numero IS NULL AND :NEW.valor_numero IS NOT NULL)
       OR (:OLD.valor_numero IS NOT NULL AND :NEW.valor_numero IS NULL)
       OR (:OLD.valor_numero <> :NEW.valor_numero) THEN
        pkg_auditoria.sp_registrar('PARAMETROS_SISTEMA', :NEW.clave, 'VALOR_NUMERO',
                                   TO_CHAR(:OLD.valor_numero), TO_CHAR(:NEW.valor_numero));
    END IF;
END trg_aud_parametros;
/

-- ============ Parte H - Vistas ============

-- ============ Producción e inventario ============

-- ============ vw_estado_periodos ============
CREATE OR REPLACE VIEW vw_estado_periodos AS
SELECT id_periodo, anio, mes, quincena, fecha_inicio, fecha_fin, estado
  FROM periodos_quincena
WITH READ ONLY;

-- ============ vw_inventario_valorizado ============
CREATE OR REPLACE VIEW vw_inventario_valorizado AS
SELECT id_producto, codigo_sku, nombre AS producto, unidad_medida, stock_actual, precio_base,
       stock_actual * precio_base AS valor_venta_inventario
  FROM productos
 WHERE activo = 1
WITH READ ONLY;

-- ============ vw_alertas_caducidad ============
CREATE OR REPLACE VIEW vw_alertas_caducidad AS
SELECT l.codigo_lote, p.nombre AS producto, l.cantidad_obtenida AS cantidad_producida,
       l.fecha_vencimiento,
       TRUNC(l.fecha_vencimiento) - TRUNC(SYSDATE) AS dias_restantes,
       fn_semaforo_caducidad(TRUNC(l.fecha_vencimiento) - TRUNC(SYSDATE)) AS nivel_alerta
  FROM produccion_lotes l
  JOIN productos p ON p.id_producto = l.id_producto
 WHERE l.fecha_vencimiento <= TRUNC(SYSDATE) + 7
WITH READ ONLY;

-- ============ vw_trazabilidad_produccion ============
CREATE OR REPLACE VIEW vw_trazabilidad_produccion AS
SELECT l.codigo_lote, p.nombre AS producto_fabricado, l.fecha_produccion,
       l.litros_leche_usados, l.cantidad_obtenida,
       fn_rendimiento_pct(l.cantidad_obtenida, l.litros_leche_usados) AS porcentaje_rendimiento,
       l.costo_total,
       ROUND(l.costo_total / l.cantidad_obtenida, 2) AS costo_unitario
  FROM produccion_lotes l
  JOIN productos p ON p.id_producto = l.id_producto
WITH READ ONLY;

-- ============ Comercial y financiera ============

-- ============ vw_dashboard_cartera ============
CREATE OR REPLACE VIEW vw_dashboard_cartera AS
SELECT c.id_cliente, c.nombre AS cliente, c.telefono, c.limite_credito, c.saldo_deudor,
       c.limite_credito - c.saldo_deudor AS cupo_disponible,
       NVL(m.dias_mora, 0) AS dias_mora,
       fn_estado_credito(c.limite_credito, c.saldo_deudor, NVL(m.dias_mora, 0)) AS estado_credito
  FROM clientes c
  LEFT JOIN (SELECT v.id_cliente, MAX(TRUNC(SYSDATE) - v.fecha_vencimiento) AS dias_mora
               FROM ventas v
              WHERE v.estado_pago = 'PENDIENTE'
                AND v.fecha_vencimiento < TRUNC(SYSDATE)
              GROUP BY v.id_cliente) m ON m.id_cliente = c.id_cliente
 WHERE c.activo = 1
WITH READ ONLY;

-- ============ vw_ventas_consolidadas ============
CREATE OR REPLACE VIEW vw_ventas_consolidadas AS
SELECT v.id_venta, v.id_cliente, c.nombre AS cliente, v.fecha_venta, v.tipo_venta, v.fecha_vencimiento,
       v.subtotal_venta, v.total_iva, v.total_venta, v.saldo_pendiente, v.estado_pago
  FROM ventas v
  JOIN clientes c ON c.id_cliente = v.id_cliente
WITH READ ONLY;

-- ============ vw_detalle_ticket_venta ============
CREATE OR REPLACE VIEW vw_detalle_ticket_venta AS
SELECT v.id_venta, c.nombre AS cliente, v.fecha_venta, d.id_producto, p.nombre AS producto,
       d.cantidad, d.precio_unitario, d.tarifa_iva, d.subtotal, d.valor_iva,
       d.subtotal + d.valor_iva AS total_linea
  FROM ventas_detalle d
  JOIN ventas v ON v.id_venta = d.id_venta
  JOIN clientes c ON c.id_cliente = v.id_cliente
  JOIN productos p ON p.id_producto = d.id_producto
WITH READ ONLY;

-- ============ vw_gastos_por_categoria ============
CREATE OR REPLACE VIEW vw_gastos_por_categoria AS
SELECT p.id_periodo, p.anio, p.mes, p.quincena, c.nombre AS categoria, SUM(g.monto) AS total_gastos
  FROM gastos_operativos g
  JOIN periodos_quincena p ON p.id_periodo = g.id_periodo
  JOIN categorias_gasto c ON c.id_categoria = g.id_categoria
 GROUP BY p.id_periodo, p.anio, p.mes, p.quincena, c.nombre
WITH READ ONLY;

-- ============ vw_resultado_periodo ============
CREATE OR REPLACE VIEW vw_resultado_periodo AS
SELECT p.id_periodo, p.anio, p.mes, p.quincena, p.estado,
       NVL(v.ingresos, 0)   AS ingresos_ventas,
       NVL(l.costo, 0)      AS costo_produccion,
       NVL(g.gastos, 0)     AS gastos_operativos,
       NVL(v.castigos, 0)   AS cartera_castigada,
       NVL(v.ingresos, 0) - NVL(l.costo, 0) - NVL(g.gastos, 0) - NVL(v.castigos, 0) AS resultado_estimado
  FROM periodos_quincena p
  LEFT JOIN (SELECT id_periodo, SUM(subtotal_venta) AS ingresos, SUM(monto_castigado) AS castigos
               FROM ventas
              WHERE estado_pago <> 'ANULADA'
              GROUP BY id_periodo) v ON v.id_periodo = p.id_periodo
  LEFT JOIN (SELECT q.id_periodo, SUM(lt.costo_total) AS costo
               FROM produccion_lotes lt
               JOIN periodos_quincena q ON lt.fecha_produccion BETWEEN q.fecha_inicio AND q.fecha_fin
              GROUP BY q.id_periodo) l ON l.id_periodo = p.id_periodo
  LEFT JOIN (SELECT id_periodo, SUM(monto) AS gastos
               FROM gastos_operativos
              GROUP BY id_periodo) g ON g.id_periodo = p.id_periodo
WITH READ ONLY;

-- ============ Proveedores y acopio ============

-- ============ vw_resumen_pago_lecheros ============
CREATE OR REPLACE VIEW vw_resumen_pago_lecheros AS
SELECT p.id_periodo, p.anio, p.mes, p.quincena, pr.id_proveedor, pr.nombre AS proveedor,
       SUM(CASE WHEN r.estado_calidad = 'APROBADO'  THEN r.litros ELSE 0 END) AS litros_a_pagar,
       SUM(CASE WHEN r.estado_calidad = 'RECHAZADO' THEN r.litros ELSE 0 END) AS litros_rechazados
  FROM recepcion_leche r
  JOIN proveedores pr ON pr.id_proveedor = r.id_proveedor
  JOIN periodos_quincena p ON p.id_periodo = r.id_periodo
 GROUP BY p.id_periodo, p.anio, p.mes, p.quincena, pr.id_proveedor, pr.nombre
WITH READ ONLY;

-- ============ vw_calidad_leche_proveedor ============
CREATE OR REPLACE VIEW vw_calidad_leche_proveedor AS
SELECT pr.id_proveedor, pr.nombre AS proveedor,
       COUNT(r.id_recepcion) AS numero_entregas,
       ROUND(AVG(r.temperatura), 2) AS temperatura_promedio,
       ROUND(AVG(r.acidez), 2) AS acidez_promedio,
       SUM(CASE WHEN r.estado_calidad = 'RECHAZADO' THEN 1 ELSE 0 END) AS entregas_rechazadas,
       ROUND(100 * SUM(CASE WHEN r.estado_calidad = 'RECHAZADO' THEN 1 ELSE 0 END)
             / COUNT(r.id_recepcion), 2) AS porcentaje_rechazo
  FROM recepcion_leche r
  JOIN proveedores pr ON pr.id_proveedor = r.id_proveedor
 GROUP BY pr.id_proveedor, pr.nombre
WITH READ ONLY;

-- ============ Documentos, catálogos y consulta operativa ============

-- ============ vw_documentos_pendientes_carga ============
CREATE OR REPLACE VIEW vw_documentos_pendientes_carga AS
SELECT id_documento, tipo_entidad, id_entidad, nombre_archivo, mime_type, estado_carga, intentos, ultimo_error, fecha_registro
  FROM documentos_repositorio
 WHERE estado_carga IN ('PENDIENTE', 'ERROR')
WITH READ ONLY;

-- ============ vw_clientes, vw_proveedores, vw_productos ============
CREATE OR REPLACE VIEW vw_clientes AS
SELECT id_cliente, tipo_documento, numero_documento, nombre, email, telefono, direccion,
       limite_credito, saldo_deudor, activo
  FROM clientes
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_proveedores AS
SELECT id_proveedor, tipo_documento, numero_documento, nombre, telefono, tipo_proveedor, activo
  FROM proveedores
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_productos AS
SELECT id_producto, codigo_sku, nombre, unidad_medida, precio_base, tarifa_iva, stock_actual, activo
  FROM productos
WITH READ ONLY;

-- ============ vw_facturas ============
CREATE OR REPLACE VIEW vw_facturas AS
SELECT id_factura, id_venta, numero_factura, fecha_emision, fecha_vencimiento,
       subtotal_base, total_iva, total_factura, cufe, qr_code_url, estado_dian, usuario_emisor
  FROM facturas
WITH READ ONLY;

-- ============ vw_abonos_cartera ============
CREATE OR REPLACE VIEW vw_abonos_cartera AS
SELECT a.id_abono, a.id_recibo, v.id_cliente, c.nombre AS cliente, a.id_venta, a.fecha_abono,
       a.monto, a.metodo_pago, a.referencia_pago, a.usuario_registro
  FROM abonos_cartera a
  JOIN ventas v ON v.id_venta = a.id_venta
  JOIN clientes c ON c.id_cliente = v.id_cliente
WITH READ ONLY;

-- ============ vw_categorias_gasto y vw_resoluciones_facturacion ============
CREATE OR REPLACE VIEW vw_categorias_gasto AS
SELECT id_categoria, nombre, activo
  FROM categorias_gasto
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_resoluciones_facturacion AS
SELECT id_resolucion, tipo_documento, numero_resolucion, prefijo, rango_desde, rango_hasta,
       consecutivo_actual, vigente_desde, vigente_hasta, activa
  FROM resoluciones_facturacion
WITH READ ONLY;

-- ============ vw_auditoria_cambios y vw_log_errores ============
CREATE OR REPLACE VIEW vw_auditoria_cambios AS
SELECT id_auditoria, fecha, usuario, tabla, id_registro, columna, valor_anterior, valor_nuevo
  FROM auditoria_cambios
WITH READ ONLY;

CREATE OR REPLACE VIEW vw_log_errores AS
SELECT id_log, fecha, usuario, unidad, codigo_error, mensaje, contexto
  FROM log_errores
WITH READ ONLY;

-- ============ Parte I - Packages de negocio ============

-- ============ pkg_catalogos - clientes, proveedores y productos ============

-- ============ pkg_catalogos ============
CREATE OR REPLACE PACKAGE pkg_catalogos AUTHID DEFINER AS
    PROCEDURE sp_crear_cliente(
        p_tipo_documento   IN  VARCHAR2,
        p_numero_documento IN  VARCHAR2,
        p_nombre           IN  VARCHAR2,
        p_email            IN  VARCHAR2,
        p_telefono         IN  VARCHAR2,
        p_direccion        IN  VARCHAR2,
        p_limite_credito   IN  NUMBER,
        p_id_cliente       OUT NUMBER
    );
    PROCEDURE sp_actualizar_cliente(
        p_id_cliente IN NUMBER,
        p_nombre     IN VARCHAR2,
        p_email      IN VARCHAR2,
        p_telefono   IN VARCHAR2,
        p_direccion  IN VARCHAR2
    );
    PROCEDURE sp_cambiar_limite_credito(p_id_cliente IN NUMBER, p_nuevo_limite IN NUMBER);

    PROCEDURE sp_crear_proveedor(
        p_tipo_documento   IN  VARCHAR2,
        p_numero_documento IN  VARCHAR2,
        p_nombre           IN  VARCHAR2,
        p_telefono         IN  VARCHAR2,
        p_tipo_proveedor   IN  VARCHAR2,
        p_id_proveedor     OUT NUMBER
    );
    PROCEDURE sp_actualizar_proveedor(p_id_proveedor IN NUMBER, p_nombre IN VARCHAR2, p_telefono IN VARCHAR2);

    PROCEDURE sp_crear_producto(
        p_codigo_sku    IN  VARCHAR2,
        p_nombre        IN  VARCHAR2,
        p_unidad_medida IN  VARCHAR2,
        p_precio_base   IN  NUMBER,
        p_tarifa_iva    IN  NUMBER,
        p_id_producto   OUT NUMBER
    );
    -- Edita nombre y unidad de medida (OPERATIVO; supuesto C-07 del dashboard).
    -- La unidad solo puede cambiar si el producto no tiene movimientos.
    PROCEDURE sp_actualizar_producto(p_id_producto IN NUMBER, p_nombre IN VARCHAR2, p_unidad_medida IN VARCHAR2);
    PROCEDURE sp_actualizar_precio(p_id_producto IN NUMBER, p_precio_base IN NUMBER, p_tarifa_iva IN NUMBER);

    -- p_entidad: CLIENTE, PROVEEDOR, PRODUCTO o CATEGORIA_GASTO
    PROCEDURE sp_cambiar_estado(p_entidad IN VARCHAR2, p_id IN NUMBER, p_activo IN NUMBER);
END pkg_catalogos;
/
CREATE OR REPLACE PACKAGE BODY pkg_catalogos AS

    PROCEDURE pr_requerir_texto(p_valor IN VARCHAR2, p_campo IN VARCHAR2, p_max IN PLS_INTEGER) IS
    BEGIN
        IF p_valor IS NULL OR TRIM(p_valor) IS NULL OR LENGTH(p_valor) > p_max THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'El campo ' || p_campo || ' es obligatorio (maximo ' || p_max || ' caracteres).');
        END IF;
    END pr_requerir_texto;

    PROCEDURE pr_validar_documento(p_tipo IN VARCHAR2, p_numero IN VARCHAR2) IS
    BEGIN
        IF p_tipo IS NULL OR p_tipo NOT IN ('CC', 'NIT', 'CE', 'PASAPORTE', 'TI') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Tipo de documento invalido.');
        END IF;
        IF p_numero IS NULL OR NOT REGEXP_LIKE(p_numero, '^[A-Za-z0-9-]{5,20}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Numero de documento invalido (5 a 20 letras, numeros o guion).');
        END IF;
    END pr_validar_documento;

    PROCEDURE pr_validar_email(p_email IN VARCHAR2) IS
    BEGIN
        IF p_email IS NOT NULL
           AND NOT REGEXP_LIKE(p_email, '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Correo electronico invalido.');
        END IF;
    END pr_validar_email;

    PROCEDURE sp_crear_cliente(
        p_tipo_documento   IN  VARCHAR2,
        p_numero_documento IN  VARCHAR2,
        p_nombre           IN  VARCHAR2,
        p_email            IN  VARCHAR2,
        p_telefono         IN  VARCHAR2,
        p_direccion        IN  VARCHAR2,
        p_limite_credito   IN  NUMBER,
        p_id_cliente       OUT NUMBER
    ) IS
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pr_validar_documento(p_tipo_documento, p_numero_documento);
        pr_requerir_texto(p_nombre, 'nombre', 120);
        pr_validar_email(p_email);
        IF p_limite_credito IS NULL OR p_limite_credito < 0 OR p_limite_credito <> ROUND(p_limite_credito, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Limite de credito invalido.');
        END IF;
        IF p_limite_credito > 0 THEN
            pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        END IF;

        INSERT INTO clientes (tipo_documento, numero_documento, nombre, email, telefono, direccion,
                              limite_credito, usuario_creacion)
        VALUES (p_tipo_documento, p_numero_documento, TRIM(p_nombre), p_email, p_telefono, p_direccion,
                p_limite_credito, v_usuario)
        RETURNING id_cliente INTO p_id_cliente;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_cliente := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_cliente', 'doc=' || p_tipo_documento || ' ' || p_numero_documento);
    END sp_crear_cliente;

    PROCEDURE sp_actualizar_cliente(
        p_id_cliente IN NUMBER,
        p_nombre     IN VARCHAR2,
        p_email      IN VARCHAR2,
        p_telefono   IN VARCHAR2,
        p_direccion  IN VARCHAR2
    ) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pr_requerir_texto(p_nombre, 'nombre', 120);
        pr_validar_email(p_email);
        UPDATE clientes
           SET nombre = TRIM(p_nombre), email = p_email, telefono = p_telefono, direccion = p_direccion
         WHERE id_cliente = p_id_cliente;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_cliente', 'id_cliente=' || p_id_cliente);
    END sp_actualizar_cliente;

    PROCEDURE sp_cambiar_limite_credito(p_id_cliente IN NUMBER, p_nuevo_limite IN NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_nuevo_limite IS NULL OR p_nuevo_limite < 0 OR p_nuevo_limite <> ROUND(p_nuevo_limite, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Limite de credito invalido.');
        END IF;
        UPDATE clientes SET limite_credito = p_nuevo_limite WHERE id_cliente = p_id_cliente;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_cambiar_limite_credito', 'id_cliente=' || p_id_cliente);
    END sp_cambiar_limite_credito;

    PROCEDURE sp_crear_proveedor(
        p_tipo_documento   IN  VARCHAR2,
        p_numero_documento IN  VARCHAR2,
        p_nombre           IN  VARCHAR2,
        p_telefono         IN  VARCHAR2,
        p_tipo_proveedor   IN  VARCHAR2,
        p_id_proveedor     OUT NUMBER
    ) IS
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pr_validar_documento(p_tipo_documento, p_numero_documento);
        pr_requerir_texto(p_nombre, 'nombre', 120);
        IF p_tipo_proveedor IS NULL OR p_tipo_proveedor NOT IN ('LECHERO', 'INSUMOS') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Tipo de proveedor invalido.');
        END IF;
        INSERT INTO proveedores (tipo_documento, numero_documento, nombre, telefono, tipo_proveedor, usuario_creacion)
        VALUES (p_tipo_documento, p_numero_documento, TRIM(p_nombre), p_telefono, p_tipo_proveedor, v_usuario)
        RETURNING id_proveedor INTO p_id_proveedor;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_proveedor := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_proveedor', 'doc=' || p_tipo_documento || ' ' || p_numero_documento);
    END sp_crear_proveedor;

    PROCEDURE sp_actualizar_proveedor(p_id_proveedor IN NUMBER, p_nombre IN VARCHAR2, p_telefono IN VARCHAR2) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pr_requerir_texto(p_nombre, 'nombre', 120);
        UPDATE proveedores SET nombre = TRIM(p_nombre), telefono = p_telefono WHERE id_proveedor = p_id_proveedor;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El proveedor no existe.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_proveedor', 'id_proveedor=' || p_id_proveedor);
    END sp_actualizar_proveedor;

    PROCEDURE sp_crear_producto(
        p_codigo_sku    IN  VARCHAR2,
        p_nombre        IN  VARCHAR2,
        p_unidad_medida IN  VARCHAR2,
        p_precio_base   IN  NUMBER,
        p_tarifa_iva    IN  NUMBER,
        p_id_producto   OUT NUMBER
    ) IS
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_codigo_sku IS NULL OR NOT REGEXP_LIKE(p_codigo_sku, '^[A-Z0-9-]{3,20}$') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'El SKU debe tener de 3 a 20 caracteres: mayusculas, numeros o guion.');
        END IF;
        pr_requerir_texto(p_nombre, 'nombre', 100);
        IF p_unidad_medida IS NULL OR p_unidad_medida NOT IN ('KG', 'GR', 'LT', 'ML', 'UND', 'PAQ') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Unidad de medida invalida.');
        END IF;
        IF p_precio_base IS NULL OR p_precio_base < 0 OR p_precio_base <> ROUND(p_precio_base, 2)
           OR p_tarifa_iva IS NULL OR p_tarifa_iva NOT BETWEEN 0 AND 100 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Precio o tarifa de IVA invalidos.');
        END IF;
        INSERT INTO productos (codigo_sku, nombre, unidad_medida, precio_base, tarifa_iva, usuario_creacion)
        VALUES (p_codigo_sku, TRIM(p_nombre), p_unidad_medida, p_precio_base, p_tarifa_iva, v_usuario)
        RETURNING id_producto INTO p_id_producto;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_producto := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_producto', 'sku=' || p_codigo_sku);
    END sp_crear_producto;

    PROCEDURE sp_actualizar_producto(p_id_producto IN NUMBER, p_nombre IN VARCHAR2, p_unidad_medida IN VARCHAR2) IS
        v_unidad_actual productos.unidad_medida%TYPE;
        v_stock         productos.stock_actual%TYPE;
        v_movimientos   NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        pr_requerir_texto(p_nombre, 'nombre', 100);
        IF p_unidad_medida IS NULL OR p_unidad_medida NOT IN ('KG', 'GR', 'LT', 'ML', 'UND', 'PAQ') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Unidad de medida invalida.');
        END IF;

        -- Bloquea la fila: evita que una venta o un ajuste concurrente cambie los
        -- movimientos entre la verificacion y el UPDATE.
        BEGIN
            SELECT unidad_medida, stock_actual
              INTO v_unidad_actual, v_stock
              FROM productos
             WHERE id_producto = p_id_producto
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe.');
        END;

        IF p_unidad_medida <> v_unidad_actual THEN
            SELECT COUNT(*) INTO v_movimientos FROM (
                SELECT 1 FROM ventas_detalle        WHERE id_producto = p_id_producto AND ROWNUM = 1
                UNION ALL
                SELECT 1 FROM ajustes_inventario    WHERE id_producto = p_id_producto AND ROWNUM = 1
                UNION ALL
                SELECT 1 FROM produccion_lotes      WHERE id_producto = p_id_producto AND ROWNUM = 1
                UNION ALL
                SELECT 1 FROM notas_credito_detalle WHERE id_producto = p_id_producto AND ROWNUM = 1
            );
            IF v_movimientos > 0 OR v_stock <> 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                    'La unidad de medida no puede cambiarse: el producto ya tiene movimientos o existencias.');
            END IF;
        END IF;

        UPDATE productos
           SET nombre = TRIM(p_nombre), unidad_medida = p_unidad_medida
         WHERE id_producto = p_id_producto;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_producto', 'id_producto=' || p_id_producto);
    END sp_actualizar_producto;

    PROCEDURE sp_actualizar_precio(p_id_producto IN NUMBER, p_precio_base IN NUMBER, p_tarifa_iva IN NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_precio_base IS NULL OR p_precio_base < 0 OR p_precio_base <> ROUND(p_precio_base, 2)
           OR p_tarifa_iva IS NULL OR p_tarifa_iva NOT BETWEEN 0 AND 100 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Precio o tarifa de IVA invalidos.');
        END IF;
        UPDATE productos SET precio_base = p_precio_base, tarifa_iva = p_tarifa_iva WHERE id_producto = p_id_producto;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_actualizar_precio', 'id_producto=' || p_id_producto);
    END sp_actualizar_precio;

    PROCEDURE sp_cambiar_estado(p_entidad IN VARCHAR2, p_id IN NUMBER, p_activo IN NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_activo IS NULL OR p_activo NOT IN (0, 1) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El estado debe ser 0 o 1.');
        END IF;
        IF p_entidad = 'CLIENTE' THEN
            UPDATE clientes SET activo = p_activo WHERE id_cliente = p_id;
        ELSIF p_entidad = 'PROVEEDOR' THEN
            UPDATE proveedores SET activo = p_activo WHERE id_proveedor = p_id;
        ELSIF p_entidad = 'PRODUCTO' THEN
            UPDATE productos SET activo = p_activo WHERE id_producto = p_id;
        ELSIF p_entidad = 'CATEGORIA_GASTO' THEN
            UPDATE categorias_gasto SET activo = p_activo WHERE id_categoria = p_id;
        ELSE
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Entidad no soportada.');
        END IF;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El registro no existe.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_cambiar_estado', p_entidad || ' id=' || p_id);
    END sp_cambiar_estado;

END pkg_catalogos;
/

-- ============ pkg_acopio y pkg_produccion ============

-- ============ pkg_acopio ============
CREATE OR REPLACE PACKAGE pkg_acopio AUTHID DEFINER AS
    PROCEDURE sp_registrar_recepcion(
        p_id_proveedor   IN  NUMBER,
        p_litros         IN  NUMBER,
        p_temperatura    IN  NUMBER,
        p_acidez         IN  NUMBER,
        p_fecha          IN  DATE,
        p_id_recepcion   OUT NUMBER,
        p_estado_calidad OUT VARCHAR2
    );
END pkg_acopio;
/
CREATE OR REPLACE PACKAGE BODY pkg_acopio AS

    PROCEDURE sp_registrar_recepcion(
        p_id_proveedor   IN  NUMBER,
        p_litros         IN  NUMBER,
        p_temperatura    IN  NUMBER,
        p_acidez         IN  NUMBER,
        p_fecha          IN  DATE,
        p_id_recepcion   OUT NUMBER,
        p_estado_calidad OUT VARCHAR2
    ) IS
        v_fecha      DATE := TRUNC(NVL(p_fecha, SYSDATE));
        v_id_periodo NUMBER;
        v_tipo       VARCHAR2(10);
        v_activo     NUMBER;
        v_motivo     VARCHAR2(200);
        v_temp_max   NUMBER;
        v_acid_max   NUMBER;
        v_usuario    VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_proveedor IS NULL OR p_litros IS NULL OR p_litros <= 0 OR p_litros <> ROUND(p_litros, 2)
           OR p_temperatura IS NULL OR p_acidez IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Proveedor, litros, temperatura y acidez son obligatorios (litros mayores a cero).');
        END IF;

        BEGIN
            SELECT tipo_proveedor, activo INTO v_tipo, v_activo
              FROM proveedores WHERE id_proveedor = p_id_proveedor;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El proveedor no existe.');
        END;
        IF v_tipo <> 'LECHERO' OR v_activo = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'El proveedor debe estar activo y ser de tipo LECHERO.');
        END IF;

        v_id_periodo := pkg_periodos.fn_id_periodo(v_fecha);
        pkg_periodos.sp_validar_abierto(v_id_periodo, v_fecha);

        v_temp_max := pkg_parametros.fn_numero('TEMP_MAX_LECHE_C');
        v_acid_max := pkg_parametros.fn_numero('ACIDEZ_MAX_DORNIC');
        IF p_temperatura > v_temp_max THEN
            v_motivo := 'Temperatura ' || p_temperatura || ' C supera el maximo de ' || v_temp_max || ' C';
        ELSIF p_acidez > v_acid_max THEN
            v_motivo := 'Acidez ' || p_acidez || ' supera el maximo de ' || v_acid_max;
        END IF;
        p_estado_calidad := CASE WHEN v_motivo IS NULL THEN 'APROBADO' ELSE 'RECHAZADO' END;

        INSERT INTO recepcion_leche (id_proveedor, id_periodo, fecha, litros, temperatura, acidez,
                                     estado_calidad, motivo_rechazo, usuario_registro)
        VALUES (p_id_proveedor, v_id_periodo, v_fecha, p_litros, p_temperatura, p_acidez,
                p_estado_calidad, v_motivo, v_usuario)
        RETURNING id_recepcion INTO p_id_recepcion;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_recepcion := NULL;
            p_estado_calidad := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_recepcion', 'id_proveedor=' || p_id_proveedor);
    END sp_registrar_recepcion;

END pkg_acopio;
/

-- ============ pkg_produccion ============
CREATE OR REPLACE PACKAGE pkg_produccion AUTHID DEFINER AS
    PROCEDURE sp_registrar_lote(
        p_id_producto       IN  NUMBER,
        p_litros_usados     IN  NUMBER,
        p_cantidad_obtenida IN  NUMBER,
        p_costo_por_litro   IN  NUMBER,
        p_fecha_produccion  IN  DATE,
        p_fecha_vencimiento IN  DATE,
        p_id_lote           OUT NUMBER,
        p_codigo_lote       OUT VARCHAR2
    );

    -- p_tipo_ajuste: MERMA, DANO, VENCIMIENTO, MUESTRA (restan); INGRESO_INICIAL, CORRECCION_MAS (suman);
    -- CORRECCION_MENOS (resta). p_cantidad es siempre positiva.
    PROCEDURE sp_registrar_ajuste(
        p_id_producto IN  NUMBER,
        p_tipo_ajuste IN  VARCHAR2,
        p_cantidad    IN  NUMBER,
        p_observacion IN  VARCHAR2,
        p_id_ajuste   OUT NUMBER
    );
END pkg_produccion;
/
CREATE OR REPLACE PACKAGE BODY pkg_produccion AS

    PROCEDURE sp_registrar_lote(
        p_id_producto       IN  NUMBER,
        p_litros_usados     IN  NUMBER,
        p_cantidad_obtenida IN  NUMBER,
        p_costo_por_litro   IN  NUMBER,
        p_fecha_produccion  IN  DATE,
        p_fecha_vencimiento IN  DATE,
        p_id_lote           OUT NUMBER,
        p_codigo_lote       OUT VARCHAR2
    ) IS
        v_sku        VARCHAR2(20);
        v_activo     NUMBER;
        v_fecha      DATE := TRUNC(NVL(p_fecha_produccion, SYSDATE));
        v_vence      DATE;
        v_secuencia  NUMBER;
        v_costo      NUMBER;
        v_usuario    VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_producto IS NULL OR p_litros_usados IS NULL OR p_litros_usados <= 0
           OR p_cantidad_obtenida IS NULL OR p_cantidad_obtenida <= 0
           OR p_costo_por_litro IS NULL OR p_costo_por_litro < 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Producto, litros y cantidad son obligatorios y mayores a cero; el costo por litro no puede ser negativo.');
        END IF;
        pkg_periodos.sp_validar_abierto(pkg_periodos.fn_id_periodo(v_fecha), v_fecha);

        -- Se bloquea el producto: serializa la generacion del codigo y el ingreso de stock.
        BEGIN
            SELECT codigo_sku, activo INTO v_sku, v_activo
              FROM productos WHERE id_producto = p_id_producto FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe.');
        END;
        IF v_activo = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'El producto esta inactivo.');
        END IF;

        SELECT COUNT(*) + 1 INTO v_secuencia
          FROM produccion_lotes
         WHERE id_producto = p_id_producto AND fecha_produccion = v_fecha;
        p_codigo_lote := v_sku || '-' || TO_CHAR(v_fecha, 'YYYYMMDD') || '-' || LPAD(v_secuencia, 3, '0');

        v_vence := NVL(TRUNC(p_fecha_vencimiento), v_fecha + pkg_parametros.fn_numero('DIAS_VIDA_UTIL_DEFAULT'));
        v_costo := ROUND(p_litros_usados * p_costo_por_litro, 2);

        INSERT INTO produccion_lotes (codigo_lote, id_producto, fecha_produccion, litros_leche_usados,
                                      cantidad_obtenida, costo_total, fecha_vencimiento, usuario_registro)
        VALUES (p_codigo_lote, p_id_producto, v_fecha, p_litros_usados,
                p_cantidad_obtenida, v_costo, v_vence, v_usuario)
        RETURNING id_lote INTO p_id_lote;

        UPDATE productos SET stock_actual = stock_actual + p_cantidad_obtenida
         WHERE id_producto = p_id_producto;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_lote := NULL;
            p_codigo_lote := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_lote', 'id_producto=' || p_id_producto);
    END sp_registrar_lote;

    PROCEDURE sp_registrar_ajuste(
        p_id_producto IN  NUMBER,
        p_tipo_ajuste IN  VARCHAR2,
        p_cantidad    IN  NUMBER,
        p_observacion IN  VARCHAR2,
        p_id_ajuste   OUT NUMBER
    ) IS
        v_stock   NUMBER;
        v_delta   NUMBER;
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_tipo_ajuste IS NULL OR p_tipo_ajuste NOT IN
           ('MERMA', 'DANO', 'VENCIMIENTO', 'MUESTRA', 'INGRESO_INICIAL', 'CORRECCION_MAS', 'CORRECCION_MENOS') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Tipo de ajuste invalido.');
        END IF;
        IF p_id_producto IS NULL OR p_cantidad IS NULL OR p_cantidad <= 0 OR p_cantidad <> ROUND(p_cantidad, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Producto y cantidad (mayor a cero) son obligatorios.');
        END IF;
        IF p_observacion IS NULL OR LENGTH(TRIM(p_observacion)) < 5 OR LENGTH(p_observacion) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'La observacion es obligatoria (5 a 255 caracteres).');
        END IF;
        -- Sumar stock o corregir hacia arriba es una decision de control: solo ADMIN.
        IF p_tipo_ajuste IN ('INGRESO_INICIAL', 'CORRECCION_MAS', 'CORRECCION_MENOS') THEN
            pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        END IF;
        v_delta := CASE WHEN p_tipo_ajuste IN ('INGRESO_INICIAL', 'CORRECCION_MAS') THEN p_cantidad ELSE -p_cantidad END;

        BEGIN
            SELECT stock_actual INTO v_stock
              FROM productos WHERE id_producto = p_id_producto FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El producto no existe.');
        END;
        IF v_stock + v_delta < 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_stock_insuficiente,
                'El ajuste dejaria el stock negativo (stock actual ' || v_stock || ').');
        END IF;

        UPDATE productos SET stock_actual = stock_actual + v_delta WHERE id_producto = p_id_producto;
        INSERT INTO ajustes_inventario (id_producto, tipo_ajuste, cantidad_delta, observacion, usuario_registro)
        VALUES (p_id_producto, p_tipo_ajuste, v_delta, TRIM(p_observacion), v_usuario)
        RETURNING id_ajuste INTO p_id_ajuste;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_ajuste := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_ajuste', 'id_producto=' || p_id_producto || ';tipo=' || p_tipo_ajuste);
    END sp_registrar_ajuste;

END pkg_produccion;
/

-- ============ pkg_ventas ============

-- ============ pkg_ventas ============
CREATE OR REPLACE PACKAGE pkg_ventas AUTHID DEFINER AS
    PROCEDURE sp_registrar_venta(
        p_id_cliente  IN  NUMBER,
        p_tipo_venta  IN  VARCHAR2,
        p_lineas_json IN  CLOB,
        p_id_venta    OUT NUMBER,
        p_total_venta OUT NUMBER
    );

    PROCEDURE sp_anular_venta(p_id_venta IN NUMBER, p_motivo IN VARCHAR2);
END pkg_ventas;
/
CREATE OR REPLACE PACKAGE BODY pkg_ventas AS

    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    PROCEDURE sp_registrar_venta(
        p_id_cliente  IN  NUMBER,
        p_tipo_venta  IN  VARCHAR2,
        p_lineas_json IN  CLOB,
        p_id_venta    OUT NUMBER,
        p_total_venta OUT NUMBER
    ) IS
        v_ids        t_num;   -- productos solicitados (agrupados, ordenados)
        v_lock_ids   sys.odcinumberlist;  -- CORRECCION: tipo SQL para TABLE()
        v_cant       t_num;   -- cantidades solicitadas
        v_inval      t_num;   -- lineas con cantidad nula o no positiva
        v_p_id       t_num;   -- productos bloqueados
        v_p_precio   t_num;
        v_p_iva      t_num;
        v_p_stock    t_num;
        v_p_activo   t_num;
        v_sub        t_num;
        v_valor_iva  t_num;
        v_es_json    NUMBER;
        v_max_lineas NUMBER;
        v_subtotal   NUMBER := 0;
        v_iva        NUMBER := 0;
        v_total      NUMBER;
        v_limite     NUMBER;
        v_saldo      NUMBER;
        v_activo     NUMBER;
        v_id_periodo NUMBER;
        v_fecha      DATE := SYSDATE;
        v_vence      DATE;
        v_estado     VARCHAR2(10);
        v_saldo_pend NUMBER;
        v_usuario    VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);

        -- 1. Validacion de parametros
        IF p_id_cliente IS NULL OR p_tipo_venta IS NULL OR p_tipo_venta NOT IN ('CONTADO', 'CREDITO')
           OR p_lineas_json IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Cliente, tipo de venta (CONTADO o CREDITO) y lineas son obligatorios.');
        END IF;
        SELECT CASE WHEN p_lineas_json IS JSON STRICT THEN 1 ELSE 0 END INTO v_es_json FROM dual;
        IF v_es_json = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Las lineas no son un JSON valido.');
        END IF;
        v_max_lineas := pkg_parametros.fn_numero('MAX_LINEAS_DOCUMENTO');

        -- 2. Lineas agrupadas por producto (un solo recorrido del JSON, variables de enlace)
        SELECT jt.id_producto,
               SUM(jt.cantidad),
               SUM(CASE WHEN jt.cantidad IS NULL OR jt.cantidad <= 0
                          OR jt.cantidad <> ROUND(jt.cantidad, 2) THEN 1 ELSE 0 END)
          BULK COLLECT INTO v_ids, v_cant, v_inval
          FROM JSON_TABLE(p_lineas_json, '$[*]'
                 COLUMNS (id_producto NUMBER PATH '$.id_producto',
                          cantidad    NUMBER PATH '$.cantidad')) jt
         GROUP BY jt.id_producto
         ORDER BY jt.id_producto;

        IF v_ids.COUNT = 0 OR v_ids.COUNT > v_max_lineas THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'La venta debe tener entre 1 y ' || v_max_lineas || ' productos.');
        END IF;
        FOR i IN 1 .. v_ids.COUNT LOOP
            IF v_ids(i) IS NULL OR v_inval(i) > 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                    'Cada linea requiere id_producto y una cantidad positiva con maximo 2 decimales.');
            END IF;
        END LOOP;

        -- 3. Bloqueo del cliente (punto de serializacion de la cartera)
        BEGIN
            SELECT limite_credito, saldo_deudor, activo
              INTO v_limite, v_saldo, v_activo
              FROM clientes
             WHERE id_cliente = p_id_cliente
               FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe.');
        END;
        IF v_activo = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'El cliente esta inactivo.');
        END IF;

        -- 4. Bloqueo ordenado de TODOS los productos en una sola consulta (evita N consultas y interbloqueos)
        -- CORRECCION (ORA-01786): FOR UPDATE no admite un JSON_TABLE en el
        -- subquery. Se reutiliza v_ids (ya validada, agrupada y ordenada)
        -- a traves de un tipo de coleccion SQL, que si admite bloqueo.
        v_lock_ids := sys.odcinumberlist();
        v_lock_ids.EXTEND(v_ids.COUNT);
        FOR i IN 1 .. v_ids.COUNT LOOP
            v_lock_ids(i) := v_ids(i);
        END LOOP;

        SELECT p.id_producto, p.precio_base, p.tarifa_iva, p.stock_actual, p.activo
          BULK COLLECT INTO v_p_id, v_p_precio, v_p_iva, v_p_stock, v_p_activo
          FROM productos p
         WHERE p.id_producto IN (SELECT column_value FROM TABLE(v_lock_ids))
         ORDER BY p.id_producto
           FOR UPDATE WAIT 10;

        IF v_p_id.COUNT <> v_ids.COUNT THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'Hay productos que no existen en el catalogo.');
        END IF;

        -- 5. Calculo en memoria (sin SQL dentro del bucle)
        FOR i IN 1 .. v_ids.COUNT LOOP
            IF v_p_id(i) <> v_ids(i) THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'Hay productos que no existen en el catalogo.');
            END IF;
            IF v_p_activo(i) = 0 THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                    'El producto ' || v_ids(i) || ' esta inactivo.');
            END IF;
            IF v_p_stock(i) < v_cant(i) THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_stock_insuficiente,
                    'Stock insuficiente del producto ' || v_ids(i) || ': disponible ' || v_p_stock(i) ||
                    ', solicitado ' || v_cant(i) || '.');
            END IF;
            v_sub(i)       := ROUND(v_cant(i) * v_p_precio(i), 2);
            v_valor_iva(i) := ROUND(v_sub(i) * v_p_iva(i) / 100, 2);
            v_subtotal     := v_subtotal + v_sub(i);
            v_iva          := v_iva + v_valor_iva(i);
        END LOOP;
        v_total := v_subtotal + v_iva;
        IF v_total <= 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El total de la venta debe ser mayor a cero.');
        END IF;

        -- 6. Periodo y credito
        v_id_periodo := pkg_periodos.fn_id_periodo(v_fecha);
        pkg_periodos.sp_validar_abierto(v_id_periodo, v_fecha);

        IF p_tipo_venta = 'CREDITO' THEN
            IF v_saldo + v_total > v_limite THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_limite_credito,
                    'La venta excede el cupo de credito: cupo ' || v_limite || ', deuda ' || v_saldo ||
                    ', venta ' || v_total || '.');
            END IF;
            v_vence      := TRUNC(v_fecha) + pkg_parametros.fn_numero('PLAZO_CREDITO_DIAS');
            v_estado     := 'PENDIENTE';
            v_saldo_pend := v_total;
        ELSE
            v_vence      := NULL;
            v_estado     := 'PAGADA';
            v_saldo_pend := 0;
        END IF;

        -- 7. Escritura por lotes
        INSERT INTO ventas (id_cliente, id_periodo, fecha_venta, tipo_venta, fecha_vencimiento,
                            subtotal_venta, total_iva, total_venta, saldo_pendiente, estado_pago, usuario_registro)
        VALUES (p_id_cliente, v_id_periodo, v_fecha, p_tipo_venta, v_vence,
                v_subtotal, v_iva, v_total, v_saldo_pend, v_estado, v_usuario)
        RETURNING id_venta INTO p_id_venta;

        FORALL i IN 1 .. v_ids.COUNT
            INSERT INTO ventas_detalle (id_venta, id_producto, cantidad, precio_unitario, tarifa_iva, subtotal, valor_iva)
            VALUES (p_id_venta, v_ids(i), v_cant(i), v_p_precio(i), v_p_iva(i), v_sub(i), v_valor_iva(i));

        FORALL i IN 1 .. v_ids.COUNT
            UPDATE productos SET stock_actual = stock_actual - v_cant(i) WHERE id_producto = v_ids(i);

        IF p_tipo_venta = 'CREDITO' THEN
            UPDATE clientes SET saldo_deudor = saldo_deudor + v_total WHERE id_cliente = p_id_cliente;
        END IF;

        p_total_venta := v_total;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_venta := NULL;
            p_total_venta := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_venta',
                                    'id_cliente=' || p_id_cliente || ';tipo=' || p_tipo_venta);
    END sp_registrar_venta;

    PROCEDURE sp_anular_venta(p_id_venta IN NUMBER, p_motivo IN VARCHAR2) IS
        v_ids        t_num;
        v_cant       t_num;
        v_bloq       t_num;
        v_id_cliente NUMBER;
        v_tipo       VARCHAR2(10);
        v_estado     VARCHAR2(10);
        v_saldo_pend NUMBER;
        v_id_periodo NUMBER;
        v_fecha      DATE;
        v_n          NUMBER;
        v_deuda      NUMBER;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_venta IS NULL OR p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 10 OR LENGTH(p_motivo) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Venta y motivo (10 a 255 caracteres) son obligatorios.');
        END IF;

        -- Orden de bloqueo: cliente -> venta -> productos
        BEGIN
            SELECT id_cliente INTO v_id_cliente FROM ventas WHERE id_venta = p_id_venta;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La venta no existe.');
        END;
        SELECT saldo_deudor INTO v_deuda FROM clientes WHERE id_cliente = v_id_cliente FOR UPDATE WAIT 10;
        SELECT tipo_venta, estado_pago, saldo_pendiente, id_periodo, fecha_venta
          INTO v_tipo, v_estado, v_saldo_pend, v_id_periodo, v_fecha
          FROM ventas WHERE id_venta = p_id_venta FOR UPDATE WAIT 10;

        IF v_estado NOT IN ('PAGADA', 'PENDIENTE') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'La venta ya esta ' || v_estado || '.');
        END IF;
        pkg_periodos.sp_validar_abierto(v_id_periodo);

        SELECT COUNT(*) INTO v_n FROM facturas
         WHERE id_venta = p_id_venta AND estado_dian IN ('EN_PROCESO', 'ACEPTADA');
        IF v_n > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'La venta tiene una factura enviada o aceptada por la DIAN: corrija con una nota credito.');
        END IF;
        SELECT COUNT(*) INTO v_n FROM abonos_cartera WHERE id_venta = p_id_venta;
        IF v_n > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida,
                'La venta tiene abonos registrados y no puede anularse.');
        END IF;

        -- Devolucion de stock por lotes
        SELECT id_producto, cantidad BULK COLLECT INTO v_ids, v_cant
          FROM ventas_detalle WHERE id_venta = p_id_venta ORDER BY id_producto;

        SELECT id_producto BULK COLLECT INTO v_bloq
          FROM productos
         WHERE id_producto IN (SELECT id_producto FROM ventas_detalle WHERE id_venta = p_id_venta)
         ORDER BY id_producto
           FOR UPDATE WAIT 10;

        FORALL i IN 1 .. v_ids.COUNT
            UPDATE productos SET stock_actual = stock_actual + v_cant(i) WHERE id_producto = v_ids(i);

        IF v_tipo = 'CREDITO' AND v_saldo_pend > 0 THEN
            UPDATE clientes SET saldo_deudor = saldo_deudor - v_saldo_pend WHERE id_cliente = v_id_cliente;
        END IF;

        UPDATE ventas
           SET estado_pago = 'ANULADA', saldo_pendiente = 0, motivo_anulacion = TRIM(p_motivo)
         WHERE id_venta = p_id_venta;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_anular_venta', 'id_venta=' || p_id_venta);
    END sp_anular_venta;

END pkg_ventas;
/

-- ============ pkg_facturacion ============

-- ============ pkg_facturacion ============
CREATE OR REPLACE PACKAGE pkg_facturacion AUTHID DEFINER AS
    -- Registra una resolucion de numeracion DIAN (solo ADMIN). consecutivo_actual queda en rango_desde - 1.
    PROCEDURE sp_registrar_resolucion(
        p_tipo_documento    IN  VARCHAR2,
        p_numero_resolucion IN  VARCHAR2,
        p_prefijo           IN  VARCHAR2,
        p_rango_desde       IN  NUMBER,
        p_rango_hasta       IN  NUMBER,
        p_vigente_desde     IN  DATE,
        p_vigente_hasta     IN  DATE,
        p_id_resolucion     OUT NUMBER
    );

    PROCEDURE sp_emitir_factura(
        p_id_venta       IN  NUMBER,
        p_id_factura     OUT NUMBER,
        p_numero_factura OUT VARCHAR2
    );

    -- p_tipo: FACTURA o NOTA_CREDITO. p_codigo_unico es el CUFE o el CUDE.
    PROCEDURE sp_registrar_respuesta_dian(
        p_tipo          IN VARCHAR2,
        p_id_documento  IN NUMBER,
        p_estado        IN VARCHAR2,
        p_codigo_unico  IN VARCHAR2,
        p_qr_url        IN VARCHAR2,
        p_xml           IN CLOB
    );

    -- Lineas: [{"id_producto":1,"cantidad":2,"reingresa_stock":1}, ...]
    PROCEDURE sp_emitir_nota_credito(
        p_id_factura     IN  NUMBER,
        p_motivo         IN  VARCHAR2,
        p_lineas_json    IN  CLOB,
        p_id_nota        OUT NUMBER,
        p_numero_nota    OUT VARCHAR2,
        p_monto_devuelto OUT NUMBER,
        p_monto_aplicado OUT NUMBER
    );
END pkg_facturacion;
/
CREATE OR REPLACE PACKAGE BODY pkg_facturacion AS

    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    -- Toma el siguiente consecutivo de la resolucion vigente, bloqueando su fila.
    PROCEDURE pr_tomar_consecutivo(
        p_tipo_documento IN  VARCHAR2,
        p_id_resolucion  OUT NUMBER,
        p_numero         OUT VARCHAR2
    ) IS
        CURSOR c_res IS
            SELECT id_resolucion, prefijo, consecutivo_actual + 1 AS siguiente
              FROM resoluciones_facturacion
             WHERE tipo_documento = p_tipo_documento
               AND activa = 1
               AND TRUNC(SYSDATE) BETWEEN vigente_desde AND vigente_hasta
               AND consecutivo_actual < rango_hasta
             ORDER BY vigente_hasta, id_resolucion
               FOR UPDATE OF consecutivo_actual WAIT 10;
        v_res c_res%ROWTYPE;
    BEGIN
        OPEN c_res;
        FETCH c_res INTO v_res;
        IF c_res%NOTFOUND THEN
            CLOSE c_res;
            RAISE_APPLICATION_ERROR(pkg_errores.c_facturacion,
                'No hay una resolucion de ' || p_tipo_documento || ' vigente con consecutivos disponibles.');
        END IF;
        CLOSE c_res;

        UPDATE resoluciones_facturacion
           SET consecutivo_actual = v_res.siguiente
         WHERE id_resolucion = v_res.id_resolucion;
        p_id_resolucion := v_res.id_resolucion;
        p_numero        := v_res.prefijo || v_res.siguiente;
    END pr_tomar_consecutivo;

    FUNCTION fn_transicion_valida(p_actual IN VARCHAR2, p_nuevo IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN (p_actual = 'NO_ENVIADA' AND p_nuevo = 'EN_PROCESO')
            OR (p_actual = 'EN_PROCESO' AND p_nuevo IN ('ACEPTADA', 'RECHAZADA'))
            OR (p_actual = 'RECHAZADA'  AND p_nuevo = 'EN_PROCESO');
    END fn_transicion_valida;

    PROCEDURE sp_registrar_resolucion(
        p_tipo_documento    IN  VARCHAR2,
        p_numero_resolucion IN  VARCHAR2,
        p_prefijo           IN  VARCHAR2,
        p_rango_desde       IN  NUMBER,
        p_rango_hasta       IN  NUMBER,
        p_vigente_desde     IN  DATE,
        p_vigente_hasta     IN  DATE,
        p_id_resolucion     OUT NUMBER
    ) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_tipo_documento IS NULL OR p_tipo_documento NOT IN ('FACTURA', 'NOTA_CREDITO')
           OR p_numero_resolucion IS NULL OR LENGTH(p_numero_resolucion) > 30
           OR p_prefijo IS NULL OR NOT REGEXP_LIKE(p_prefijo, '^[A-Za-z0-9]{1,10}$')
           OR p_rango_desde IS NULL OR p_rango_hasta IS NULL OR p_rango_desde < 1 OR p_rango_hasta < p_rango_desde
           OR p_rango_desde <> TRUNC(p_rango_desde) OR p_rango_hasta <> TRUNC(p_rango_hasta)
           OR p_vigente_desde IS NULL OR p_vigente_hasta IS NULL OR p_vigente_hasta < p_vigente_desde THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Datos de la resolucion invalidos.');
        END IF;
        INSERT INTO resoluciones_facturacion (tipo_documento, numero_resolucion, prefijo, rango_desde, rango_hasta,
                                              consecutivo_actual, vigente_desde, vigente_hasta)
        VALUES (p_tipo_documento, p_numero_resolucion, p_prefijo, p_rango_desde, p_rango_hasta,
                p_rango_desde - 1, TRUNC(p_vigente_desde), TRUNC(p_vigente_hasta))
        RETURNING id_resolucion INTO p_id_resolucion;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_resolucion := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_resolucion', 'resolucion=' || p_numero_resolucion);
    END sp_registrar_resolucion;

    PROCEDURE sp_emitir_factura(
        p_id_venta       IN  NUMBER,
        p_id_factura     OUT NUMBER,
        p_numero_factura OUT VARCHAR2
    ) IS
        v_estado        VARCHAR2(10);
        v_subtotal      NUMBER;
        v_iva           NUMBER;
        v_total         NUMBER;
        v_vence         DATE;
        v_n             NUMBER;
        v_id_resolucion NUMBER;
        v_usuario       VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_venta IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'La venta es obligatoria.');
        END IF;

        BEGIN
            SELECT estado_pago, subtotal_venta, total_iva, total_venta, fecha_vencimiento
              INTO v_estado, v_subtotal, v_iva, v_total, v_vence
              FROM ventas WHERE id_venta = p_id_venta FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La venta no existe.');
        END;
        IF v_estado IN ('ANULADA', 'CASTIGADA') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido, 'No se factura una venta ' || v_estado || '.');
        END IF;
        SELECT COUNT(*) INTO v_n FROM facturas WHERE id_venta = p_id_venta;
        IF v_n > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'La venta ya tiene factura.');
        END IF;

        pr_tomar_consecutivo('FACTURA', v_id_resolucion, p_numero_factura);

        INSERT INTO facturas (id_venta, id_resolucion, numero_factura, fecha_vencimiento,
                              subtotal_base, total_iva, total_factura, usuario_emisor)
        VALUES (p_id_venta, v_id_resolucion, p_numero_factura, v_vence,
                v_subtotal, v_iva, v_total, v_usuario)
        RETURNING id_factura INTO p_id_factura;

        INSERT INTO documentos_repositorio (tipo_entidad, id_entidad, nombre_archivo, usuario_carga)
        VALUES ('FACTURA', p_id_factura, p_numero_factura || '.pdf', v_usuario);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_factura := NULL;
            p_numero_factura := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_emitir_factura', 'id_venta=' || p_id_venta);
    END sp_emitir_factura;

    PROCEDURE sp_registrar_respuesta_dian(
        p_tipo          IN VARCHAR2,
        p_id_documento  IN NUMBER,
        p_estado        IN VARCHAR2,
        p_codigo_unico  IN VARCHAR2,
        p_qr_url        IN VARCHAR2,
        p_xml           IN CLOB
    ) IS
        v_actual VARCHAR2(12);
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_tipo IS NULL OR p_estado IS NULL OR p_id_documento IS NULL
           OR p_tipo NOT IN ('FACTURA', 'NOTA_CREDITO')
           OR p_estado NOT IN ('EN_PROCESO', 'ACEPTADA', 'RECHAZADA') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Tipo, documento o estado invalidos.');
        END IF;
        IF p_estado = 'ACEPTADA' AND p_codigo_unico IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Un documento ACEPTADA requiere CUFE/CUDE.');
        END IF;

        BEGIN
            IF p_tipo = 'FACTURA' THEN
                SELECT estado_dian INTO v_actual FROM facturas
                 WHERE id_factura = p_id_documento FOR UPDATE WAIT 10;
            ELSE
                SELECT estado_dian INTO v_actual FROM facturas_notas_credito
                 WHERE id_nota = p_id_documento FOR UPDATE WAIT 10;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El documento no existe.');
        END;
        IF NOT fn_transicion_valida(v_actual, p_estado) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'Transicion de estado DIAN no permitida: ' || v_actual || ' a ' || p_estado || '.');
        END IF;

        IF p_tipo = 'FACTURA' THEN
            UPDATE facturas
               SET estado_dian = p_estado,
                   cufe = NVL(p_codigo_unico, cufe),
                   qr_code_url = NVL(p_qr_url, qr_code_url),
                   xml_documento = NVL(p_xml, xml_documento)
             WHERE id_factura = p_id_documento;
        ELSE
            UPDATE facturas_notas_credito
               SET estado_dian = p_estado, cude = NVL(p_codigo_unico, cude)
             WHERE id_nota = p_id_documento;
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_respuesta_dian', p_tipo || ' id=' || p_id_documento);
    END sp_registrar_respuesta_dian;

    PROCEDURE sp_emitir_nota_credito(
        p_id_factura     IN  NUMBER,
        p_motivo         IN  VARCHAR2,
        p_lineas_json    IN  CLOB,
        p_id_nota        OUT NUMBER,
        p_numero_nota    OUT VARCHAR2,
        p_monto_devuelto OUT NUMBER,
        p_monto_aplicado OUT NUMBER
    ) IS
        v_ids     t_num;   -- lineas solicitadas
        v_cant    t_num;
        v_reing   t_num;
        v_d_id    t_num;   -- lo vendido en la factura
        v_d_precio t_num;
        v_d_iva   t_num;
        v_d_disp  t_num;   -- vendido menos ya devuelto
        v_valor   t_num;
        v_bloq    t_num;
        v_lock_ids sys.odcinumberlist;  -- CORRECCION: tipo SQL para TABLE()
        v_id_venta      NUMBER;
        v_id_cliente    NUMBER;
        v_tipo_venta    VARCHAR2(10);
        v_estado_pago   VARCHAR2(10);
        v_saldo_pend    NUMBER;
        v_estado_dian   VARCHAR2(12);
        v_deuda         NUMBER;
        v_es_json       NUMBER;
        v_max_lineas    NUMBER;
        v_id_resolucion NUMBER;
        v_base          NUMBER;
        v_monto         NUMBER := 0;
        v_aplicado      NUMBER := 0;
        v_usuario       VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_factura IS NULL OR p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 5 OR LENGTH(p_motivo) > 255
           OR p_lineas_json IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Factura, motivo (5 a 255 caracteres) y lineas son obligatorios.');
        END IF;
        SELECT CASE WHEN p_lineas_json IS JSON STRICT THEN 1 ELSE 0 END INTO v_es_json FROM dual;
        IF v_es_json = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Las lineas no son un JSON valido.');
        END IF;
        v_max_lineas := pkg_parametros.fn_numero('MAX_LINEAS_DOCUMENTO');

        -- Orden de bloqueo: cliente -> venta -> productos
        BEGIN
            SELECT f.id_venta, v.id_cliente INTO v_id_venta, v_id_cliente
              FROM facturas f JOIN ventas v ON v.id_venta = f.id_venta
             WHERE f.id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La factura no existe.');
        END;
        SELECT saldo_deudor INTO v_deuda FROM clientes WHERE id_cliente = v_id_cliente FOR UPDATE WAIT 10;
        SELECT v.tipo_venta, v.estado_pago, v.saldo_pendiente, f.estado_dian
          INTO v_tipo_venta, v_estado_pago, v_saldo_pend, v_estado_dian
          FROM ventas v JOIN facturas f ON f.id_venta = v.id_venta
         WHERE v.id_venta = v_id_venta
           FOR UPDATE OF v.saldo_pendiente WAIT 10;

        IF v_estado_dian <> 'ACEPTADA' THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'Solo se emiten notas credito sobre facturas ACEPTADA por la DIAN.');
        END IF;
        pkg_periodos.sp_validar_abierto(pkg_periodos.fn_id_periodo(SYSDATE), SYSDATE);

        -- Lineas solicitadas
        SELECT jt.id_producto, jt.cantidad, NVL(jt.reingresa_stock, 0)
          BULK COLLECT INTO v_ids, v_cant, v_reing
          FROM JSON_TABLE(p_lineas_json, '$[*]'
                 COLUMNS (id_producto     NUMBER PATH '$.id_producto',
                          cantidad        NUMBER PATH '$.cantidad',
                          reingresa_stock NUMBER PATH '$.reingresa_stock')) jt
         ORDER BY jt.id_producto;
        IF v_ids.COUNT = 0 OR v_ids.COUNT > v_max_lineas THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'La nota debe tener entre 1 y ' || v_max_lineas || ' productos.');
        END IF;
        FOR i IN 1 .. v_ids.COUNT LOOP
            IF v_ids(i) IS NULL OR v_cant(i) IS NULL OR v_cant(i) <= 0 OR v_cant(i) <> ROUND(v_cant(i), 2)
               OR v_reing(i) NOT IN (0, 1) THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                    'Cada linea requiere id_producto, cantidad positiva (max. 2 decimales) y reingresa_stock 0 o 1.');
            END IF;
            IF i > 1 AND v_ids(i) = v_ids(i - 1) THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                    'El producto ' || v_ids(i) || ' esta repetido en la nota.');
            END IF;
        END LOOP;

        -- Lo vendido menos lo ya devuelto, en una sola consulta
        SELECT d.id_producto, d.precio_unitario, d.tarifa_iva, d.cantidad - NVL(dev.cantidad, 0)
          BULK COLLECT INTO v_d_id, v_d_precio, v_d_iva, v_d_disp
          FROM ventas_detalle d
          LEFT JOIN (SELECT nd.id_producto, SUM(nd.cantidad) AS cantidad
                       FROM notas_credito_detalle nd
                       JOIN facturas_notas_credito n ON n.id_nota = nd.id_nota
                      WHERE n.id_factura = p_id_factura
                      GROUP BY nd.id_producto) dev ON dev.id_producto = d.id_producto
         WHERE d.id_venta = v_id_venta
           AND d.id_producto IN (SELECT jt.id_producto
                                   FROM JSON_TABLE(p_lineas_json, '$[*]'
                                          COLUMNS (id_producto NUMBER PATH '$.id_producto')) jt)
         ORDER BY d.id_producto;
        IF v_d_id.COUNT <> v_ids.COUNT THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Hay productos que no pertenecen a la venta facturada.');
        END IF;

        FOR i IN 1 .. v_ids.COUNT LOOP
            IF v_d_id(i) <> v_ids(i) THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                    'Hay productos que no pertenecen a la venta facturada.');
            END IF;
            IF v_cant(i) > v_d_disp(i) THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                    'El producto ' || v_ids(i) || ' excede lo vendido y no devuelto (' || v_d_disp(i) || ').');
            END IF;
            v_base     := ROUND(v_cant(i) * v_d_precio(i), 2);
            v_valor(i) := v_base + ROUND(v_base * v_d_iva(i) / 100, 2);
            v_monto    := v_monto + v_valor(i);
        END LOOP;

        IF v_tipo_venta = 'CREDITO' AND v_estado_pago = 'PENDIENTE' THEN
            v_aplicado := LEAST(v_monto, v_saldo_pend);
        END IF;

        -- CORRECCION (ORA-01786): FOR UPDATE no admite un JSON_TABLE en el
        -- subquery. Se reutiliza v_ids (ya validada, agrupada y ordenada)
        -- a traves de un tipo de coleccion SQL, que si admite bloqueo.
        v_lock_ids := sys.odcinumberlist();
        v_lock_ids.EXTEND(v_ids.COUNT);
        FOR i IN 1 .. v_ids.COUNT LOOP
            v_lock_ids(i) := v_ids(i);
        END LOOP;

        SELECT id_producto BULK COLLECT INTO v_bloq
          FROM productos
         WHERE id_producto IN (SELECT column_value FROM TABLE(v_lock_ids))
         ORDER BY id_producto
           FOR UPDATE WAIT 10;

        pr_tomar_consecutivo('NOTA_CREDITO', v_id_resolucion, p_numero_nota);

        INSERT INTO facturas_notas_credito (id_factura, id_resolucion, numero_nota, monto_devolucion,
                                            monto_aplicado_cartera, motivo, usuario_emisor)
        VALUES (p_id_factura, v_id_resolucion, p_numero_nota, v_monto, v_aplicado, TRIM(p_motivo), v_usuario)
        RETURNING id_nota INTO p_id_nota;

        FORALL i IN 1 .. v_ids.COUNT
            INSERT INTO notas_credito_detalle (id_nota, id_producto, cantidad, valor_linea, reingresa_stock)
            VALUES (p_id_nota, v_ids(i), v_cant(i), v_valor(i), v_reing(i));

        FORALL i IN 1 .. v_ids.COUNT
            UPDATE productos SET stock_actual = stock_actual + (v_cant(i) * v_reing(i))
             WHERE id_producto = v_ids(i);

        IF v_aplicado > 0 THEN
            UPDATE ventas
               SET saldo_pendiente = saldo_pendiente - v_aplicado,
                   estado_pago = CASE WHEN saldo_pendiente - v_aplicado = 0 THEN 'PAGADA' ELSE estado_pago END
             WHERE id_venta = v_id_venta;
            UPDATE clientes SET saldo_deudor = saldo_deudor - v_aplicado WHERE id_cliente = v_id_cliente;
        END IF;

        INSERT INTO documentos_repositorio (tipo_entidad, id_entidad, nombre_archivo, usuario_carga)
        VALUES ('NOTA_CREDITO', p_id_nota, p_numero_nota || '.pdf', v_usuario);

        p_monto_devuelto := v_monto;
        p_monto_aplicado := v_aplicado;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_nota := NULL;
            p_numero_nota := NULL;
            p_monto_devuelto := NULL;
            p_monto_aplicado := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_emitir_nota_credito', 'id_factura=' || p_id_factura);
    END sp_emitir_nota_credito;

END pkg_facturacion;
/

-- ============ pkg_cartera ============

-- ============ pkg_cartera ============
CREATE OR REPLACE PACKAGE pkg_cartera AUTHID DEFINER AS
    PROCEDURE sp_registrar_abono(
        p_id_cliente     IN  NUMBER,
        p_monto          IN  NUMBER,
        p_metodo_pago    IN  VARCHAR2,
        p_referencia     IN  VARCHAR2,
        p_id_recibo      OUT NUMBER,
        p_saldo_restante OUT NUMBER
    );

    PROCEDURE sp_castigar_cartera(
        p_id_cliente     IN  NUMBER,
        p_motivo         IN  VARCHAR2,
        p_monto_castigado OUT NUMBER
    );
END pkg_cartera;
/
CREATE OR REPLACE PACKAGE BODY pkg_cartera AS

    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    PROCEDURE sp_registrar_abono(
        p_id_cliente     IN  NUMBER,
        p_monto          IN  NUMBER,
        p_metodo_pago    IN  VARCHAR2,
        p_referencia     IN  VARCHAR2,
        p_id_recibo      OUT NUMBER,
        p_saldo_restante OUT NUMBER
    ) IS
        v_id_venta  t_num;   -- ventas pendientes, mas antiguas primero
        v_saldo     t_num;
        v_ap_venta  t_num;   -- reparto del abono
        v_ap_monto  t_num;
        v_deuda     NUMBER;
        v_restante  NUMBER;
        v_n         PLS_INTEGER := 0;
        v_usuario   VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_cliente IS NULL OR p_monto IS NULL OR p_monto <= 0 OR p_monto <> ROUND(p_monto, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_abono_invalido,
                'El abono debe ser mayor a cero y tener maximo 2 decimales.');
        END IF;
        IF p_metodo_pago IS NULL OR p_metodo_pago NOT IN ('EFECTIVO', 'TRANSFERENCIA', 'TARJETA', 'CHEQUE', 'OTRO') THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Metodo de pago invalido.');
        END IF;

        BEGIN
            SELECT saldo_deudor INTO v_deuda FROM clientes WHERE id_cliente = p_id_cliente FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe.');
        END;
        IF p_monto > v_deuda THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_abono_invalido,
                'El abono (' || p_monto || ') excede la deuda del cliente (' || v_deuda || ').');
        END IF;

        -- Una sola lectura, con bloqueo, de todas las ventas pendientes (FIFO)
        SELECT v.id_venta, v.saldo_pendiente
          BULK COLLECT INTO v_id_venta, v_saldo
          FROM ventas v
         WHERE v.id_cliente = p_id_cliente AND v.estado_pago = 'PENDIENTE'
         ORDER BY v.fecha_venta, v.id_venta
           FOR UPDATE WAIT 10;

        -- Reparto en memoria
        v_restante := p_monto;
        FOR i IN 1 .. v_id_venta.COUNT LOOP
            EXIT WHEN v_restante <= 0;
            v_n := v_n + 1;
            v_ap_venta(v_n) := v_id_venta(i);
            v_ap_monto(v_n) := LEAST(v_restante, v_saldo(i));
            v_restante      := v_restante - v_ap_monto(v_n);
        END LOOP;
        IF v_restante > 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'Inconsistencia: la deuda del cliente no coincide con sus ventas pendientes. Avise a soporte.');
        END IF;

        p_id_recibo := seq_recibo_caja.NEXTVAL;

        FORALL i IN 1 .. v_n
            INSERT INTO abonos_cartera (id_recibo, id_venta, fecha_abono, monto, metodo_pago, referencia_pago, usuario_registro)
            VALUES (p_id_recibo, v_ap_venta(i), SYSDATE, v_ap_monto(i), p_metodo_pago, p_referencia, v_usuario);

        FORALL i IN 1 .. v_n
            UPDATE ventas
               SET saldo_pendiente = saldo_pendiente - v_ap_monto(i),
                   estado_pago = CASE WHEN saldo_pendiente - v_ap_monto(i) = 0 THEN 'PAGADA' ELSE 'PENDIENTE' END
             WHERE id_venta = v_ap_venta(i);

        UPDATE clientes SET saldo_deudor = saldo_deudor - p_monto WHERE id_cliente = p_id_cliente;
        p_saldo_restante := v_deuda - p_monto;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_recibo := NULL;
            p_saldo_restante := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_abono', 'id_cliente=' || p_id_cliente || ';monto=' || p_monto);
    END sp_registrar_abono;

    PROCEDURE sp_castigar_cartera(
        p_id_cliente      IN  NUMBER,
        p_motivo          IN  VARCHAR2,
        p_monto_castigado OUT NUMBER
    ) IS
        v_montos t_num;
        v_deuda  NUMBER;
        v_total  NUMBER := 0;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_id_cliente IS NULL OR p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 10 OR LENGTH(p_motivo) > 255 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Cliente y motivo (10 a 255 caracteres) son obligatorios.');
        END IF;

        BEGIN
            SELECT saldo_deudor INTO v_deuda FROM clientes WHERE id_cliente = p_id_cliente FOR UPDATE WAIT 10;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'El cliente no existe.');
        END;

        UPDATE ventas
           SET monto_castigado = saldo_pendiente, saldo_pendiente = 0, estado_pago = 'CASTIGADA'
         WHERE id_cliente = p_id_cliente AND estado_pago = 'PENDIENTE'
        RETURNING monto_castigado BULK COLLECT INTO v_montos;

        FOR i IN 1 .. v_montos.COUNT LOOP
            v_total := v_total + v_montos(i);
        END LOOP;
        IF v_total = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'El cliente no tiene cartera pendiente.');
        END IF;

        UPDATE clientes SET saldo_deudor = saldo_deudor - v_total WHERE id_cliente = p_id_cliente;
        pkg_auditoria.sp_registrar('CLIENTES', TO_CHAR(p_id_cliente), 'CASTIGO_CARTERA',
                                   TO_CHAR(v_total), SUBSTR(TRIM(p_motivo), 1, 400));
        p_monto_castigado := v_total;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_monto_castigado := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_castigar_cartera', 'id_cliente=' || p_id_cliente);
    END sp_castigar_cartera;

END pkg_cartera;
/

-- ============ pkg_finanzas y pkg_documentos ============

-- ============ pkg_finanzas ============
CREATE OR REPLACE PACKAGE pkg_finanzas AUTHID DEFINER AS
    PROCEDURE sp_crear_categoria_gasto(p_nombre IN VARCHAR2, p_id_categoria OUT NUMBER);
    PROCEDURE sp_registrar_gasto(
        p_id_categoria IN  NUMBER,
        p_concepto     IN  VARCHAR2,
        p_monto        IN  NUMBER,
        p_fecha_gasto  IN  DATE,
        p_id_gasto     OUT NUMBER
    );
END pkg_finanzas;
/
CREATE OR REPLACE PACKAGE BODY pkg_finanzas AS

    PROCEDURE sp_crear_categoria_gasto(p_nombre IN VARCHAR2, p_id_categoria OUT NUMBER) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_admin);
        IF p_nombre IS NULL OR LENGTH(TRIM(p_nombre)) < 3 OR LENGTH(p_nombre) > 80 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Nombre de categoria invalido (3 a 80 caracteres).');
        END IF;
        INSERT INTO categorias_gasto (nombre) VALUES (UPPER(TRIM(p_nombre)))
        RETURNING id_categoria INTO p_id_categoria;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_categoria := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_crear_categoria_gasto', 'nombre=' || p_nombre);
    END sp_crear_categoria_gasto;

    PROCEDURE sp_registrar_gasto(
        p_id_categoria IN  NUMBER,
        p_concepto     IN  VARCHAR2,
        p_monto        IN  NUMBER,
        p_fecha_gasto  IN  DATE,
        p_id_gasto     OUT NUMBER
    ) IS
        v_fecha   DATE := TRUNC(NVL(p_fecha_gasto, SYSDATE));
        v_activa  NUMBER;
        v_periodo NUMBER;
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_categoria IS NULL OR p_concepto IS NULL OR LENGTH(TRIM(p_concepto)) < 3 OR LENGTH(p_concepto) > 255
           OR p_monto IS NULL OR p_monto <= 0 OR p_monto <> ROUND(p_monto, 2) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido,
                'Categoria, concepto (3 a 255 caracteres) y monto positivo son obligatorios.');
        END IF;
        BEGIN
            SELECT activo INTO v_activa FROM categorias_gasto WHERE id_categoria = p_id_categoria;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(pkg_errores.c_entidad_no_existe, 'La categoria no existe.');
        END;
        IF v_activa = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_operacion_no_permitida, 'La categoria esta inactiva.');
        END IF;

        v_periodo := pkg_periodos.fn_id_periodo(v_fecha);
        pkg_periodos.sp_validar_abierto(v_periodo, v_fecha);

        INSERT INTO gastos_operativos (id_periodo, id_categoria, fecha_gasto, concepto, monto, usuario_registro)
        VALUES (v_periodo, p_id_categoria, v_fecha, TRIM(p_concepto), p_monto, v_usuario)
        RETURNING id_gasto INTO p_id_gasto;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_gasto := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_gasto', 'id_categoria=' || p_id_categoria);
    END sp_registrar_gasto;

END pkg_finanzas;
/

-- ============ pkg_documentos ============
CREATE OR REPLACE PACKAGE pkg_documentos AUTHID DEFINER AS
    PROCEDURE sp_registrar_pendiente(
        p_tipo_entidad  IN  VARCHAR2,
        p_id_entidad    IN  NUMBER,
        p_nombre        IN  VARCHAR2,
        p_mime_type     IN  VARCHAR2,
        p_id_documento  OUT NUMBER
    );
    PROCEDURE sp_marcar_subido(
        p_id_documento  IN NUMBER,
        p_drive_file_id IN VARCHAR2,
        p_drive_url     IN VARCHAR2,
        p_checksum      IN VARCHAR2
    );
    PROCEDURE sp_marcar_error(p_id_documento IN NUMBER, p_mensaje IN VARCHAR2);
END pkg_documentos;
/
CREATE OR REPLACE PACKAGE BODY pkg_documentos AS

    PROCEDURE sp_registrar_pendiente(
        p_tipo_entidad  IN  VARCHAR2,
        p_id_entidad    IN  NUMBER,
        p_nombre        IN  VARCHAR2,
        p_mime_type     IN  VARCHAR2,
        p_id_documento  OUT NUMBER
    ) IS
        v_usuario VARCHAR2(100) := pkg_seguridad.fn_usuario_actual;
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_tipo_entidad IS NULL OR p_tipo_entidad NOT IN ('FACTURA', 'NOTA_CREDITO', 'RECEPCION_LECHE')
           OR p_id_entidad IS NULL OR p_nombre IS NULL OR LENGTH(TRIM(p_nombre)) < 3 OR LENGTH(p_nombre) > 255
           OR p_mime_type IS NULL OR LENGTH(p_mime_type) > 100 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Datos del documento invalidos.');
        END IF;
        -- El trigger trg_documentos_valida_entidad comprueba que la entidad exista.
        INSERT INTO documentos_repositorio (tipo_entidad, id_entidad, nombre_archivo, mime_type, usuario_carga)
        VALUES (p_tipo_entidad, p_id_entidad, TRIM(p_nombre), p_mime_type, v_usuario)
        RETURNING id_documento INTO p_id_documento;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_id_documento := NULL;
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_registrar_pendiente', p_tipo_entidad || ' id=' || p_id_entidad);
    END sp_registrar_pendiente;

    PROCEDURE sp_marcar_subido(
        p_id_documento  IN NUMBER,
        p_drive_file_id IN VARCHAR2,
        p_drive_url     IN VARCHAR2,
        p_checksum      IN VARCHAR2
    ) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_documento IS NULL OR p_drive_file_id IS NULL OR LENGTH(p_drive_file_id) > 150
           OR (p_checksum IS NOT NULL AND NOT REGEXP_LIKE(p_checksum, '^[A-Fa-f0-9]{64}$')) THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'Datos de la carga invalidos.');
        END IF;
        UPDATE documentos_repositorio
           SET estado_carga = 'SUBIDO', drive_file_id = p_drive_file_id, drive_url = p_drive_url,
               checksum_sha256 = LOWER(p_checksum), ultimo_error = NULL, fecha_carga = SYSTIMESTAMP,
               intentos = intentos + 1
         WHERE id_documento = p_id_documento AND estado_carga IN ('PENDIENTE', 'ERROR');
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'El documento no existe o ya fue marcado como subido.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_marcar_subido', 'id_documento=' || p_id_documento);
    END sp_marcar_subido;

    PROCEDURE sp_marcar_error(p_id_documento IN NUMBER, p_mensaje IN VARCHAR2) IS
    BEGIN
        pkg_seguridad.sp_exigir_rol(pkg_seguridad.c_rol_operativo);
        IF p_id_documento IS NULL THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_parametro_invalido, 'El documento es obligatorio.');
        END IF;
        UPDATE documentos_repositorio
           SET estado_carga = 'ERROR', ultimo_error = SUBSTR(p_mensaje, 1, 500), intentos = intentos + 1
         WHERE id_documento = p_id_documento AND estado_carga IN ('PENDIENTE', 'ERROR');
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(pkg_errores.c_estado_invalido,
                'El documento no existe o ya fue marcado como subido.');
        END IF;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_errores.sp_propagar($$PLSQL_UNIT || '.sp_marcar_error', 'id_documento=' || p_id_documento);
    END sp_marcar_error;

END pkg_documentos;
/

-- ============ Parte J - Permisos (privilegio mínimo) ============

-- ============ Rol de la aplicación (__ROL_APP__) ============
GRANT EXECUTE ON pkg_seguridad    TO __ROL_APP__;
GRANT EXECUTE ON pkg_periodos     TO __ROL_APP__;
GRANT EXECUTE ON pkg_catalogos    TO __ROL_APP__;
GRANT EXECUTE ON pkg_acopio       TO __ROL_APP__;
GRANT EXECUTE ON pkg_produccion   TO __ROL_APP__;
GRANT EXECUTE ON pkg_ventas       TO __ROL_APP__;
GRANT EXECUTE ON pkg_facturacion  TO __ROL_APP__;
GRANT EXECUTE ON pkg_cartera      TO __ROL_APP__;
GRANT EXECUTE ON pkg_finanzas     TO __ROL_APP__;
GRANT EXECUTE ON pkg_documentos   TO __ROL_APP__;

GRANT SELECT ON vw_estado_periodos             TO __ROL_APP__;
GRANT SELECT ON vw_inventario_valorizado       TO __ROL_APP__;
GRANT SELECT ON vw_alertas_caducidad           TO __ROL_APP__;
GRANT SELECT ON vw_trazabilidad_produccion     TO __ROL_APP__;
GRANT SELECT ON vw_dashboard_cartera           TO __ROL_APP__;
GRANT SELECT ON vw_ventas_consolidadas         TO __ROL_APP__;
GRANT SELECT ON vw_detalle_ticket_venta        TO __ROL_APP__;
GRANT SELECT ON vw_gastos_por_categoria        TO __ROL_APP__;
GRANT SELECT ON vw_resumen_pago_lecheros       TO __ROL_APP__;
GRANT SELECT ON vw_calidad_leche_proveedor     TO __ROL_APP__;
GRANT SELECT ON vw_resultado_periodo           TO __ROL_APP__;
GRANT SELECT ON vw_documentos_pendientes_carga TO __ROL_APP__;
GRANT SELECT ON vw_clientes                    TO __ROL_APP__;
GRANT SELECT ON vw_proveedores                 TO __ROL_APP__;
GRANT SELECT ON vw_productos                   TO __ROL_APP__;
GRANT SELECT ON vw_facturas                    TO __ROL_APP__;
GRANT SELECT ON vw_abonos_cartera              TO __ROL_APP__;
GRANT SELECT ON vw_categorias_gasto            TO __ROL_APP__;
GRANT SELECT ON vw_resoluciones_facturacion    TO __ROL_APP__;

-- ============ Rol de lectura para reportes (__ROL_LECTURA__) ============
GRANT SELECT ON vw_estado_periodos             TO __ROL_LECTURA__;
GRANT SELECT ON vw_inventario_valorizado       TO __ROL_LECTURA__;
GRANT SELECT ON vw_alertas_caducidad           TO __ROL_LECTURA__;
GRANT SELECT ON vw_trazabilidad_produccion     TO __ROL_LECTURA__;
GRANT SELECT ON vw_gastos_por_categoria        TO __ROL_LECTURA__;
GRANT SELECT ON vw_resumen_pago_lecheros       TO __ROL_LECTURA__;
GRANT SELECT ON vw_calidad_leche_proveedor     TO __ROL_LECTURA__;
GRANT SELECT ON vw_resultado_periodo           TO __ROL_LECTURA__;

-- ============ Rol de auditoría (__ROL_AUDITORIA__) ============
GRANT SELECT ON vw_auditoria_cambios TO __ROL_AUDITORIA__;
GRANT SELECT ON vw_log_errores       TO __ROL_AUDITORIA__;

-- ============ Parte K - Verificación del despliegue ============

-- ============ Objetos inválidos, errores de compilación y claves foráneas sin índice ============
SELECT object_type, object_name, status
  FROM user_objects
 WHERE status <> 'VALID'
 ORDER BY object_type, object_name;

SELECT name, type, line, position, text
  FROM user_errors
 ORDER BY name, type, sequence;

SELECT cc.table_name, cc.constraint_name, cc.column_name
  FROM user_constraints c
  JOIN user_cons_columns cc ON cc.constraint_name = c.constraint_name
 WHERE c.constraint_type = 'R'
   AND NOT EXISTS (SELECT 1
                     FROM user_ind_columns ic
                    WHERE ic.table_name = cc.table_name
                      AND ic.column_name = cc.column_name
                      AND ic.column_position = 1);
