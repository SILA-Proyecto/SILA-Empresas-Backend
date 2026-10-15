package com.llanolat.sila.seguridad.auth;

import com.llanolat.sila.infra.SilaTemplate;
import com.yubico.webauthn.CredentialRepository;
import com.yubico.webauthn.RegisteredCredential;
import com.yubico.webauthn.data.ByteArray;
import com.yubico.webauthn.data.PublicKeyCredentialDescriptor;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Passkeys (WebAuthn) en mfa_passkeys, via pkg_passkeys y vw_passkeys. Sin sesion de aplicacion (como el login).
 * Tambien es el CredentialRepository que pide la biblioteca Yubico: "username" = usuario de SILA,
 * "userHandle" = usuarios_app.webauthn_handle. Ids y llaves viajan en base64url.
 */
@Repository
class PasskeyRepository implements CredentialRepository {

    record Passkey(Long idPasskey, String nombre, LocalDateTime fechaCreacion, LocalDateTime fechaUltimoUso) {}

    private record Fila(String usuario, String webauthnHandle, String credentialId, String llavePublica, Long contador) {}

    private static final String FILA = "SELECT usuario, webauthn_handle, credential_id, llave_publica, contador FROM vw_passkeys ";

    private final SilaTemplate sila;
    private final JdbcClient jdbc;

    PasskeyRepository(SilaTemplate sila, JdbcClient jdbc) {
        this.sila = sila;
        this.jdbc = jdbc;
    }

    /** Devuelve el handle de la persona; si no tenia, guarda {@code nuevo}. */
    String asegurarHandle(long idUsuario, String nuevo) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_passkeys.sp_asegurar_handle(?,?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, nuevo);
                s.registerOutParameter(3, Types.VARCHAR);
                s.execute();
                return s.getString(3);
            }
        });
    }

    long registrar(long idUsuario, String credentialId, String llave, long contador, String nombre, String transportes) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_passkeys.sp_registrar(?,?,?,?,?,?,?)}")) {
                s.setLong(1, idUsuario);
                s.setString(2, credentialId);
                s.setString(3, llave);
                s.setLong(4, contador);
                s.setString(5, nombre);
                s.setString(6, transportes);
                s.registerOutParameter(7, Types.NUMERIC);
                s.execute();
                return s.getLong(7);
            }
        });
    }

    void usar(String credentialId, long contador) {
        sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_passkeys.sp_usar(?,?)}")) {
                s.setString(1, credentialId);
                s.setLong(2, contador);
                s.execute();
                return null;
            }
        });
    }

    int quitar(long idUsuario, long idPasskey) {
        return sila.ejecutarSinSesion(c -> {
            try (CallableStatement s = c.prepareCall("{call pkg_passkeys.sp_quitar(?,?,?)}")) {
                s.setLong(1, idUsuario);
                s.setLong(2, idPasskey);
                s.registerOutParameter(3, Types.NUMERIC);
                s.execute();
                return s.getInt(3);
            }
        });
    }

    List<Passkey> listar(long idUsuario) {
        return jdbc.sql("SELECT id_passkey, nombre, fecha_creacion, fecha_ultimo_uso FROM vw_passkeys "
                      + "WHERE id_usuario = :id ORDER BY fecha_creacion")
                   .param("id", idUsuario).query(Passkey.class).list();
    }

    boolean tiene(long idUsuario) {
        return jdbc.sql("SELECT COUNT(*) FROM vw_passkeys WHERE id_usuario = :id")
                   .param("id", idUsuario).query(Integer.class).single() > 0;
    }

    // ---------- CredentialRepository (Yubico) ----------

    @Override
    public Set<PublicKeyCredentialDescriptor> getCredentialIdsForUsername(String usuario) {
        return filas("usuario = :v", usuario).stream()
                .map(f -> PublicKeyCredentialDescriptor.builder().id(b64(f.credentialId())).build())
                .collect(Collectors.toSet());
    }

    @Override
    public Optional<ByteArray> getUserHandleForUsername(String usuario) {
        return filas("usuario = :v", usuario).stream().findFirst().map(f -> b64(f.webauthnHandle()));
    }

    @Override
    public Optional<String> getUsernameForUserHandle(ByteArray handle) {
        return filas("webauthn_handle = :v", handle.getBase64Url()).stream().findFirst().map(Fila::usuario);
    }

    @Override
    public Optional<RegisteredCredential> lookup(ByteArray credentialId, ByteArray handle) {
        return filas("credential_id = :v", credentialId.getBase64Url()).stream()
                .filter(f -> f.webauthnHandle().equals(handle.getBase64Url()))
                .findFirst().map(PasskeyRepository::registrada);
    }

    @Override
    public Set<RegisteredCredential> lookupAll(ByteArray credentialId) {
        return filas("credential_id = :v", credentialId.getBase64Url()).stream()
                .map(PasskeyRepository::registrada).collect(Collectors.toSet());
    }

    private List<Fila> filas(String donde, String valor) {
        return jdbc.sql(FILA + "WHERE " + donde).param("v", valor).query(Fila.class).list();
    }

    private static RegisteredCredential registrada(Fila f) {
        return RegisteredCredential.builder()
                .credentialId(b64(f.credentialId()))
                .userHandle(b64(f.webauthnHandle()))
                .publicKeyCose(b64(f.llavePublica()))
                .signatureCount(f.contador())
                .build();
    }

    private static ByteArray b64(String base64Url) {
        try {
            return ByteArray.fromBase64Url(base64Url);
        } catch (com.yubico.webauthn.data.exception.Base64UrlException e) {
            throw new IllegalStateException("Dato WebAuthn corrupto en la base.", e);
        }
    }
}
