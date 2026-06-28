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
import com.pgmanager.occupancy.dto.OccupancyDtos.TransferResult;
import com.pgmanager.security.CurrentUser;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
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
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/occupancy")
@RequiredArgsConstructor
public class OccupancyController {
    private final OccupancyService occupancyService;
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;

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
    ApiResponse<OccupancyResponse> tempStay(@Valid @RequestBody TempStayRequest request) {
        return ApiResponse.ok("Temporary stay started",
                occupancyService.tempStay(currentUser.organizationId(), currentUser.userLoginId(), request));
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
                request.monthlyRent(), request.securityDeposit(), request.expectedCheckoutDate());
        OccupancyResponse occupancy = occupancyService.assign(org, user, assignReq);
        bootstrapBilling(org, request.partyId(), occupancy);
        return ApiResponse.ok("Temporary stay made permanent",
                Map.of("mode", "ASSIGNED", "fromDate", String.valueOf(occupancy.fromDate())));
    }

    @PostMapping("/checkout")
    ApiResponse<OccupancyResponse> checkout(@Valid @RequestBody CheckoutRequest request) {
        return ApiResponse.ok("Checkout completed", occupancyService.checkout(currentUser.organizationId(), currentUser.userLoginId(), request));
    }

    @PutMapping("/expected-checkout")
    @Transactional
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

    @GetMapping("/history/{partyId}")
    ApiResponse<List<OccupancyResponse>> history(@PathVariable Long partyId) {
        return ApiResponse.ok(occupancyService.history(currentUser.organizationId(), partyId));
    }

    /**
     * Ensures the tenant has a billing account and a first invoice for the move-in month.
     * Shared by the assign and make-permanent flows.
     */
    private void bootstrapBilling(Long org, Long partyId, OccupancyResponse occupancy) {
        List<Map<String, Object>> baRows = jdbc.queryForList(
                "SELECT billing_account_id FROM billing_account WHERE organization_id=? AND party_id=? AND status='ACTIVE' LIMIT 1",
                org, partyId);
        Long baId;
        if (baRows.isEmpty()) {
            jdbc.update("INSERT INTO billing_account(organization_id,party_id,currency_code,status,advance_balance,created_at,updated_at,version) " +
                    "VALUES(?,?,'INR','ACTIVE',0,?,?,0)", org, partyId, LocalDateTime.now(), LocalDateTime.now());
            baId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        } else {
            baId = ((Number) baRows.getFirst().get("billing_account_id")).longValue();
        }

        LocalDate moveIn = occupancy.fromDate() != null ? occupancy.fromDate() : LocalDate.now();
        LocalDate invoiceMonth = moveIn.withDayOfMonth(1);
        Long exists = jdbc.queryForObject(
                "SELECT COUNT(*) FROM invoice WHERE billing_account_id=? AND invoice_month=?",
                Long.class, baId, invoiceMonth);
        if (exists == null || exists == 0) {
            BigDecimal rent = occupancy.monthlyRent() != null ? occupancy.monthlyRent() : BigDecimal.ZERO;
            String invNum = "INV-" + org + "-" + baId + "-" + invoiceMonth.toString().substring(0, 7).replace("-", "");
            jdbc.update("INSERT INTO invoice(organization_id,billing_account_id,invoice_number,invoice_month,issue_date,due_date," +
                            "total_amount,paid_amount,status,created_at,updated_at,version) VALUES(?,?,?,?,?,?,?,0,'PENDING',?,?,0)",
                    org, baId, invNum, invoiceMonth, moveIn, moveIn, rent, LocalDateTime.now(), LocalDateTime.now());
            Long invoiceId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
            if (rent.compareTo(BigDecimal.ZERO) > 0) {
                jdbc.update("INSERT INTO invoice_item(invoice_id,item_type_id,description,amount,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                        invoiceId, "MONTHLY_RENT", "Monthly Rent", rent, LocalDateTime.now(), LocalDateTime.now());
            }
        }
    }

    public record ExpectedCheckoutRequest(@NotNull Long partyId, String expectedCheckoutDate) {}
}
