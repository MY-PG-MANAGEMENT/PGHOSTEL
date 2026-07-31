package com.pgmanager.common.util;

/**
 * Coercions for values read out of a {@code JdbcTemplate} row map, where the runtime type
 * depends on the driver rather than the column definition.
 *
 * <p>The one that bites: a {@code BOOLEAN} column comes back as a {@link Boolean}, so a plain
 * {@code (Number)} cast on a boolean flag throws {@link ClassCastException} — but the same
 * column read through {@code COALESCE}, {@code SUM(...)} or a {@code CASE} comes back as a
 * {@link Number}. So neither cast is safe on its own, and which one you get depends on the
 * query rather than the column. Route every boolean-flag read through {@link #toBoolean}.
 *
 * <p>It bites late, too: the wrong cast only throws once a row actually exists, so the bug
 * hides behind every "no row → defaults" branch until an org saves a setting.
 *
 * <p>The numeric and string branches below are kept deliberately after the move off MySQL,
 * where {@code TINYINT(1)} made the Number case the common one: the aggregate forms still
 * produce it, and narrowing this to Boolean-only would fail exactly where it is hardest to see.
 */
public final class JdbcValues {
    private JdbcValues() {
    }

    /** Reads a boolean flag column, returning {@code fallback} when NULL. */
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
