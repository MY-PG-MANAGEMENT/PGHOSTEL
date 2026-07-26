package com.pgmanager.occupancy;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedAssignRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedTransferRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.CheckoutRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.EndTempStayRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.OccupancyResponse;
import com.pgmanager.occupancy.dto.OccupancyDtos.ScheduledTransferResponse;
import com.pgmanager.occupancy.dto.OccupancyDtos.TempStayRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.TempStayUpdateRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.TransferResult;
import com.pgmanager.billing.MoveInBillingService;
import com.pgmanager.common.cache.EvictOccupancyCaches;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.security.PropertyAccessGuard;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/occupancy")
@RequiredArgsConstructor
public class OccupancyController {
    private final OccupancyService occupancyService;
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;
    private final MoveInBillingService moveInBillingService;
    private final com.pgmanager.billing.CheckoutInvoiceService checkoutInvoiceService;
    private final PropertyAccessGuard propertyAccessGuard;

    @PostMapping("/assign-bed")
    @Transactional
    ApiResponse<OccupancyResponse> assign(@Valid @RequestBody BedAssignRequest request) {
        Long org = currentUser.organizationId();
        OccupancyResponse occupancy = occupancyService.assign(org, currentUser.userLoginId(), request);
        bootstrapBilling(org, request.partyId(), occupancy);
        return ApiResponse.ok("Bed assigned", occupancy);
    }

    @PostMapping("/transfer-bed")
    ApiResponse<TransferResult> transfer(@Valid @RequestBody BedTransferRequest request) {
        TransferResult result = occupancyService.transfer(currentUser.organizationId(), currentUser.userLoginId(), request);
        String msg = "APPLIED".equals(result.mode())
                ? "Bed transferred"
                : "Transfer scheduled for " + result.scheduled().effectiveDate();
        return ApiResponse.ok(msg, result);
    }

    @GetMapping("/scheduled-transfers/{partyId}")
    ApiResponse<List<ScheduledTransferResponse>> scheduledTransfers(@PathVariable Long partyId) {
        return ApiResponse.ok(occupancyService.pendingTransfers(currentUser.organizationId(), partyId));
    }

    @DeleteMapping("/scheduled-transfers/{id}")
    ApiResponse<Void> cancelScheduledTransfer(@PathVariable Long id) {
        occupancyService.cancelScheduledTransfer(currentUser.organizationId(), currentUser.userLoginId(), id);
        return ApiResponse.ok("Scheduled transfer cancelled", null);
    }

    @PostMapping("/temp-stay")
    @Transactional
    ApiResponse<OccupancyResponse> tempStay(@Valid @RequestBody TempStayRequest request) {
        Long org = currentUser.organizationId();
        OccupancyResponse occupancy = occupancyService.tempStay(org, currentUser.userLoginId(), request);
        // Bill the one-time stay charge as a single invoice (no-op when amount is absent).
        // The owner collects it later from the temporary-stay card's Pay action.
        moveInBillingService.bootstrapTempStay(org, request.partyId(), occupancy.fromDate(), request.amount());
        return ApiResponse.ok("Temporary stay started", occupancy);
    }

    @PutMapping("/temp-stay/{facilityPartyId}")
    @Transactional
    ApiResponse<OccupancyResponse> updateTempStay(@PathVariable Long facilityPartyId,
                                                  @Valid @RequestBody TempStayUpdateRequest request) {
        Long org = currentUser.organizationId();
        OccupancyResponse occupancy = occupancyService.updateTempStay(org, currentUser.userLoginId(), facilityPartyId, request);
        // Re-bill the (editable) stay charge onto the single temp invoice.
        moveInBillingService.updateTempStayInvoice(org, occupancy.partyId(), occupancy.fromDate(), request.amount());
        return ApiResponse.ok("Temporary stay updated", occupancy);
    }

    @PostMapping("/temp-stay/end")
    ApiResponse<OccupancyResponse> endTempStay(@Valid @RequestBody EndTempStayRequest request) {
        return ApiResponse.ok("Temporary stay ended",
                occupancyService.endTempStay(currentUser.organizationId(), currentUser.userLoginId(), request));
    }

    /**
     * Converts a temporary stay into a permanent bed.
     * <ul>
     *   <li><b>New tenant</b> (no existing bed) — a fresh assignment whose billing is
     *       anchored to the <i>temporary start date</i> (the join date), not the day
     *       they were made permanent. First invoice and cycle follow that date.</li>
     *   <li><b>Existing tenant</b> (already has a bed) — treated as a transfer to the
     *       chosen bed, so their existing payment cycle is preserved (same/different
     *       sharing rules apply).</li>
     * </ul>
     */
    @PostMapping("/temp-stay/make-permanent")
    @Transactional
    ApiResponse<Map<String, Object>> makePermanent(@Valid @RequestBody BedAssignRequest request) {
        Long org = currentUser.organizationId();
        Long user = currentUser.userLoginId();
        // Business rule: the temporary-stay/allocation invoice must be fully paid before
        // the guest can be moved into a permanent bed. Checked before anything is mutated.
        if (moveInBillingService.outstandingTempBalance(org, request.partyId())
                .compareTo(java.math.BigDecimal.ZERO) > 0) {
            throw new com.pgmanager.common.exception.BadRequestException(
                    "Collect the pending temporary invoice amount before assigning a permanent bed.");
        }
        boolean existing = occupancyService.hasActiveOccupant(org, request.partyId());
        // End the temporary stay first; its start date is the billing anchor for a new tenant.
        OccupancyResponse temp = occupancyService.endTempStay(org, user, new EndTempStayRequest(request.partyId(), LocalDate.now()));

        if (existing) {
            TransferResult result = occupancyService.transfer(org, user,
                    new BedTransferRequest(request.partyId(), request.bedFacilityId(), null, request.monthlyRent()));
            return ApiResponse.ok("Temporary stay made permanent", Map.of("mode", result.mode()));
        }

        LocalDate anchor = temp.fromDate() != null ? temp.fromDate() : LocalDate.now();
        BedAssignRequest assignReq = new BedAssignRequest(request.partyId(), request.bedFacilityId(), anchor,
                request.monthlyRent(), request.securityDeposit(), request.expectedCheckoutDate(), request.acCharges());
        OccupancyResponse occupancy = occupancyService.assign(org, user, assignReq);
        bootstrapBilling(org, request.partyId(), occupancy);
        // Bed allocation (no planned checkout): carry the allocation payment onto the
        // move-in invoice as an advance credit and void the superseded TEMP invoice.
        if (temp.expectedCheckoutDate() == null) {
            moveInBillingService.carryTempCreditToMoveIn(org, request.partyId(), anchor);
        }
        return ApiResponse.ok("Temporary stay made permanent",
                Map.of("mode", "ASSIGNED", "fromDate", String.valueOf(occupancy.fromDate())));
    }

    @PostMapping("/checkout")
    ApiResponse<OccupancyResponse> checkout(@Valid @RequestBody CheckoutRequest request) {
        return ApiResponse.ok("Checkout completed", occupancyService.checkout(currentUser.organizationId(), currentUser.userLoginId(), request));
    }

    /**
     * Which of the tenant's pending invoices checkout on {@code checkoutDate} would delete
     * outright (the next-cycle invoice raised ahead of its due date). The checkout screen
     * calls this so it can leave those out of "settle dues" instead of offering Pay /
     * Write Off on a month the tenant is not staying — the backend stays the authority on
     * the rule, so the list and the delete can never drift apart.
     */
    @GetMapping("/checkout-preview")
    ApiResponse<Map<String, Object>> checkoutPreview(@RequestParam Long partyId,
                                                     @RequestParam(required = false) String checkoutDate) {
        LocalDate date;
        try {
            date = checkoutDate == null || checkoutDate.isBlank() ? LocalDate.now() : LocalDate.parse(checkoutDate);
        } catch (Exception e) {
            throw new com.pgmanager.common.exception.BadRequestException("Invalid date format; expected YYYY-MM-DD");
        }
        List<Map<String, Object>> items = checkoutInvoiceService
                .previewUnconsumedInvoices(currentUser.organizationId(), partyId, date)
                .stream()
                .map(invoice -> Map.of(
                        "invoiceId", (Object) invoice.invoiceId(),
                        "invoiceNumber", String.valueOf(invoice.invoiceNumber()),
                        "dueDate", String.valueOf(invoice.dueDate()),
                        "amount", invoice.amount()))
                .toList();
        return ApiResponse.ok(Map.of("checkoutDate", date.toString(), "droppedInvoices", items));
    }

    @PutMapping("/expected-checkout")
    @Transactional
    @EvictOccupancyCaches
    ApiResponse<Void> setExpectedCheckout(@Valid @RequestBody ExpectedCheckoutRequest request) {
        Long org = currentUser.organizationId();
        LocalDate checkoutDate = null;
        if (request.expectedCheckoutDate() != null && !request.expectedCheckoutDate().isBlank()) {
            try {
                checkoutDate = LocalDate.parse(request.expectedCheckoutDate());
            } catch (Exception e) {
                throw new com.pgmanager.common.exception.BadRequestException("Invalid date format; expected YYYY-MM-DD");
            }
        }
        if (checkoutDate != null) {
            List<Map<String, Object>> fp = jdbc.queryForList(
                    "SELECT from_date FROM facility_party WHERE organization_id=? AND party_id=? AND role_type_id='OCCUPANT' AND thru_date IS NULL",
                    org, request.partyId());
            if (!fp.isEmpty()) {
                LocalDate fromDate = ((java.sql.Date) fp.get(0).get("from_date")).toLocalDate();
                int moveInDay = fromDate.getDayOfMonth();
                LocalDate today = LocalDate.now();
                int daysInThisMonth = today.lengthOfMonth();
                LocalDate thisMonthDue = today.withDayOfMonth(Math.min(moveInDay, daysInThisMonth));
                LocalDate nextDue = !thisMonthDue.isAfter(today)
                        ? today.plusMonths(1).withDayOfMonth(Math.min(moveInDay, today.plusMonths(1).lengthOfMonth()))
                        : thisMonthDue;
                if (!checkoutDate.isBefore(nextDue)) {
                    throw new com.pgmanager.common.exception.BadRequestException(
                            "Expected checkout date must be before next payment date (" + nextDue + ")");
                }
            }
        }
        int updated = jdbc.update(
                "UPDATE facility_party SET expected_checkout_date=?,updated_at=NOW() " +
                "WHERE organization_id=? AND party_id=? AND role_type_id='OCCUPANT' AND thru_date IS NULL",
                checkoutDate, org, request.partyId());
        if (updated == 0) throw new NotFoundException("Active bed assignment not found for this tenant");
        return ApiResponse.ok("Expected checkout date updated", null);
    }

    // Change the tenant's master monthly rent. This updates the recurring rent
    // on the active occupancy row only — the current month's invoice (already
    // generated) is untouched, so the new rent takes effect from the next
    // billing cycle when /generate-invoices reads facility_party.monthly_rent.
    @PutMapping("/monthly-rent")
    @Transactional
    @EvictOccupancyCaches
    ApiResponse<Void> changeRent(@Valid @RequestBody ChangeRentRequest request) {
        Long org = currentUser.organizationId();
        int updated = jdbc.update(
                "UPDATE facility_party SET monthly_rent=?,updated_at=NOW() " +
                "WHERE organization_id=? AND party_id=? AND role_type_id='OCCUPANT' AND thru_date IS NULL",
                request.monthlyRent(), org, request.partyId());
        if (updated == 0) throw new NotFoundException("Active bed assignment not found for this tenant");
        return ApiResponse.ok("Monthly rent updated — applies from the next billing cycle", null);
    }

    @GetMapping("/history/{partyId}")
    ApiResponse<List<OccupancyResponse>> history(@PathVariable Long partyId) {
        return ApiResponse.ok(occupancyService.history(currentUser.organizationId(), partyId));
    }

    /**
     * Ensures the tenant has a billing account and a first invoice for the move-in month.
     * Shared by the assign and make-permanent flows; delegates to {@link MoveInBillingService}
     * so the in-app and CSV-import paths produce identical billing.
     */
    private void bootstrapBilling(Long org, Long partyId, OccupancyResponse occupancy) {
        moveInBillingService.bootstrapMoveIn(org, partyId, occupancy.fromDate(),
                occupancy.monthlyRent(), occupancy.acCharges(), occupancy.securityDeposit());
    }

    public record ExpectedCheckoutRequest(@NotNull Long partyId, String expectedCheckoutDate) {}
    public record ChangeRentRequest(@NotNull Long partyId, @NotNull @DecimalMin("0") BigDecimal monthlyRent) {}
}
