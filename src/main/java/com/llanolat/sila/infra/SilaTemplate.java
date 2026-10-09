package com.llanolat.sila.infra;

import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.SQLException;
import javax.sql.DataSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Component;

/**
 * Ejecuta una operacion de negocio sobre UNA sola conexion, enmarcada por
 * sp_iniciar_sesion / sp_cerrar_sesion.
 *
 * Por que una sola conexion: el contexto CTX_SILA (usuario y rol) vive en la
 * sesion de base de datos, es decir en la conexion. Si se inicia la sesion en
 * una conexion y se llama el procedimiento en otra -- que es exactamente lo
 * que pasa si se usan dos llamadas sueltas de JdbcTemplate sin transaccion --
 * el procedimiento corre sin identidad y sp_exigir_rol lanza ORA-20008.
 *
 * Por que el finally: la conexion vuelve al pool. Si no se limpia el contexto,
 * la siguiente peticion que tome esa misma conexion fisica hereda el usuario y
 * el rol de la anterior.
 *
 * No usar @Transactional alrededor de estas llamadas: cada procedimiento hace
 * su propio COMMIT o ROLLBACK y es una unidad de trabajo completa.
 */
@Component
public class SilaTemplate {

    private static final Logger log = LoggerFactory.getLogger(SilaTemplate.class);

    @FunctionalInterface
    public interface Operacion<T> {
        T ejecutar(Connection c) throws SQLException;
    }

    private final DataSource dataSource;
    private final ObjectProvider<Identidad> identidad;

    public SilaTemplate(DataSource dataSource, ObjectProvider<Identidad> identidad) {
        this.dataSource = dataSource;
        this.identidad = identidad;
    }

    /** Escritura: abre sesion de aplicacion, ejecuta y cierra siempre. */
    public <T> T ejecutar(Operacion<T> operacion) {
        Identidad id = identidad.getIfAvailable(() -> {
            throw new IllegalStateException(
                "No hay ninguna implementacion de Identidad registrada. Configure "
              + "sila.seguridad.modo=desarrollo en application.yml, o registre un "
              + "bean que lea el usuario y el rol del JWT.");
        });
        String usuario = id.usuario();
        String rol = id.rol();

        try (Connection c = dataSource.getConnection()) {
            iniciarSesion(c, usuario, rol);
            try {
                return operacion.ejecutar(c);
            } finally {
                cerrarSesion(c);
            }
        } catch (SQLException e) {
            SilaException se = SilaException.de(e);
            if (se.esDeNegocio()) {
                log.debug("Error de negocio ORA-{} para {}: {}", se.getCodigo(), usuario, se.getMessage());
            } else {
                log.error("Error interno ORA-{} para {} (ref. {})",
                          se.getCodigo(), usuario, se.getReferencia(), e);
            }
            throw se;
        }
    }

    /**
     * Operacion SIN sesion de aplicacion: es la del login, que ocurre antes de saber
     * quien es la persona. Solo debe llamar procedimientos de pkg_autenticacion, que no
     * exigen rol. Cualquier otra escritura debe pasar por {@link #ejecutar}.
     */
    public <T> T ejecutarSinSesion(Operacion<T> operacion) {
        try (Connection c = dataSource.getConnection()) {
            return operacion.ejecutar(c);
        } catch (SQLException e) {
            SilaException se = SilaException.de(e);
            if (se.esDeNegocio()) {
                log.debug("Error de negocio ORA-{} (sin sesion): {}", se.getCodigo(), se.getMessage());
            } else {
                log.error("Error interno ORA-{} (sin sesion, ref. {})", se.getCodigo(), se.getReferencia(), e);
            }
            throw se;
        }
    }

    /** Variante para procedimientos sin valor de retorno. */
    public void ejecutarSinRetorno(Operacion<Void> operacion) {
        ejecutar(operacion);
    }

    private void iniciarSesion(Connection c, String usuario, String rol) throws SQLException {
        try (CallableStatement s = c.prepareCall("{call pkg_seguridad.sp_iniciar_sesion(?, ?)}")) {
            s.setString(1, usuario);
            s.setString(2, rol);
            s.execute();
        }
    }

    private void cerrarSesion(Connection c) {
        try (CallableStatement s = c.prepareCall("{call pkg_seguridad.sp_cerrar_sesion}")) {
            s.execute();
        } catch (SQLException e) {
            // No enmascarar el error original de la operacion, pero si avisar:
            // una conexion que vuelve al pool con contexto es una fuga de identidad.
            log.error("No se pudo cerrar la sesion de aplicacion; la conexion vuelve al pool "
                    + "con el contexto puesto", e);
        }
    }
}
