package com.llanolat.sila.archivos;

import java.time.Duration;
import java.time.LocalDate;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Propiedades sila.archivos.*. La llave de cifrado llega por variable de entorno (SILA_DOCS_KEY), nunca en el repositorio.
 *
 * @param directorio  donde viven los archivos CIFRADOS (fuera de cualquier carpeta que sirva un servidor web)
 * @param docsKey     llave AES-256 en base64 (32 bytes). DISTINTA de SILA_MFA_KEY. Si se pierde, los archivos no se leen
 *                    (tampoco los copiados a Drive): guardar una copia FUERA del servidor
 * @param fechaCorte  los comprobantes de esta fecha en adelante reciben PDF si les falta (reintento automatico);
 *                    sin fecha el reintento queda apagado y los movimientos anteriores nunca reciben PDF
 * @param usuarioSistema identidad con la que corren los procesos sin peticion (reintento de PDF, envio a Drive)
 */
@ConfigurationProperties(prefix = "sila.archivos")
public record ArchivosProps(
        String directorio,
        String docsKey,
        LocalDate fechaCorte,
        @DefaultValue("sistema.archivos") String usuarioSistema,
        @DefaultValue Empresa empresa,
        @DefaultValue Clamav clamav,
        @DefaultValue Drive drive
) {

    /** Encabezado de los PDF. Solo el nombre es obligatorio. */
    public record Empresa(@DefaultValue("LLANOLAT") String nombre, String nit, String direccion, String telefono) {}

    /**
     * Antivirus ClamAV (servicio clamd). Con socket se usa el socket Unix; si no, host:puerto.
     * Si esta habilitado y no responde, la subida se RECHAZA (nunca se guarda algo sin escanear).
     */
    public record Clamav(
            @DefaultValue("true") boolean habilitado,
            @DefaultValue("127.0.0.1") String host,
            @DefaultValue("3310") int puerto,
            String socket,
            @DefaultValue("30s") Duration timeout) {}

    /**
     * Google Drive (API v3, OAuth con alcance drive.file). {@code redirectUri} es la URL de /drive/callback tal como se
     * registro en Google Cloud; {@code retorno} (opcional) es la pagina del dashboard a la que se vuelve al terminar.
     * Las demas URL se pueden cambiar solo para pruebas.
     */
    public record Drive(
            String clientId,
            String clientSecret,
            String redirectUri,
            String retorno,
            @DefaultValue("https://accounts.google.com/o/oauth2/v2/auth") String authUrl,
            @DefaultValue("https://oauth2.googleapis.com/token") String tokenUrl,
            @DefaultValue("https://www.googleapis.com") String apiUrl,
            @DefaultValue("SILA-respaldo") String carpeta,
            @DefaultValue("60s") Duration intervalo) {

        public boolean configurado() {
            return clientId != null && !clientId.isBlank() && clientSecret != null && !clientSecret.isBlank()
                    && redirectUri != null && !redirectUri.isBlank();
        }
    }
}
