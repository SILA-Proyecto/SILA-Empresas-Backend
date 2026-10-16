package com.llanolat.sila.archivos;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.llanolat.sila.archivos.CifradoDocs.ArchivoIlegibleException;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

class CifradoDocsTest {

    private final CifradoDocs c = new CifradoDocs(Fixtures.props(1, false));

    @Test
    void descifraLoQueCifro() {
        String ruta = c.nuevaRuta();
        byte[] plano = "contenido del comprobante".getBytes(StandardCharsets.UTF_8);
        CifradoDocs.Descifrado d = c.descifrar(c.cifrar(plano, ruta));
        assertThat(d.contenido()).isEqualTo(plano);
        assertThat(d.ruta()).isEqualTo(ruta);
    }

    @Test
    void elEncabezadoDiceLaRutaYElTextoNoSeVe() {
        String ruta = c.nuevaRuta();
        byte[] cif = c.cifrar("SECRETO-visible".getBytes(StandardCharsets.UTF_8), ruta);
        assertThat(CifradoDocs.rutaDe(cif)).isEqualTo(ruta);
        assertThat(new String(cif, StandardCharsets.ISO_8859_1)).doesNotContain("SECRETO");
    }

    @Test
    void cadaCifradoUsaUnIvDistinto() {
        String ruta = c.nuevaRuta();
        assertThat(c.cifrar(new byte[10], ruta)).isNotEqualTo(c.cifrar(new byte[10], ruta));
    }

    @Test
    void cambiarUnByteOLaRutaDelEncabezadoLoInvalida() {
        String ruta = c.nuevaRuta();
        byte[] cif = c.cifrar(new byte[100], ruta);
        byte[] tocado = cif.clone();
        tocado[tocado.length - 1] ^= 1;
        assertThatThrownBy(() -> c.descifrar(tocado)).isInstanceOf(ArchivoIlegibleException.class);
        byte[] otraRuta = cif.clone();
        otraRuta[6] = (byte) (otraRuta[6] == 'a' ? 'b' : 'a');            // la ruta esta en el AAD
        assertThatThrownBy(() -> c.descifrar(otraRuta)).isInstanceOf(ArchivoIlegibleException.class);
    }

    @Test
    void otraLlaveNoDescifra() {
        byte[] otra = new byte[32];
        java.util.Arrays.fill(otra, (byte) 5);
        ArchivosProps p = Fixtures.props(1, false);
        CifradoDocs distinta = new CifradoDocs(new ArchivosProps(p.directorio(), java.util.Base64.getEncoder().encodeToString(otra),
                null, p.usuarioSistema(), p.empresa(), p.clamav(), p.drive()));
        byte[] cif = c.cifrar(new byte[20], c.nuevaRuta());
        assertThatThrownBy(() -> distinta.descifrar(cif)).isInstanceOf(ArchivoIlegibleException.class);
    }

    @Test
    void loQueNoEsDeSilaSeRechaza() {
        assertThat(CifradoDocs.rutaDe("%PDF-1.7 hola".getBytes(StandardCharsets.UTF_8))).isNull();
        assertThatThrownBy(() -> c.descifrar(new byte[100])).isInstanceOf(ArchivoIlegibleException.class);
    }

    @Test
    void rutaInvalidaNoSeAcepta() {
        assertThatThrownBy(() -> c.cifrar(new byte[1], "../../etc/passwd")).isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void sellarAtaElDatoASuEtiqueta() {
        byte[] s = c.sellar("token".getBytes(StandardCharsets.UTF_8), "a");
        assertThat(c.abrir(s, "a")).isEqualTo("token".getBytes(StandardCharsets.UTF_8));
        assertThatThrownBy(() -> c.abrir(s, "b")).isInstanceOf(ArchivoIlegibleException.class);
    }
}
