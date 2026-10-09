package com.llanolat.sila.infra;

import java.util.List;

/**
 * Envoltura de toda lista paginada. Es el contrato del dashboard
 * (core/api/page.models.ts): {items, total, page, size}, con page base 0.
 */
public record Page<T>(List<T> items, long total, int page, int size) {}
