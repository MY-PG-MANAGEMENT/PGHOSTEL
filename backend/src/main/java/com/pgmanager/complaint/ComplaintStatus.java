package com.pgmanager.complaint;

import java.util.List;
import java.util.Set;

/** String constants for complaint status + priority (no master tables, matching the expenses module style). */
public final class ComplaintStatus {
    public static final String OPEN = "OPEN";
    public static final String IN_PROGRESS = "IN_PROGRESS";
    public static final String RESOLVED = "RESOLVED";
    public static final String CLOSED = "CLOSED";

    public static final Set<String> ALL = Set.of(OPEN, IN_PROGRESS, RESOLVED, CLOSED);

    public static final String PRIORITY_LOW = "LOW";
    public static final String PRIORITY_MEDIUM = "MEDIUM";
    public static final String PRIORITY_HIGH = "HIGH";
    public static final Set<String> PRIORITIES = Set.of(PRIORITY_LOW, PRIORITY_MEDIUM, PRIORITY_HIGH);

    /** Tenant-selectable complaint categories. */
    public static final List<String> CATEGORIES =
            List.of("ELECTRICAL", "PLUMBING", "CLEANING", "FURNITURE", "INTERNET", "FOOD", "SECURITY", "OTHER");

    private ComplaintStatus() {}
}
