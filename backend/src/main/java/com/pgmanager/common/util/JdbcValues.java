package com.pgmanager.common.util;

/**
 * Coercions for values read out of a {@code JdbcTemplate} row map, where the runtime type
 * depends on the driver rather than the column definition.
 *
 * <p>The one that bites: MySQL Connector/J maps {@code TINYINT(1)} to {@link Boolean}
 * (its {@code tinyInt1isBit} default), so a plain {@code (Number)} cast on a boolean flag
 * column throws {@link ClassCastException} — but the same column read through
 * {@code COALESCE(flag, 1)} or {@code SUM(flag)} comes back as a {@link Number}. Route
 * every boolean-flag read through {@link #toBoolean} instead of casting.
 */
public final class JdbcValues {
    private JdbcValues() {
    }

    /** Reads a boolean flag column ({@code TINYINT(1)}), returning {@code fallback} when NULL. */
    public static boolean toBoolean(Object value, boolean fallback) {
        if (value == null) return fallback;
        if (value instanceof Boolean b) return b;
        if (value instanceof Number n) return n.intValue() != 0;
        String text = value.toString().trim();
        return "1".equals(text) || "true".equalsIgnoreCase(text) || "y".equalsIgnoreCase(text);
    }

    /** Reads an integer column, returning {@code fallback} when NULL or non-numeric. */
    public static int toInt(Object value, int fallback) {
        if (value instanceof Number n) return n.intValue();
        if (value instanceof Boolean b) return b ? 1 : 0;
        return fallback;
    }
}
