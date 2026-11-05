package com.llanolat.sila.empresa;

import com.llanolat.sila.archivos.Imagenes.Imagen;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.infra.SilaTemplate;
import java.sql.Blob;
import java.sql.CallableStatement;
import java.time.Duration;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

/**
 * Los datos de la empresa y sus modulos, leidos de las vistas vw_empresa / vw_modulos con una cache corta
 * (sila.modulos.cache-ttl, 30 s por defecto): un cambio del dueno (sql/modulos.sh, sql/empresa.sh) se nota en menos de
 * un minuto sin reiniciar y no se consulta la base en cada peticion.
 * Nombre, nombre corto, NIT y modulos los cambia SOLO el dueno. El ADMIN de la empresa puede cambiar los datos de contacto,
 * el pie del comprobante y el logo (pkg_empresa, que vuelve a exigir el rol ADMIN en la base).
 * Si la base falla al refrescar, se sigue con la ultima copia buena (y se avisa en el log).
 * El logo no viaja en la copia: solo su huella; los bytes se leen cuando cambia la huella y se guardan aparte.
 */
@Service
public class EmpresaService {

    private static final Logger log = LoggerFactory.getLogger(EmpresaService.class);

    public static final String MENSAJE_INACTIVO = "Esta función no está activa para su empresa.";
    public static final String MENSAJE_SUSPENDIDA = "El servicio de su empresa está suspendido. Comuníquese con el proveedor del sistema.";

    /** empresa.estado (script 33). Solo el dueno lo cambia (sql/empresa.sh suspender | reactivar). */
    public static final String ACTIVA = "ACTIVA";
    public static final String SUSPENDIDA = "SUSPENDIDA";

    /** Si la fila de empresa aun no existe (base sin sembrar), el sistema sigue funcionando con este nombre neutro. */
    static final Datos SIN_DATOS = new Datos("SILA", "SILA", null, null, null, null, null, null);

    public record Datos(String nombre, String nombreCorto, String nit, String direccion, String telefono,
                        String ciudad, String correoContacto, String pieComprobante) {}

    /** El logo tal como se sirve. {@code sha256}: su huella, que hace de ETag y de version para el dashboard. */
    public record Logo(byte[] contenido, String tipo, String sha256) {}

    private record LogoInfo(String tipo, String sha256) {}

    public record Modulo(String codigo, String nombre, String descripcion, int nucleo, int activo) {}

    private record Copia(Datos datos, List<Modulo> modulos, Set<String> activos, Integer versionEsquema, LogoInfo logo,
                         String estado, long venceNanos) {}

    private final JdbcClient jdbc;
    private final SilaTemplate sila;
    private final long ttlNanos;
    private volatile Copia copia;
    private volatile Logo logo;

    public EmpresaService(JdbcClient jdbc, SilaTemplate sila, @Value("${sila.modulos.cache-ttl:30s}") Duration ttl) {
        this.jdbc = jdbc;
        this.sila = sila;
        this.ttlNanos = ttl.toNanos();
    }

    public Datos datos() { return actual().datos(); }

    /** El numero del ultimo script aplicado (version_esquema), o null si la base aun no lo registra. */
    public Integer versionEsquema() { return actual().versionEsquema(); }

    /** ACTIVA o SUSPENDIDA. */
    public String estado() { return actual().estado(); }

    public boolean suspendida() { return SUSPENDIDA.equals(actual().estado()); }

    /** Todos los modulos (activos o no), en el orden del catalogo. */
    public List<Modulo> modulos() { return actual().modulos(); }

    /** Falso si el modulo esta apagado o no existe en el catalogo (ante la duda, cerrado). */
    public boolean activo(String codigo) {
        Copia c = actual();
        if (c.activos().contains(codigo)) return true;
        if (c.modulos().stream().noneMatch(m -> m.codigo().equals(codigo))) {
            log.warn("Modulo desconocido consultado: {}", codigo);
        }
        return false;
    }

    /** Lanza 20020 (403) si el modulo esta apagado. */
    public void exigir(String codigo) {
        if (!activo(codigo)) {
            throw SilaException.de(SilaException.MODULO_INACTIVO, MENSAJE_INACTIVO);
        }
    }

    /** Descarta la copia (pruebas, o para forzar la relectura). */
    public void invalidar() { copia = null; }

    // ---------- logo ----------

    /** Primeros 16 caracteres de la huella del logo (cambia cuando cambia el logo), o null si no hay logo. */
    public String logoVersion() {
        LogoInfo l = actual().logo();
        return l == null ? null : l.sha256().substring(0, 16);
    }

    public Optional<Logo> logo() {
        LogoInfo info = actual().logo();
        if (info == null) return Optional.empty();
        Logo l = logo;
        if (l != null && l.sha256().equals(info.sha256())) return Optional.of(l);
        Optional<Logo> leido = jdbc.sql("SELECT contenido, tipo, sha256 FROM vw_empresa_logo")
                .query((rs, i) -> new Logo(rs.getBytes(1), rs.getString(2), rs.getString(3))).optional();
        logo = leido.orElse(null);
        return leido;
    }

    // ---------- cambios del ADMIN (la base exige el rol otra vez) ----------

    public void actualizarContacto(String direccion, String telefono, String ciudad, String correo, String pie) {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_empresa.sp_actualizar_contacto(?,?,?,?,?)}")) {
                s.setString(1, direccion);
                s.setString(2, telefono);
                s.setString(3, ciudad);
                s.setString(4, correo);
                s.setString(5, pie);
                s.execute();
                return null;
            }
        });
        invalidar();
    }

    public void fijarLogo(Imagen img) {
        sila.ejecutar(c -> {
            Blob blob = c.createBlob();
            try (CallableStatement s = c.prepareCall("{call pkg_empresa.sp_fijar_logo(?,?,?)}")) {
                blob.setBytes(1, img.contenido());
                s.setBlob(1, blob);
                s.setString(2, img.tipo());
                s.setString(3, img.sha256());
                s.execute();
                return null;
            } finally {
                blob.free();
            }
        });
        invalidar();
    }

    public void quitarLogo() {
        sila.ejecutar(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_empresa.sp_quitar_logo}")) {
                s.execute();
                return null;
            }
        });
        invalidar();
    }

    private Copia actual() {
        Copia c = copia;
        if (c != null && System.nanoTime() < c.venceNanos()) return c;
        synchronized (this) {
            c = copia;
            if (c != null && System.nanoTime() < c.venceNanos()) return c;
            try {
                copia = c = leer();
            } catch (RuntimeException e) {
                if (c == null) throw e;
                log.warn("No se pudo refrescar empresa/modulos; sigo con la ultima copia: {}", e.getMessage());
                copia = c = new Copia(c.datos(), c.modulos(), c.activos(), c.versionEsquema(), c.logo(), c.estado(),
                                      System.nanoTime() + ttlNanos);
            }
            return c;
        }
    }

    private Copia leer() {
        Datos datos = jdbc.sql("SELECT nombre, nombre_corto, nit, direccion, telefono, ciudad, correo_contacto, pie_comprobante"
                        + " FROM vw_empresa")
                .query(Datos.class).optional().orElse(SIN_DATOS);
        List<Modulo> modulos = jdbc.sql("SELECT codigo, nombre, descripcion, nucleo, activo FROM vw_modulos ORDER BY orden")
                .query(Modulo.class).list();
        Set<String> activos = new HashSet<>();
        for (Modulo m : modulos) if (m.activo() == 1) activos.add(m.codigo());
        return new Copia(datos, List.copyOf(modulos), Set.copyOf(activos), leerVersion(), leerLogo(), leerEstado(),
                         System.nanoTime() + ttlNanos);
    }

    /** Una base anterior al script 33 (o sin fila de empresa) se toma como ACTIVA. */
    private String leerEstado() {
        try {
            return jdbc.sql("SELECT estado FROM vw_empresa").query(String.class).optional().orElse(ACTIVA);
        } catch (DataAccessException e) {
            return ACTIVA;
        }
    }

    /** Solo el tipo y la huella (no el contenido). Una base anterior al script 31 no tiene logo. */
    private LogoInfo leerLogo() {
        try {
            return jdbc.sql("SELECT tipo, sha256 FROM vw_empresa_logo").query(LogoInfo.class).optional().orElse(null);
        } catch (DataAccessException e) {
            return null;
        }
    }

    /** Una base anterior a la tabla version_esquema simplemente no tiene version (null), no es un error. */
    private Integer leerVersion() {
        try {
            return jdbc.sql("SELECT MAX(numero) FROM vw_version_esquema")
                    .query((rs, i) -> { int v = rs.getInt(1); return rs.wasNull() ? null : v; }).single();
        } catch (DataAccessException e) {
            return null;
        }
    }
}
