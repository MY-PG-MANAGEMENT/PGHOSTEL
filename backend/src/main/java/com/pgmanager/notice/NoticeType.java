package com.pgmanager.notice;

import java.util.Set;

/** Notice categories surfaced in the tenant app (string constants; no master table). */
public final class NoticeType {
    public static final String ANNOUNCEMENT = "ANNOUNCEMENT";
    public static final String RENT_REMINDER = "RENT_REMINDER";
    public static final String MAINTENANCE = "MAINTENANCE";
    public static final String WATER_SHUTDOWN = "WATER_SHUTDOWN";
    public static final String POWER_SHUTDOWN = "POWER_SHUTDOWN";

    public static final Set<String> ALL =
            Set.of(ANNOUNCEMENT, RENT_REMINDER, MAINTENANCE, WATER_SHUTDOWN, POWER_SHUTDOWN);

    private NoticeType() {}
}
