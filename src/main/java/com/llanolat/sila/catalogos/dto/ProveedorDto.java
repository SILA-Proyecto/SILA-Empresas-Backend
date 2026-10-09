package com.llanolat.sila.catalogos.dto;


/** Fila de vw_proveedores. */
public record ProveedorDto(
        Long idProveedor,
        String tipoDocumento,
        String numeroDocumento,
        String nombre,
        String telefono,
        String tipoProveedor,
        Boolean activo
) {}
