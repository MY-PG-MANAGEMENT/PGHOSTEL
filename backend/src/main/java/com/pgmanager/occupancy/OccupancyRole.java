package com.pgmanager.occupancy;

public final class OccupancyRole {
    public static final String TENANT = "TENANT";
    public static final String OCCUPANT = "OCCUPANT";

    /**
     * A tenant physically placed in a bed on a temporary basis (e.g. while their
     * intended bed is freed up). Marks the bed as occupied for availability, but is
     * deliberately ignored by billing/invoice generation — no rent is charged for a
     * temporary stay. Ended via "move back" or converted into a real OCCUPANT.
     */
    public static final String TEMP_OCCUPANT = "TEMP_OCCUPANT";

    private OccupancyRole() {
    }
}
