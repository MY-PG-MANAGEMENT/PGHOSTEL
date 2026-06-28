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

    public record BedTransferRequest(
            @NotNull Long partyId,
            @NotNull Long newBedFacilityId,
            LocalDate transferDate,
            @DecimalMin("0") BigDecimal monthlyRent
    ) {}

    public record TempStayRequest(
            @NotNull Long partyId,
            @NotNull Long bedFacilityId,
            LocalDate fromDate
    ) {}

    public record EndTempStayRequest(@NotNull Long partyId, LocalDate endDate) {}

    public record CheckoutRequest(@NotNull Long partyId, LocalDate checkoutDate) {
    }

    public record OccupancyResponse(
            Long facilityPartyId, Long partyId, Long facilityId,
            String roleTypeId, LocalDate fromDate, LocalDate thruDate,
            BigDecimal monthlyRent, BigDecimal securityDeposit,
            LocalDate expectedCheckoutDate
    ) {}

    public record ScheduledTransferResponse(
            Long scheduledBedTransferId, Long partyId,
            Long fromBedFacilityId, Long toBedFacilityId,
            LocalDate effectiveDate, BigDecimal newMonthlyRent, BigDecimal newSecurityDeposit,
            String status, String note
    ) {}

    /**
     * Outcome of a transfer request. {@code mode} is "APPLIED" when the move happened
     * immediately (same sharing type) — {@code occupancy} is populated. It is
     * "SCHEDULED" when the move was deferred to the next billing cycle (different
     * sharing type) — {@code scheduled} is populated.
     */
    public record TransferResult(
            String mode,
            OccupancyResponse occupancy,
            ScheduledTransferResponse scheduled
    ) {}
}
