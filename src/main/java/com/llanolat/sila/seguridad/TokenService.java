package com.llanolat.sila.seguridad;

import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.UUID;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.stereotype.Service;

/**
 * Emite los JWT. El claim "tipo" separa lo que cada token permite:
 * ACCESO abre la API; los demas (MFA, MFA_ENROLAR, CAMBIAR_CLAVE) son de un
 * solo paso del login y NO sirven para llamar al resto del API.
 */
@Service
public class TokenService {

    public enum Tipo {
        ACCESO, MFA, MFA_ENROLAR, CAMBIAR_CLAVE;

        public String claim() { return name().toLowerCase(Locale.ROOT); }
    }

    private final JwtEncoder encoder;
    private final SeguridadProps props;

    public TokenService(JwtEncoder encoder, SeguridadProps props) {
        this.encoder = encoder;
        this.props = props;
    }

    /** Tokens temporales del login: sin sesion todavia. */
    public String emitir(Tipo tipo, long idUsuario, String usuario, String rol) {
        return emitir(tipo, idUsuario, usuario, rol, null);
    }

    /** El de ACCESO lleva "sid", la familia de la sesion: cerrar esa sesion corta tambien este token. */
    public String emitir(Tipo tipo, long idUsuario, String usuario, String rol, String sid) {
        Duration ttl = tipo == Tipo.ACCESO ? props.accesoTtl() : props.temporalTtl();
        Instant ahora = Instant.now();
        JwtClaimsSet.Builder claims = JwtClaimsSet.builder()
                .issuer(props.emisor())
                .subject(usuario)
                .issuedAt(ahora)
                .expiresAt(ahora.plus(ttl))
                .id(UUID.randomUUID().toString())
                .claim("uid", idUsuario)
                .claim("rol", rol)
                .claim("tipo", tipo.claim());
        if (sid != null) {
            claims = claims.claim("sid", sid);
        }
        JwtClaimsSet fijos = claims.build();
        return encoder.encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), fijos))
                      .getTokenValue();
    }

    public long segundosAcceso() {
        return props.accesoTtl().toSeconds();
    }
}
