package com.llanolat.sila.legal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.llanolat.sila.infra.SilaException;
import com.llanolat.sila.legal.LegalProps.Documento;
import com.llanolat.sila.legal.LegalProps.Documentos;
import com.llanolat.sila.legal.LegalRepository.Aceptacion;
import com.llanolat.sila.legal.LegalService.Aceptado;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class LegalServiceTest {

    static final LegalProps PROPS = new LegalProps(new Documentos(
            new Documento("2.0", LocalDate.of(2026, 10, 28)), new Documento("1.5", LocalDate.of(2026, 10, 1))), Duration.ofSeconds(30));

    /** Repositorio de mentira: guarda en memoria lo que "la base" tendria y cuenta las consultas. */
    static class RepoFalso extends LegalRepository {
        final List<Aceptacion> filas = new ArrayList<>();
        int consultas, escrituras;
        String ultimaIp;

        RepoFalso() { super(null, null); }

        @Override List<Aceptacion> deUsuario(long idUsuario) { consultas++; return List.copyOf(filas); }

        @Override int aceptar(String vt, String vp, String ip, String ua) {
            escrituras++;
            ultimaIp = ip;
            filas.add(new Aceptacion("TERMINOS", vt, LocalDateTime.now()));
            filas.add(new Aceptacion("PRIVACIDAD", vp, LocalDateTime.now()));
            return 2;
        }
    }

    private static Aceptado t(String v) { return new Aceptado("TERMINOS", v); }
    private static Aceptado p(String v) { return new Aceptado("PRIVACIDAD", v); }

    @Test
    void vigentesSonLosDosEnOrdenFijo() {
        var v = new LegalService(new RepoFalso(), PROPS).vigentes();
        assertThat(v).extracting("documento").containsExactly("TERMINOS", "PRIVACIDAD");
        assertThat(v).extracting("version").containsExactly("2.0", "1.5");
    }

    @Test
    void sinAceptacionesNoEstaAlDia() {
        LegalService s = new LegalService(new RepoFalso(), PROPS);
        var e = s.estado(7);
        assertThat(e.alDia()).isFalse();
        assertThat(e.documentos()).allSatisfy(d -> {
            assertThat(d.aceptado()).isFalse();
            assertThat(d.fechaAceptacion()).isNull();
        });
        assertThat(s.alDia(7)).isFalse();
    }

    @Test
    void unaVersionAntiguaNoCuenta() {
        RepoFalso repo = new RepoFalso();
        repo.filas.add(new Aceptacion("TERMINOS", "1.0", LocalDateTime.now()));
        repo.filas.add(new Aceptacion("PRIVACIDAD", "1.5", LocalDateTime.now()));
        var e = new LegalService(repo, PROPS).estado(7);
        assertThat(e.alDia()).isFalse();
        assertThat(e.documentos().get(0).aceptado()).isFalse();   // TERMINOS: aceptó 1.0, rige 2.0
        assertThat(e.documentos().get(1).aceptado()).isTrue();    // PRIVACIDAD al día
    }

    @Test
    void aceptarLasVersionesVigentesDejaAlDiaYGuardaLaIp() {
        RepoFalso repo = new RepoFalso();
        LegalService s = new LegalService(repo, PROPS);
        assertThat(s.alDia(7)).isFalse();
        var e = s.aceptar(7, List.of(t("2.0"), p("1.5")), "10.1.2.3", "Firefox");
        assertThat(e.alDia()).isTrue();
        assertThat(repo.escrituras).isEqualTo(1);
        assertThat(repo.ultimaIp).isEqualTo("10.1.2.3");
        assertThat(s.alDia(7)).as("aceptar invalida lo recordado").isTrue();
    }

    @Test
    void lasDosVersionesQueSeEscribenSonLasVigentesNoLasDelCliente() {
        RepoFalso repo = new RepoFalso();
        new LegalService(repo, PROPS).aceptar(7, List.of(p("1.5"), t("2.0")), "ip", "ua");   // en otro orden
        assertThat(repo.filas).extracting("version").containsExactly("2.0", "1.5");
    }

    @Test
    void faltanSobranORepitenDocumentosDa400() {
        LegalService s = new LegalService(new RepoFalso(), PROPS);
        for (List<Aceptado> malo : List.of(
                List.<Aceptado>of(),
                List.of(t("2.0")),
                List.of(p("1.5")),
                List.of(t("2.0"), t("2.0")),
                List.of(t("2.0"), p("1.5"), t("2.0")),
                List.of(t("2.0"), new Aceptado("COOKIES", "1.0")),
                List.of(new Aceptado(null, "2.0"), p("1.5")))) {
            assertThatThrownBy(() -> s.aceptar(7, malo, "ip", "ua")).as(malo.toString())
                    .isInstanceOfSatisfying(SilaException.class, e -> assertThat(e.getCodigo()).isEqualTo(SilaException.PARAMETRO_INVALIDO));
        }
    }

    @Test
    void otraVersionDa409Con20023YNoEscribeNada() {
        RepoFalso repo = new RepoFalso();
        LegalService s = new LegalService(repo, PROPS);
        for (List<Aceptado> viejo : List.of(List.of(t("1.0"), p("1.5")), List.of(t("2.0"), p("1.0")), List.of(t("2.0 "), p("1.5")))) {
            assertThatThrownBy(() -> s.aceptar(7, viejo, "ip", "ua"))
                    .isInstanceOfSatisfying(SilaException.class, e -> assertThat(e.getCodigo()).isEqualTo(SilaException.VERSION_LEGAL_DESACTUALIZADA));
        }
        assertThat(repo.escrituras).isZero();
    }

    @Test
    void recuerdaElEstadoDentroDelTtl() {
        RepoFalso repo = new RepoFalso();
        LegalService s = new LegalService(repo, PROPS);
        s.alDia(7); s.alDia(7); s.alDia(7);
        assertThat(repo.consultas).isEqualTo(1);
        s.alDia(8);
        assertThat(repo.consultas).isEqualTo(2);
        s.invalidar(7);
        s.alDia(7);
        assertThat(repo.consultas).isEqualTo(3);
    }

    @Test
    void conTtlCeroSiempreConsulta() {
        RepoFalso repo = new RepoFalso();
        LegalService s = new LegalService(repo, new LegalProps(PROPS.documentos(), Duration.ZERO));
        s.alDia(7); s.alDia(7);
        assertThat(repo.consultas).isEqualTo(2);
    }
}
