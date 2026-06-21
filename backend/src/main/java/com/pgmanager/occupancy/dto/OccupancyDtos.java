package com.pgmanager.occupancy.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.time.LocalDate;

public final class OccupancyDtos {
    private OccupancyDtos() {
    }

    public record BedAssignRequest(
            @NotNull Long partyId,
            @NotNull Long bedFacilityId,
            LocalDate fromDate,
            @DecimalMin("0") BigDecimal monthlyRent,
            @DecimalMin("0") BigDecimal securityDeposit,
            LocalDate expectedCheckoutDate
    ) {}

    public record BedTransferRequest(@NotNull Long partyId, @NotNull Long newBedFacilityId, LocalDate transferDate) {
    }

    public record CheckoutRequest(@NotNull Long partyId, LocalDate checkoutDate) {
    }

    public record OccupancyResponse(
            Long facilityPartyId, Long partyId, Long facilityId,
            String roleTypeId, LocalDate fromDate, LocalDate thruDate,
            BigDecimal monthlyRent, BigDecimal securityDeposit,
            LocalDate expectedCheckoutDate
    ) {}
}
