package com.pgmanager.occupancy.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.time.LocalDate;

public final class OccupancyDtos {
    private OccupancyDtos() {
    }

    /**
     * {@code monthlyRent} is the all-in monthly amount (base rent + AC).
     * {@code acCharges} only annotates how much of it is the AC premium so
     * invoices can itemize the breakdown — it is never added on top.
     */
    public record BedAssignRequest(
            @NotNull Long partyId,
            @NotNull Long bedFacilityId,
            LocalDate fromDate,
            @DecimalMin("0") BigDecimal monthlyRent,
            @DecimalMin("0") BigDecimal securityDeposit,
            LocalDate expectedCheckoutDate,
            @DecimalMin("0") BigDecimal acCharges
    ) {
        public BedAssignRequest(Long partyId, Long bedFacilityId, LocalDate fromDate,
                                BigDecimal monthlyRent, BigDecimal securityDeposit,
                                LocalDate expectedCheckoutDate) {
            this(partyId, bedFacilityId, fromDate, monthlyRent, securityDeposit, expectedCheckoutDate, null);
        }
    }

    public record BedTransferRequest(
            @NotNull Long partyId,
            @NotNull Long newBedFacilityId,
            LocalDate transferDate,
            @DecimalMin("0") BigDecimal monthlyRent
    ) {}

    /**
     * {@code amount} is the (editable) total charge for the temporary stay — the app
     * computes it as {@code days * perDayPrice} (per-day rate from Price Master) and lets
     * the owner override it. It is stored on the occupancy's {@code monthly_rent} column
     * (reused) and billed as a single invoice. {@code expectedCheckoutDate} is the planned
     * check-out; the actual check-out is written to {@code thru_date} when the stay ends.
     */
    public record TempStayRequest(
            @NotNull Long partyId,
            @NotNull Long bedFacilityId,
            LocalDate fromDate,
            LocalDate expectedCheckoutDate,
            @DecimalMin("0") BigDecimal amount,
            // Bed allocation only: the future permanent monthly rent + deposit captured
            // up front, stored on the row and prefilled when converting to permanent.
            @DecimalMin("0") BigDecimal monthlyRent,
            @DecimalMin("0") BigDecimal securityDeposit
    ) {
        public TempStayRequest(Long partyId, Long bedFacilityId, LocalDate fromDate) {
            this(partyId, bedFacilityId, fromDate, null, null, null, null);
        }
    }

    /**
     * Edits an active temporary stay: change the planned check-out, the (editable) total
     * amount, and optionally move to a different bed. The check-in date is not editable
     * here (it anchors the stay's invoice) — end and re-create to change it.
     */
    public record TempStayUpdateRequest(
            LocalDate expectedCheckoutDate,
            @DecimalMin("0") BigDecimal amount,
            Long bedFacilityId
    ) {}

    public record EndTempStayRequest(@NotNull Long partyId, LocalDate endDate) {}

    /**
     * {@code refundAmount} is the optional security-deposit refund the owner hands
     * back at checkout. When present (&gt; 0) it is recorded as a DEPOSIT_REFUND
     * expense (money-out). Must not exceed the deposit held on the occupancy.
     */
    public record CheckoutRequest(@NotNull Long partyId, LocalDate checkoutDate,
                                  @DecimalMin("0") BigDecimal refundAmount,
                                  String refundMethod, String refundNotes) {
        public CheckoutRequest(Long partyId, LocalDate checkoutDate) {
            this(partyId, checkoutDate, null, null, null);
        }
    }

    public record OccupancyResponse(
            Long facilityPartyId, Long partyId, Long facilityId,
            String roleTypeId, LocalDate fromDate, LocalDate thruDate,
            BigDecimal monthlyRent, BigDecimal securityDeposit,
            LocalDate expectedCheckoutDate, BigDecimal acCharges
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
