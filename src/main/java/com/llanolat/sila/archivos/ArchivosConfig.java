package com.llanolat.sila.archivos;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/** Activa las tareas programadas (reintento de PDF faltantes y envio a Drive). */
@Configuration
@EnableScheduling
public class ArchivosConfig {}
