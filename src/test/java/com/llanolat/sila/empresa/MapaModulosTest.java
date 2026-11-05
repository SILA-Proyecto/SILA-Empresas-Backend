package com.llanolat.sila.empresa;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Optional;
import org.junit.jupiter.api.Test;

class MapaModulosTest {

    private static Optional<String> modulo(String metodo, String ruta) {
        return MapaModulos.moduloDe(metodo, ruta);
    }

    @Test
    void cadaModuloOpcionalTieneSusRutas() {
        assertThat(modulo("GET", "/api/v1/cartera/clientes")).contains("CREDITO");
        assertThat(modulo("POST", "/api/v1/cartera/abonos")).contains("CREDITO");
        assertThat(modulo("POST", "/api/v1/cartera/castigos")).contains("CREDITO");
        assertThat(modulo("GET", "/api/v1/cartera/edades/clientes")).contains("CREDITO");
        assertThat(modulo("GET", "/api/v1/precios-cliente")).contains("PRECIOS_CLIENTE");
        assertThat(modulo("PUT", "/api/v1/precios-cliente")).contains("PRECIOS_CLIENTE");
        assertThat(modulo("PATCH", "/api/v1/precios-cliente/7/estado")).contains("PRECIOS_CLIENTE");
        assertThat(modulo("GET", "/api/v1/acopio/calidad")).contains("CALIDAD_LECHE");
        assertThat(modulo("GET", "/api/v1/acopio/umbrales")).contains("CALIDAD_LECHE");
        assertThat(modulo("GET", "/api/v1/reportes/margen")).contains("MARGEN");
        assertThat(modulo("POST", "/api/v1/asistente/mensajes")).contains("ASISTENTE");
        assertThat(modulo("GET", "/api/v1/auditoria/accesos")).contains("AUDITORIA");
        assertThat(modulo("GET", "/api/v1/auditoria/cambios")).contains("AUDITORIA");
        assertThat(modulo("GET", "/api/v1/auditoria/errores")).contains("AUDITORIA");
        assertThat(modulo("PUT", "/api/v1/parametros/IVA_GENERAL")).contains("PARAMETROS");
    }

    @Test
    void leerParametrosYLasQuincenasSigueEnElNucleo() {
        // otras pantallas leen los parametros; RESULTADO_QUINCENA no bloquea rutas, solo omite cifras
        assertThat(modulo("GET", "/api/v1/parametros")).isEmpty();
        assertThat(modulo("GET", "/api/v1/periodos")).isEmpty();
        assertThat(modulo("GET", "/api/v1/periodos/actual")).isEmpty();
        assertThat(modulo("PATCH", "/api/v1/periodos/3/estado")).isEmpty();
        assertThat(modulo("GET", "/api/v1/tablero")).isEmpty();
    }

    @Test
    void archivosSeparaLoSubidoDeLosPdfDeComprobantes() {
        // del nucleo: ver, opciones y descargar un archivo por id, y pedir el PDF de un comprobante
        assertThat(modulo("GET", "/api/v1/archivos/comprobante/VENTA/65")).isEmpty();
        assertThat(modulo("GET", "/api/v1/archivos/12")).isEmpty();
        assertThat(modulo("GET", "/api/v1/archivos/12/opciones-descarga")).isEmpty();
        assertThat(modulo("GET", "/api/v1/archivos/12/contenido")).isEmpty();
        assertThat(modulo("POST", "/api/v1/archivos/12/descarga")).isEmpty();
        // del modulo: todo lo demas
        for (String[] r : new String[][] {
                {"GET", "/api/v1/archivos"}, {"POST", "/api/v1/archivos"}, {"GET", "/api/v1/archivos/explorador"},
                {"GET", "/api/v1/archivos/carpetas"}, {"POST", "/api/v1/archivos/carpetas"},
                {"POST", "/api/v1/archivos/carpetas/3/archivar"}, {"POST", "/api/v1/archivos/12/archivar"},
                {"POST", "/api/v1/archivos/descifrar"}, {"GET", "/api/v1/archivos/accesos"},
                {"GET", "/api/v1/archivos/drive/estado"}, {"GET", "/api/v1/archivos/drive/autorizar"},
                {"POST", "/api/v1/archivos/drive/sincronizar"}, {"POST", "/api/v1/archivos/drive/desconectar"}}) {
            assertThat(modulo(r[0], r[1])).as(r[0] + " " + r[1]).contains("ARCHIVOS");
        }
    }

    @Test
    void elRetornoDeDriveEsPublicoPeroDelModulo() {
        MapaModulos.Regla r = MapaModulos.de("GET", "/api/v1/archivos/drive/callback").orElseThrow();
        assertThat(r.modulo()).isEqualTo("ARCHIVOS");
        assertThat(r.publica()).isTrue();
    }

    @Test
    void elNucleoNuncaSeMapea() {
        for (String[] r : new String[][] {
                {"GET", "/api/v1/ventas"}, {"POST", "/api/v1/ventas"}, {"POST", "/api/v1/ventas/5/anular"}, {"GET", "/api/v1/ventas/precios"},
                {"GET", "/api/v1/catalogos/clientes"}, {"GET", "/api/v1/inventario"}, {"POST", "/api/v1/produccion/lotes"},
                {"GET", "/api/v1/insumos/compras"}, {"POST", "/api/v1/insumos/compras"}, {"GET", "/api/v1/cuentas-proveedores/precios"},
                {"GET", "/api/v1/cuentas-proveedores/saldos"}, {"POST", "/api/v1/finanzas/gastos"}, {"GET", "/api/v1/periodos"},
                {"GET", "/api/v1/comprobantes"}, {"GET", "/api/v1/tablero"}, {"GET", "/api/v1/notificaciones"},
                {"GET", "/api/v1/usuarios"}, {"GET", "/api/v1/parametros"},
                {"POST", "/api/v1/auth/login"}, {"GET", "/api/v1/auth/yo"}, {"GET", "/api/v1/empresa"},
                {"GET", "/api/v1/empresa/publica"}, {"GET", "/api/v1/reportes"}, {"GET", "/actuator/health"}}) {
            assertThat(modulo(r[0], r[1])).as(r[0] + " " + r[1]).isEmpty();
        }
    }
}
