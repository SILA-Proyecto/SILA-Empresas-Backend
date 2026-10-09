package com.llanolat.sila.seguridad.usuarios;

import com.llanolat.sila.infra.Page;
import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.seguridad.PasswordService;
import com.llanolat.sila.seguridad.VerificadorUsuario;
import com.llanolat.sila.seguridad.usuarios.UsuarioDtos.ActualizarUsuarioRequest;
import com.llanolat.sila.seguridad.usuarios.UsuarioDtos.CrearUsuarioRequest;
import com.llanolat.sila.seguridad.usuarios.UsuarioDtos.UsuarioConClaveTemporal;
import org.springframework.stereotype.Service;

/**
 * Orquesta, no decide: quien puede administrar usuarios, que no se pueda dejar la empresa
 * sin ADMIN y que nadie se quite el acceso a si mismo lo resuelve pkg_usuarios en Oracle.
 * Aqui solo se genera la clave temporal (y su hash) y se relee la fila tras escribir.
 */
@Service
class UsuarioService {

    private final UsuarioRepository repo;
    private final PasswordService passwords;
    private final VerificadorUsuario verificador;

    UsuarioService(UsuarioRepository repo, PasswordService passwords, VerificadorUsuario verificador) {
        this.repo = repo;
        this.passwords = passwords;
        this.verificador = verificador;
    }

    Page<UsuarioDto> listar(String texto, Boolean activo, String rol, Integer page, Integer size, String sort) {
        return repo.listar(texto, activo, rol, page, size, sort);
    }

    UsuarioDto obtener(long id) {
        return repo.porId(id).orElseThrow(() -> SilaException.noEncontrado("El usuario no existe."));
    }

    UsuarioConClaveTemporal crear(CrearUsuarioRequest r) {
        String temporal = passwords.generarTemporal();
        long id = repo.crear(r.usuario(), r.nombre(), r.email(), r.rol(), passwords.hash(temporal));
        return new UsuarioConClaveTemporal(obtener(id), temporal);
    }

    UsuarioDto actualizar(long id, ActualizarUsuarioRequest r) {
        obtener(id);
        repo.actualizar(id, r.nombre(), r.email(), r.rol());
        verificador.invalidar(id);   // el cambio de rol vale desde ya
        return obtener(id);
    }

    UsuarioDto cambiarEstado(long id, boolean activo) {
        obtener(id);
        repo.cambiarEstado(id, activo);
        verificador.invalidar(id);   // desactivar corta el acceso desde ya
        return obtener(id);
    }

    UsuarioDto desbloquear(long id) {
        obtener(id);
        repo.desbloquear(id);
        return obtener(id);
    }

    UsuarioConClaveTemporal restablecerClave(long id) {
        obtener(id);
        String temporal = passwords.generarTemporal();
        repo.restablecerClave(id, passwords.hash(temporal));
        return new UsuarioConClaveTemporal(obtener(id), temporal);
    }

    UsuarioDto cerrarSesiones(long id) {
        obtener(id);
        repo.cerrarSesiones(id);
        verificador.invalidar(id);
        return obtener(id);
    }

    java.util.List<UsuarioRepository.SesionActiva> sesiones(long id) {
        obtener(id);
        return repo.sesionesActivas(id);
    }

    UsuarioDto restablecerMfa(long id) {
        obtener(id);
        repo.restablecerMfa(id);
        return obtener(id);
    }
}
