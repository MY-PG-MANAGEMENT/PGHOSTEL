package com.pgmanager.dashboard;

import java.math.BigDecimal;

public record DashboardResponse(
        long totalBeds,
        long occupiedBeds,
        long vacantBeds,
        long totalTenants,
        BigDecimal pendingRent,
        BigDecimal revenue
) {
}
