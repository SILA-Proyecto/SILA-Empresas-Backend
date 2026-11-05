-- 25_datos_prueba.sql
-- Datos ficticios para pruebas y simulacion (solo base LOCAL; NO correr en el servidor). Requiere 26_materias_primas.sql.
-- Ejecutar con:  docker exec -i -e NLS_LANG=.AL32UTF8 oracle-xe sqlplus ... < 25_datos_prueba.sql
-- 10 clientes, 10 proveedores (5 de leche + 5 de otras materias primas, algunos surten VARIAS), 10 productos con
-- receta (la leche incluida), 10 materias primas (la LECHE ya existe), precios pactados por proveedor y por cliente,
-- y compras iniciales: a credito, de contado, sin proveedor y una entrega de leche rechazada.
-- Los documentos llevan el prefijo PRUEBA- para reconocerlos y limpiarlos luego (se borran por ese prefijo).
set serveroutput on size unlimited
set define off
ALTER SESSION SET CURRENT_SCHEMA = __ESQUEMA__;
declare
  type t_ids is table of number index by pls_integer;
  cli t_ids; prov t_ids; prod t_ids; ins t_ids;
  v_id number; v_json clob; v_est varchar2(10);
  v_hoy date := trunc(cast(systimestamp at time zone 'America/Bogota' as date));
begin
  pkg_seguridad.sp_iniciar_sesion('carga.pruebas', 'ADMIN');

  -- Clientes (doc, nombre, email, telefono, direccion, limite de credito)
  for r in (
    select 1 n,'CC' t,'PRUEBA-C01' d,'Tienda Doña Luz' nom,'donaluz@ejemplo.com' em,'+57 300 111 0001' tel,'Cra 5 # 10-20, Villavicencio' dir,1500000 lim from dual union all
    select 2,'NIT','PRUEBA-C02','Supermercado El Llanito','compras@elllanito.com','+57 300 111 0002','Av 40 # 25-10, Villavicencio',5000000 from dual union all
    select 3,'NIT','PRUEBA-C03','Restaurante Sabor Llanero','admin@saborllanero.com','+57 300 111 0003','Calle 15 # 30-45, Villavicencio',2000000 from dual union all
    select 4,'CC','PRUEBA-C04','Panadería La Espiga','laespiga@ejemplo.com','+57 300 111 0004','Cra 22 # 8-12, Acacías',800000 from dual union all
    select 5,'NIT','PRUEBA-C05','Hotel Altillanura','compras@altillanura.com','+57 300 111 0005','Km 3 vía Puerto López',4000000 from dual union all
    select 6,'CC','PRUEBA-C06','Miscelánea Los Pinos','lospinos@ejemplo.com','+57 300 111 0006','Calle 9 # 14-33, Granada',500000 from dual union all
    select 7,'NIT','PRUEBA-C07','Distribuidora Orinoquia','pedidos@orinoquia.com','+57 300 111 0007','Zona Industrial, Villavicencio',10000000 from dual union all
    select 8,'CC','PRUEBA-C08','Carnicería y Víveres El Cebú','elcebu@ejemplo.com','+57 300 111 0008','Cra 31 # 19-05, Restrepo',1000000 from dual union all
    select 9,'NIT','PRUEBA-C09','Cafetería Universitaria Unillanos','cafeteria@unillanos.edu.co','+57 300 111 0009','Campus Barcelona, Villavicencio',3000000 from dual union all
    select 10,'CC','PRUEBA-C10','Almacén Mi Pueblo','mipueblo@ejemplo.com','+57 300 111 0010','Calle 12 # 6-18, Cumaral',600000 from dual
  ) loop
    pkg_catalogos.sp_crear_cliente(r.t, r.d, r.nom, r.em, r.tel, r.dir, r.lim, v_id);
    cli(r.n) := v_id;
  end loop;

  -- Proveedores (1-5 entregan leche; 6-10 surten otras materias primas, varios surten mas de una)
  for r in (
    select 1 n,'NIT' t,'PRUEBA-P01' d,'Hacienda La Alquería Ganadera' nom,'+57 310 555 0101' tel from dual union all
    select 2,'NIT','PRUEBA-P02','Finca Lechera El Mirador','+57 315 333 0303' from dual union all
    select 3,'NIT','PRUEBA-P03','Cooperativa Lechera Los Andes','+57 318 111 0505' from dual union all
    select 4,'NIT','PRUEBA-P04','Ganadería San Jerónimo','+57 314 888 0707' from dual union all
    select 5,'NIT','PRUEBA-P05','Agropecuaria Santa Clara','+57 317 666 0909' from dual union all
    select 6,'NIT','PRUEBA-P06','Cultivos y Fermentos Biológicos S.A.','+57 312 444 0202' from dual union all
    select 7,'NIT','PRUEBA-P07','Distribuidora de Cuajos y Enzimas del Valle','+57 320 222 0404' from dual union all
    select 8,'NIT','PRUEBA-P08','Empaques y Envases Lácteos','+57 311 999 0606' from dual union all
    select 9,'NIT','PRUEBA-P09','Aditivos y Sabores ProLácteos','+57 316 777 0808' from dual union all
    select 10,'NIT','PRUEBA-P10','Soluciones Sanitarias y Filtros','+57 313 555 1010' from dual
  ) loop
    pkg_catalogos.sp_crear_proveedor(r.t, r.d, r.nom, r.tel, v_id);
    prov(r.n) := v_id;
  end loop;

  -- Productos (sku, nombre, unidad, precio base, IVA %)
  for r in (
    select 1 n,'QSO-CAMPESINO-500' sku,'Queso campesino 500 g' nom,'UND' u,14000 p,0 iva from dual union all
    select 2,'QSO-DOBLECREMA-KG','Queso doble crema','KG',28000,0 from dual union all
    select 3,'QSO-MOZZARELLA-KG','Queso mozzarella','KG',32000,0 from dual union all
    select 4,'CUAJADA-KG','Cuajada fresca','KG',16000,0 from dual union all
    select 5,'MANTEQUILLA-250','Mantequilla 250 g','UND',9500,0 from dual union all
    select 6,'YOGURT-1L','Yogurt natural 1 L','UND',7500,0 from dual union all
    select 7,'KUMIS-1L','Kumis 1 L','UND',7000,0 from dual union all
    select 8,'LECHE-PAST-1L','Leche pasteurizada 1 L','UND',4200,0 from dual union all
    select 9,'AREQUIPE-500','Arequipe 500 g','UND',11000,19 from dual union all
    select 10,'SUERO-COSTENO-500','Suero costeño 500 g','UND',6500,0 from dual
  ) loop
    pkg_catalogos.sp_crear_producto(r.sku, r.nom, r.u, r.p, r.iva, v_id);
    prod(r.n) := v_id;
  end loop;

  -- Materias primas: la LECHE (1) ya existe; se crean las otras 9
  select id_insumo into ins(1) from insumos where codigo = 'LECHE';
  for r in (
    select 2 n,'CUAJO-LIQ' c,'Cuajo líquido' nom,'LT' u,5 sm from dual union all
    select 3,'FERMENTO-LACTICO','Fermento láctico','GR',500 from dual union all
    select 4,'SAL-INDUSTRIAL','Sal industrial','KG',50 from dual union all
    select 5,'CLORURO-CALCIO','Cloruro de calcio','LT',3 from dual union all
    select 6,'EMPAQUE-VACIO-500','Bolsa al vacío 500 g','UND',500 from dual union all
    select 7,'BOTELLA-1L','Botella plástica 1 L','UND',300 from dual union all
    select 8,'AZUCAR','Azúcar','KG',40 from dual union all
    select 9,'SABORIZANTE-VAINILL','Saborizante de vainilla','LT',2 from dual union all
    select 10,'CAJA-CARTON','Caja de cartón corrugado','UND',100 from dual union all
    select 11,'DETERGENTE-SANIT','Detergente sanitizante','LT',10 from dual
  ) loop
    pkg_insumos.sp_crear_insumo(r.c, r.nom, r.u, r.sm, v_id);
    ins(r.n) := v_id;
  end loop;

  -- Recetas: cantidad por UNIDAD de producto. %1 = leche (litros), %2 cuajo, %3 fermento, %4 sal, %5 cloruro,
  -- %6 bolsa, %7 botella, %8 azucar, %9 saborizante, %10 caja
  for r in (
    select 1 n, '[{"id_insumo":%1,"cantidad":5},{"id_insumo":%2,"cantidad":0.004},{"id_insumo":%3,"cantidad":0.5},{"id_insumo":%4,"cantidad":0.02},{"id_insumo":%6,"cantidad":1}]' j from dual union all
    select 2, '[{"id_insumo":%1,"cantidad":9},{"id_insumo":%2,"cantidad":0.005},{"id_insumo":%3,"cantidad":0.6},{"id_insumo":%4,"cantidad":0.03},{"id_insumo":%5,"cantidad":0.002},{"id_insumo":%10,"cantidad":0.05}]' from dual union all
    select 3, '[{"id_insumo":%1,"cantidad":10},{"id_insumo":%2,"cantidad":0.006},{"id_insumo":%3,"cantidad":0.8},{"id_insumo":%4,"cantidad":0.03},{"id_insumo":%5,"cantidad":0.003}]' from dual union all
    select 4, '[{"id_insumo":%1,"cantidad":6},{"id_insumo":%2,"cantidad":0.003},{"id_insumo":%4,"cantidad":0.015}]' from dual union all
    select 5, '[{"id_insumo":%1,"cantidad":5},{"id_insumo":%4,"cantidad":0.005},{"id_insumo":%6,"cantidad":1}]' from dual union all
    select 6, '[{"id_insumo":%1,"cantidad":1.05},{"id_insumo":%3,"cantidad":2},{"id_insumo":%7,"cantidad":1},{"id_insumo":%8,"cantidad":0.05}]' from dual union all
    select 7, '[{"id_insumo":%1,"cantidad":1.05},{"id_insumo":%3,"cantidad":2},{"id_insumo":%7,"cantidad":1},{"id_insumo":%8,"cantidad":0.04}]' from dual union all
    select 8, '[{"id_insumo":%1,"cantidad":1.02},{"id_insumo":%7,"cantidad":1}]' from dual union all
    select 9, '[{"id_insumo":%1,"cantidad":2.5},{"id_insumo":%8,"cantidad":0.25},{"id_insumo":%9,"cantidad":0.005},{"id_insumo":%6,"cantidad":1}]' from dual union all
    select 10, '[{"id_insumo":%1,"cantidad":3},{"id_insumo":%4,"cantidad":0.01},{"id_insumo":%6,"cantidad":1}]' from dual
  ) loop
    v_json := r.j;
    for k in reverse 1..10 loop
      v_json := replace(v_json, '%' || k, to_char(ins(k)));
    end loop;
    pkg_insumos.sp_definir_receta(prod(r.n), v_json);
  end loop;

  -- Precios pactados por proveedor y materia prima (referencia; la compra puede traer su propio valor).
  -- Fermento lo surten DOS proveedores a precios distintos; botellas y bolsas, un mismo proveedor.
  for r in (
    select 1 p, 1 i, 1750 pr from dual union all select 2, 1, 1800 from dual union all select 3, 1, 1850 from dual union all
    select 4, 1, 1900 from dual union all select 5, 1, 1950 from dual union all
    select 6, 3, 150 from dual union all select 7, 3, 170 from dual union all
    select 7, 2, 38000 from dual union all select 7, 5, 8500 from dual union all
    select 8, 6, 150 from dual union all select 8, 7, 350 from dual union all select 8, 10, 1300 from dual union all
    select 9, 8, 3800 from dual union all select 9, 9, 22000 from dual union all
    select 10, 11, 9000 from dual union all select 10, 4, 800 from dual
  ) loop
    pkg_pagos_proveedor.sp_fijar_precio(prov(r.p), ins(r.i), r.pr, v_hoy - 30);
  end loop;

  -- Precios especiales por cliente
  for r in (
    select 1 c, 1 p, 13000 pr from dual union all select 1, 2, 26500 from dual union all
    select 2, 1, 12500 from dual union all select 2, 3, 30500 from dual union all select 2, 8, 3900 from dual union all
    select 3, 2, 27000 from dual union all select 3, 4, 15000 from dual union all
    select 5, 6, 7000 from dual union all select 5, 7, 6500 from dual union all
    select 7, 1, 12000 from dual union all select 7, 5, 8800 from dual union all select 9, 6, 6900 from dual
  ) loop
    pkg_precios.sp_fijar_precio(cli(r.c), prod(r.p), r.pr, v_id);
  end loop;

  -- Compras iniciales. LECHE (OPERATIVO la registra en el dia a dia; aqui entra con el precio pactado): 3 entregas a
  -- credito de tres proveedores (promedio ponderado) y una RECHAZADA por temperatura (vale 0, no entra al stock).
  pkg_insumos.sp_registrar_compra(ins(1), prov(1), 1000, null, 'PRUEBA-LECHE-1', v_hoy, null, null, 6, 15, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(1), prov(2),  600, null, 'PRUEBA-LECHE-2', v_hoy, null, null, 7, 16, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(1), prov(3),  800, null, 'PRUEBA-LECHE-3', v_hoy, null, null, 5, 14, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(1), prov(4),  300, null, 'PRUEBA-LECHE-4', v_hoy, null, null, 15, 15, v_id, v_est);

  -- Otras materias primas: a credito con el precio pactado (valor null), a credito con valor digitado, de contado y
  -- sin proveedor registrado (comprado en un almacen).
  pkg_insumos.sp_registrar_compra(ins(2),  prov(7),   20, null,   'PRUEBA-CUAJO-1',  v_hoy, null, null, null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(3),  prov(6), 1500, 180000, 'PRUEBA-FERM-1',   v_hoy, null, null, null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(3),  prov(7),  800, null,   'PRUEBA-FERM-2',   v_hoy, null, null, null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(4),  prov(10), 200, null,   'PRUEBA-SAL-1',    v_hoy, null, null, null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(5),  prov(7),   10, null,   'PRUEBA-CACL-1',   v_hoy, null, null, null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(6),  prov(8), 3000, null,   'PRUEBA-BOLSA-1',  v_hoy, null, null, null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(7),  prov(8), 2000, null,   'PRUEBA-BOT-1',    v_hoy, null, null, null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(8),  prov(9),  100, null,   'PRUEBA-AZ-1',     v_hoy, null, null, null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(8),  null,      50, 215000, 'PRUEBA-AZ-2',     v_hoy, 1, 'Supermercado Metro', null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(9),  prov(9),    6, null,   'PRUEBA-VAIN-1',   v_hoy, null, null, null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(10), prov(8),  400, null,   'PRUEBA-CAJA-1',   v_hoy, 1, null, null, null, v_id, v_est);
  pkg_insumos.sp_registrar_compra(ins(11), prov(10),  40, null,   'PRUEBA-DET-1',    v_hoy, null, null, null, null, v_id, v_est);

  commit;
  pkg_seguridad.sp_cerrar_sesion;
  dbms_output.put_line('Datos de prueba cargados.');
exception when others then
  -- los paquetes confirman por su cuenta: si falla a medias, correr 24_limpieza_para_pruebas.sql y repetir
  dbms_output.put_line('ERROR: ' || sqlerrm || ' | ' || dbms_utility.format_error_backtrace);
end;
/
select (select count(*) from clientes) clientes, (select count(*) from proveedores) proveedores,
       (select count(*) from productos) productos, (select count(*) from insumos) materias_primas,
       (select count(*) from recetas_producto) lineas_receta, (select count(*) from precios_cliente) precios_cliente,
       (select count(*) from precios_proveedor) precios_proveedor, (select count(*) from compras_insumo) compras
from dual;
select i.codigo, i.stock_actual, i.costo_promedio from insumos i order by i.id_insumo;
