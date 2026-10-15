package com.llanolat.sila.seguridad.auth;

import com.llanolat.sila.infra.SilaException;
import com.yubico.webauthn.AssertionRequest;
import com.yubico.webauthn.AssertionResult;
import com.yubico.webauthn.FinishAssertionOptions;
import com.yubico.webauthn.FinishRegistrationOptions;
import com.yubico.webauthn.RegistrationResult;
import com.yubico.webauthn.RelyingParty;
import com.yubico.webauthn.StartAssertionOptions;
import com.yubico.webauthn.StartRegistrationOptions;
import com.yubico.webauthn.data.AuthenticatorSelectionCriteria;
import com.yubico.webauthn.data.ByteArray;
import com.yubico.webauthn.data.PublicKeyCredential;
import com.yubico.webauthn.data.PublicKeyCredentialCreationOptions;
import com.yubico.webauthn.data.RelyingPartyIdentity;
import com.yubico.webauthn.data.ResidentKeyRequirement;
import com.yubico.webauthn.data.UserIdentity;
import com.yubico.webauthn.data.UserVerificationRequirement;
import java.net.URI;
import java.time.Duration;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * WebAuthn con la biblioteca Yubico. La llave queda ligada al DOMINIO (RP ID): se acepta cada origen del
 * dashboard (sila.cors.origenes: localhost y el de ngrok) y su RP ID es el host de ese origen; una passkey
 * registrada en un dominio no sirve en otro. Al migrar a servidor basta cambiar los origenes.
 *
 * Los desafios viven en memoria 3 minutos, uno por persona y proposito, y se consumen al usarse
 * (como LimiteTasa: con varias instancias habria que moverlos a la base o a Redis).
 */
@Component
class WebAuthn {

    private static final Duration VIDA = Duration.ofMinutes(3);
    private static final long TIMEOUT_MS = 120_000;

    record Registro(String credentialId, String llave, long contador, String transportes) {}

    record Uso(String credentialId, long contador) {}

    private record Pendiente(Object solicitud, String origen, Instant expira) {}

    private final PasskeyRepository repo;
    private final List<String> origenes;
    private final Map<String, RelyingParty> partes = new ConcurrentHashMap<>();
    private final Map<String, Pendiente> pendientes = new ConcurrentHashMap<>();

    WebAuthn(PasskeyRepository repo, @Value("${sila.cors.origenes:http://localhost:4200}") String[] origenes) {
        this.repo = repo;
        this.origenes = Arrays.stream(origenes).map(String::trim).filter(o -> !o.isEmpty()).toList();
    }

    // ---------- registro ----------

    /** Opciones para navigator.credentials.create(), como JSON ({"publicKey": {...}}). */
    String iniciarRegistro(String origen, long idUsuario, String usuario, String nombre, String handle) {
        RelyingParty rp = parte(origen);
        PublicKeyCredentialCreationOptions opciones = rp.startRegistration(StartRegistrationOptions.builder()
                .user(UserIdentity.builder().name(usuario).displayName(nombre).id(b64(handle)).build())
                .authenticatorSelection(AuthenticatorSelectionCriteria.builder()
                        .residentKey(ResidentKeyRequirement.PREFERRED)
                        .userVerification(UserVerificationRequirement.REQUIRED)   // exige Face ID / huella / PIN
                        .build())
                .timeout(TIMEOUT_MS)
                .build());
        guardar("registro:" + idUsuario, opciones, origen);
        try {
            return opciones.toCredentialsCreateJson();
        } catch (Exception e) {
            throw new IllegalStateException("No se pudieron serializar las opciones WebAuthn.", e);
        }
    }

    Registro terminarRegistro(String origen, long idUsuario, String credencialJson) {
        PublicKeyCredentialCreationOptions opciones = (PublicKeyCredentialCreationOptions) tomar("registro:" + idUsuario, origen);
        try {
            var pkc = PublicKeyCredential.parseRegistrationResponseJson(credencialJson);
            RegistrationResult r = parte(origen).finishRegistration(
                    FinishRegistrationOptions.builder().request(opciones).response(pkc).build());
            String transportes = r.getKeyId().getTransports()
                    .map(t -> String.join(",", t.stream().map(x -> x.getId()).toList())).orElse(null);
            return new Registro(r.getKeyId().getId().getBase64Url(), r.getPublicKeyCose().getBase64Url(),
                                r.getSignatureCount(), transportes);
        } catch (Exception e) {
            throw SilaException.de(SilaException.PARAMETRO_INVALIDO, "No se pudo verificar el dispositivo. Intente de nuevo.");
        }
    }

    // ---------- inicio de sesion ----------

    /** Opciones para navigator.credentials.get(), como JSON ({"publicKey": {...}}). */
    String iniciarUso(String origen, long idUsuario, String usuario) {
        AssertionRequest solicitud = parte(origen).startAssertion(StartAssertionOptions.builder()
                .username(usuario)
                .userVerification(UserVerificationRequirement.REQUIRED)
                .timeout(TIMEOUT_MS)
                .build());
        guardar("uso:" + idUsuario, solicitud, origen);
        try {
            return solicitud.toCredentialsGetJson();
        } catch (Exception e) {
            throw new IllegalStateException("No se pudieron serializar las opciones WebAuthn.", e);
        }
    }

    /** null si la firma no es valida (el llamador cuenta el fallo). */
    Uso terminarUso(String origen, long idUsuario, String usuario, String credencialJson) {
        AssertionRequest solicitud = (AssertionRequest) tomar("uso:" + idUsuario, origen);
        try {
            var pkc = PublicKeyCredential.parseAssertionResponseJson(credencialJson);
            AssertionResult r = parte(origen).finishAssertion(
                    FinishAssertionOptions.builder().request(solicitud).response(pkc).build());
            if (!r.isSuccess() || !usuario.equals(r.getUsername())) {
                return null;
            }
            return new Uso(r.getCredential().getCredentialId().getBase64Url(), r.getSignatureCount());
        } catch (Exception e) {
            return null;
        }
    }

    // ---------- piezas ----------

    /** El origen debe ser uno de los del dashboard; si no, no hay RP ID con que firmar. */
    private RelyingParty parte(String origen) {
        if (origen == null || !origenes.contains(origen)) {
            throw SilaException.de(SilaException.PERMISO_DENEGADO, "Origen no permitido para Face ID / huella.");
        }
        return partes.computeIfAbsent(origen, o -> RelyingParty.builder()
                .identity(RelyingPartyIdentity.builder().id(URI.create(o).getHost()).name("SILA Llanolat").build())
                .credentialRepository(repo)
                .origins(Set.of(o))
                .build());
    }

    private void guardar(String clave, Object solicitud, String origen) {
        Instant ahora = Instant.now();
        pendientes.values().removeIf(p -> p.expira().isBefore(ahora));
        pendientes.put(clave, new Pendiente(solicitud, origen, ahora.plus(VIDA)));
    }

    /** Un desafio sirve UNA vez, desde el mismo origen y antes de vencer. */
    private Object tomar(String clave, String origen) {
        Pendiente p = pendientes.remove(clave);
        if (p == null || p.expira().isBefore(Instant.now()) || !p.origen().equals(origen)) {
            throw SilaException.de(SilaException.ESTADO_INVALIDO, "La solicitud vencio o no existe. Intente de nuevo.");
        }
        return p.solicitud();
    }

    private static ByteArray b64(String base64Url) {
        try {
            return ByteArray.fromBase64Url(base64Url);
        } catch (com.yubico.webauthn.data.exception.Base64UrlException e) {
            throw new IllegalStateException(e);
        }
    }
}
