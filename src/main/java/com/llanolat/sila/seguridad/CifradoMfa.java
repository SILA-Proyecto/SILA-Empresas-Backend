package com.llanolat.sila.seguridad;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.stereotype.Component;

/**
 * Cifra el secreto TOTP antes de guardarlo en Oracle (AES-256-GCM). Asi, quien lea la
 * base (un respaldo, un DBA) no puede generar codigos. El id del usuario va como dato
 * asociado: un secreto copiado a la fila de otro usuario no descifra.
 */
@Component
public class CifradoMfa {

    private static final int IV_BYTES = 12;
    private static final int TAG_BITS = 128;

    private final SecretKeySpec clave;
    private final SecureRandom azar = new SecureRandom();

    public CifradoMfa(SeguridadProps props) {
        this.clave = new SecretKeySpec(Claves.decodificar(props.mfaKey(), "SILA_MFA_KEY", 32), 0, 32, "AES");
    }

    public String cifrar(byte[] secreto, long idUsuario) {
        try {
            byte[] iv = new byte[IV_BYTES];
            azar.nextBytes(iv);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, clave, new GCMParameterSpec(TAG_BITS, iv));
            c.updateAAD(aad(idUsuario));
            byte[] ct = c.doFinal(secreto);
            return Base64.getEncoder().encodeToString(ByteBuffer.allocate(iv.length + ct.length).put(iv).put(ct).array());
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("No se pudo cifrar el secreto.", e);
        }
    }

    public byte[] descifrar(String cifrado, long idUsuario) {
        try {
            byte[] todo = Base64.getDecoder().decode(cifrado);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, clave, new GCMParameterSpec(TAG_BITS, todo, 0, IV_BYTES));
            c.updateAAD(aad(idUsuario));
            return c.doFinal(todo, IV_BYTES, todo.length - IV_BYTES);
        } catch (GeneralSecurityException | IllegalArgumentException e) {
            throw new IllegalStateException("No se pudo descifrar el secreto del segundo factor.", e);
        }
    }

    private static byte[] aad(long idUsuario) {
        return ("sila-mfa:" + idUsuario).getBytes(StandardCharsets.UTF_8);
    }
}
