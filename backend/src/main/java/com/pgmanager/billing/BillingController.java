package com.pgmanager.billing;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.notification.NotificationService;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.security.PropertyAccessGuard;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/billing")
@RequiredArgsConstructor
public class BillingController {
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;
    private final NotificationService notificationService;
    private final InvoiceGenerationService invoiceGenerationService;
    private final BillingConfigService billingConfigService;
    private final AuditService auditService;
    private final PropertyAccessGuard propertyAccessGuard;

    @GetMapping("/dashboard")
    ApiResponse<Map<String, Object>> dashboard(@RequestParam(required = false) Long propertyId) {
        // Scope to what this login may see: unchanged for an owner; a property-scoped
        // login gets their own property substituted in, or a 403/400.
        propertyId = propertyAccessGuard.resolvePropertyId(propertyId);
        Long org = currentUser.organizationId();
        String payProp       = partyPropFilter(null, propertyId);
        String payAliasProp  = partyPropFilter("p",  propertyId);
        String invProp       = partyPropFilter("ba", propertyId);
        String invScalarProp = propertyId != null
                ? " AND billing_account_id IN (SELECT ba.billing_account_id FROM billing_account ba WHERE ba.organization_id=? AND ba.party_id IN (SELECT fp.party_id FROM facility_party fp WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT'))"
                : "";
        Object[] pp2 = propertyId != null ? new Object[]{org, propertyId} : new Object[0];
        Object[] pp3 = propertyId != null ? new Object[]{org, org, propertyId} : new Object[0];
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("totalCollection", amount(
                "SELECT COALESCE(SUM(amount),0) FROM payment WHERE organization_id=? AND status='RECEIVED' AND payment_date BETWEEN DATE_TRUNC('month',CURRENT_DATE)::date AND (DATE_TRUNC('month',CURRENT_DATE) + INTERVAL '1 month - 1 day')::date" + payProp,
                cat(org, pp2)));
        result.put("totalCollectionCount", count(
                "SELECT COUNT(*) FROM payment WHERE organization_id=? AND status='RECEIVED' AND payment_date BETWEEN DATE_TRUNC('month',CURRENT_DATE)::date AND (DATE_TRUNC('month',CURRENT_DATE) + INTERVAL '1 month - 1 day')::date" + payProp,
                cat(org, pp2)));
        result.put("receivedToday", amount(
                "SELECT COALESCE(SUM(amount),0) FROM payment WHERE organization_id=? AND payment_date=CURRENT_DATE AND status='RECEIVED'" + payProp,
                cat(org, pp2)));
        result.put("outstandingToday", amount(
                "SELECT COALESCE(SUM(total_amount-paid_amount),0) FROM invoice WHERE organization_id=? AND due_date=CURRENT_DATE AND status IN ('PENDING','PARTIAL')" + invScalarProp,
                cat(org, pp3)));
        result.put("overdue", amount(
                "SELECT COALESCE(SUM(total_amount-paid_amount),0) FROM invoice WHERE organization_id=? AND due_date<CURRENT_DATE AND status IN ('PENDING','PARTIAL','OVERDUE')" + invScalarProp,
                cat(org, pp3)));
        result.put("recentPayments", jdbc.queryForList(
                "SELECT p.payment_id,p.party_id,p.amount,p.payment_mode,p.payment_date,p.reference_number,p.status,pr.full_name " +
                "FROM payment p JOIN person pr ON pr.party_id=p.party_id " +
                "WHERE p.organization_id=?" + payAliasProp + " ORDER BY p.payment_date DESC,p.payment_id DESC LIMIT 10",
                cat(org, pp2)));
        result.put("todayPayments", jdbc.queryForList(
                "SELECT p.payment_id,p.party_id,p.amount,p.payment_mode,p.payment_date,p.reference_number,p.status,COALESCE(pr.full_name,'') full_name " +
                "FROM payment p LEFT JOIN person pr ON pr.party_id=p.party_id " +
                "WHERE p.organization_id=? AND p.payment_date=CURRENT_DATE AND p.status='RECEIVED'" + payAliasProp + " ORDER BY p.payment_id DESC",
                cat(org, pp2)));
        result.put("outstandingTodayInvoices", jdbc.queryForList(
                "SELECT i.invoice_id,i.invoice_number,i.invoice_month,i.total_amount,i.paid_amount," +
                "(i.total_amount-i.paid_amount) balance,i.status,i.due_date,ba.party_id,p.full_name " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "JOIN person p ON p.party_id=ba.party_id " +
                "WHERE i.organization_id=? AND i.due_date=CURRENT_DATE AND i.status IN ('PENDING','PARTIAL')" + invProp + " ORDER BY i.invoice_id",
                cat(org, pp2)));
        result.put("overdueInvoices", jdbc.queryForList(
                "SELECT i.invoice_id,i.invoice_number,i.invoice_month,i.total_amount,i.paid_amount," +
                "(i.total_amount-i.paid_amount) balance,i.status,i.due_date,ba.party_id,p.full_name " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "JOIN person p ON p.party_id=ba.party_id " +
                "WHERE i.organization_id=? AND i.due_date<CURRENT_DATE AND i.status IN ('PENDING','PARTIAL','OVERDUE')" + invProp + " ORDER BY i.due_date,i.invoice_id",
                cat(org, pp2)));
        return ApiResponse.ok(result);
    }

    @GetMapping("/invoices")
    ApiResponse<Map<String, Object>> invoices(@RequestParam(required = false) String status,
                                               @RequestParam(required = false) Long partyId,
                                               @RequestParam(required = false) Long propertyId,
                                               @RequestParam(defaultValue = "0") int page,
                                               @RequestParam(defaultValue = "25") int size) {
        // Scope to what this login may see (see PropertyAccessGuard).
        propertyId = propertyAccessGuard.resolvePropertyId(propertyId);
        Long org = currentUser.organizationId();
        int safeSize = Math.min(Math.max(size, 1), 100);
        String statusFilter = (status == null || status.isBlank()) ? "" : " AND i.status=?";
        String partyFilter = partyId != null ? " AND ba.party_id=?" : "";
        String propFilter = partyPropFilter("ba", propertyId);
        java.util.List<Object> argList = new java.util.ArrayList<>();
        argList.add(org);
        if (status != null && !status.isBlank()) argList.add(status.toUpperCase());
        if (partyId != null) argList.add(partyId);
        if (propertyId != null) { argList.add(org); argList.add(propertyId); }
        argList.add(safeSize);
        argList.add(Math.max(page, 0) * safeSize);
        List<Map<String, Object>> items = jdbc.queryForList("SELECT i.invoice_id,i.invoice_number,i.invoice_month,i.issue_date,i.due_date," +
                "i.total_amount,i.paid_amount,(i.total_amount-i.paid_amount) balance,i.status,ba.party_id,p.full_name " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "JOIN person p ON p.party_id=ba.party_id WHERE i.organization_id=?" + statusFilter + partyFilter + propFilter +
                " ORDER BY i.due_date DESC LIMIT ? OFFSET ?", argList.toArray());
        return ApiResponse.ok(Map.of("items", items, "page", page, "size", safeSize));
    }

    @GetMapping("/invoices/{invoiceId}")
    ApiResponse<Map<String, Object>> invoice(@PathVariable Long invoiceId) {
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT i.*,ba.party_id,p.full_name,ba.advance_balance FROM invoice i " +
                        "JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id JOIN person p ON p.party_id=ba.party_id " +
                        "WHERE i.invoice_id=? AND i.organization_id=?", invoiceId, currentUser.organizationId());
        if (rows.isEmpty()) throw new NotFoundException("Invoice not found");
        Map<String, Object> result = new LinkedHashMap<>(rows.getFirst());
        result.put("items", jdbc.queryForList("SELECT invoice_item_id,item_type_id,description,amount FROM invoice_item WHERE invoice_id=?", invoiceId));
        result.put("payments", jdbc.queryForList("SELECT p.payment_id,p.amount,p.payment_mode,p.payment_date,p.reference_number " +
                "FROM payment_allocation a JOIN payment p ON p.payment_id=a.payment_id WHERE a.invoice_id=?", invoiceId));
        return ApiResponse.ok(result);
    }

    @GetMapping("/payments")
    ApiResponse<Map<String, Object>> payments(@RequestParam(required = false) Long partyId,
                                               @RequestParam(required = false) String fromDate,
                                               @RequestParam(required = false) String toDate,
                                               @RequestParam(required = false) Long propertyId,
                                               @RequestParam(defaultValue = "0") int page,
                                               @RequestParam(defaultValue = "200") int size) {
        // Scope to what this login may see (see PropertyAccessGuard).
        propertyId = propertyAccessGuard.resolvePropertyId(propertyId);
        Long org = currentUser.organizationId();
        int safeSize = Math.min(Math.max(size, 1), 500);
        String partyFilter = (partyId != null) ? " AND p.party_id=?" : "";
        String fromFilter  = (fromDate != null && !fromDate.isBlank()) ? " AND p.payment_date>=?" : "";
        String toFilter    = (toDate   != null && !toDate.isBlank())   ? " AND p.payment_date<=?" : "";
        String propFilter  = partyPropFilter("p", propertyId);
        java.util.List<Object> argList = new java.util.ArrayList<>();
        argList.add(org);
        if (partyId  != null) argList.add(partyId);
        if (fromDate != null && !fromDate.isBlank()) argList.add(fromDate);
        if (toDate   != null && !toDate.isBlank())   argList.add(toDate);
        if (propertyId != null) { argList.add(org); argList.add(propertyId); }
        argList.add(safeSize);
        argList.add(Math.max(page, 0) * safeSize);
        List<Map<String, Object>> items = jdbc.queryForList(
                "SELECT p.payment_id,p.party_id,p.amount,p.payment_mode,p.payment_date,p.reference_number,p.notes,p.status,pr.full_name " +
                "FROM payment p JOIN person pr ON pr.party_id=p.party_id WHERE p.organization_id=?" +
                partyFilter + fromFilter + toFilter + propFilter +
                " ORDER BY p.payment_date DESC,p.payment_id DESC LIMIT ? OFFSET ?", argList.toArray());
        return ApiResponse.ok(Map.of("items", items, "page", page, "size", safeSize));
    }

    @PostMapping("/payments")
    @Transactional
    ApiResponse<Map<String, Object>> collectPayment(@Valid @RequestBody PaymentRequest request) {
        Long org = currentUser.organizationId();
        // Replay check FIRST, before the balance guard below.
        //
        // A retry of a payment that settled the invoice in full leaves balance = 0, so
        // the "exceeds invoice balance" guard rejected the replay with a 400 and the
        // DuplicateKeyException branch further down was never reached. That is exactly
        // backwards: the idempotency key exists so a client that retries after a network
        // timeout gets the original receipt back, not an error telling it the invoice is
        // already paid. The catch below stays as the race backstop for two concurrent
        // replays, where both get past this lookup before either has inserted.
        List<Map<String, Object>> replay = jdbc.queryForList(
                "SELECT payment_id,amount,status FROM payment WHERE organization_id=? AND idempotency_key=?",
                org, request.idempotencyKey());
        if (!replay.isEmpty()) return ApiResponse.ok("Payment already recorded", replay.getFirst());

        List<Map<String, Object>> invoices = jdbc.queryForList("SELECT i.invoice_id,i.billing_account_id,i.total_amount,i.paid_amount,ba.party_id " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id WHERE i.invoice_id=? AND i.organization_id=? FOR UPDATE",
                request.invoiceId(), org);
        if (invoices.isEmpty()) throw new NotFoundException("Invoice not found");
        Map<String, Object> invoice = invoices.getFirst();
        BigDecimal balance = decimal(invoice.get("total_amount")).subtract(decimal(invoice.get("paid_amount")));
        if (request.amount().compareTo(balance) > 0) throw new BadRequestException("Payment exceeds invoice balance");
        String mode = request.paymentMode() == null ? "CASH" : request.paymentMode().toUpperCase();
        Long paymentId;
        try {
            paymentId = jdbc.queryForObject(
                    "INSERT INTO payment(organization_id,party_id,amount,payment_mode,payment_date,reference_number,notes," +
                            "idempotency_key,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,'RECEIVED',?,?) " +
                            "RETURNING payment_id",
                    Long.class, org, invoice.get("party_id"), request.amount(), mode,
                    request.paymentDate() == null ? LocalDate.now() : request.paymentDate(),
                    request.referenceNumber(), request.notes(), request.idempotencyKey(), LocalDateTime.now(), LocalDateTime.now());
        } catch (DuplicateKeyException duplicate) {
            return ApiResponse.ok("Payment already recorded", jdbc.queryForMap(
                    "SELECT payment_id,amount,status FROM payment WHERE organization_id=? AND idempotency_key=?",
                    org, request.idempotencyKey()));
        }
        jdbc.update("INSERT INTO payment_allocation(organization_id,payment_id,invoice_id,amount,allocated_at) VALUES(?,?,?,?,?)",
                org, paymentId, request.invoiceId(), request.amount(), LocalDateTime.now());
        BigDecimal paid = decimal(invoice.get("paid_amount")).add(request.amount());
        String status = paid.compareTo(decimal(invoice.get("total_amount"))) >= 0 ? "PAID" : "PARTIAL";
        jdbc.update("UPDATE invoice SET paid_amount=?,status=?,updated_at=?,version=version+1 WHERE invoice_id=?",
                paid, status, LocalDateTime.now(), request.invoiceId());
        Long partyId = ((Number) invoice.get("party_id")).longValue();
        notificationService.notifyPaymentReceipt(org, partyId, paymentId, request.amount());
        notificationService.notifyTenantPaymentReceipt(org, partyId, paymentId, request.amount(), mode);
        return ApiResponse.ok("Payment recorded", Map.of("paymentId", paymentId, "invoiceId", request.invoiceId(),
                "amount", request.amount(), "paymentMode", mode, "status", status, "receiptNumber", "RCP-" + paymentId));
    }

    @PostMapping("/payments/cash")
    @Transactional
    ApiResponse<Map<String, Object>> collectCash(@Valid @RequestBody CashPaymentRequest request) {
        return collectPayment(new PaymentRequest(request.invoiceId(), request.amount(), "CASH",
                request.paymentDate(), request.referenceNumber(), request.notes(), request.idempotencyKey()));
    }

    /**
     * Manual/fallback generation for the invoices that come due <em>today</em> — the tenants whose
     * billing anniversary is today's day-of-month, not the whole month. The daily
     * {@link InvoiceAutoGenerationScheduler} normally raises these ahead of the anniversary; this
     * endpoint is the on-demand equivalent for an org that has automation switched off (or a day
     * the scheduler missed). Delegates to {@link InvoiceGenerationService} so numbering /
     * due-date / line-item logic stays in one place. Idempotent per account+month.
     */
    @PostMapping("/generate-invoices")
    ApiResponse<Map<String, Object>> generateInvoices(@RequestParam(required = false) Long propertyId) {
        // Scope to what this login may see: unchanged for an owner; a property-scoped
        // login gets their own property substituted in, or a 403/400.
        propertyId = propertyAccessGuard.resolvePropertyId(propertyId);
        Long org = currentUser.organizationId();
        java.time.LocalDate today = java.time.LocalDate.now();
        InvoiceGenerationService.GenerationResult result =
                invoiceGenerationService.generateDueOn(org, today, propertyId);
        return ApiResponse.ok(Map.of("generated", result.generated(), "skipped", result.skipped(),
                "notDue", result.notDue(), "date", today.toString()));
    }

    @GetMapping("/config")
    ApiResponse<Map<String, Object>> getBillingConfig() {
        BillingConfigService.BillingConfig config = billingConfigService.get(currentUser.organizationId());
        return ApiResponse.ok(configPayload(config));
    }

    @PutMapping("/config")
    ApiResponse<Map<String, Object>> updateBillingConfig(@Valid @RequestBody BillingConfigRequest request) {
        BillingConfigService.BillingConfig config = billingConfigService.upsert(
                currentUser.organizationId(), request.invoiceLeadDays(),
                request.checkoutGraceDays() != null
                        ? request.checkoutGraceDays() : BillingConfigService.DEFAULT.checkoutGraceDays(),
                request.autoGenerateEnabled());
        return ApiResponse.ok("Billing settings updated", configPayload(config));
    }

    private Map<String, Object> configPayload(BillingConfigService.BillingConfig config) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("invoiceLeadDays", config.invoiceLeadDays());
        payload.put("checkoutGraceDays", config.checkoutGraceDays());
        payload.put("autoGenerateEnabled", config.autoGenerateEnabled());
        payload.put("minLeadDays", BillingConfigService.MIN_LEAD_DAYS);
        payload.put("maxLeadDays", BillingConfigService.MAX_LEAD_DAYS);
        payload.put("minGraceDays", BillingConfigService.MIN_GRACE_DAYS);
        payload.put("maxGraceDays", BillingConfigService.MAX_GRACE_DAYS);
        return payload;
    }

    @PostMapping("/advances")
    @Transactional
    ApiResponse<Map<String, Object>> addAdvance(@Valid @RequestBody AdvanceRequest request) {
        Long org = currentUser.organizationId();
        List<Map<String, Object>> accounts = jdbc.queryForList("SELECT billing_account_id,advance_balance FROM billing_account " +
                "WHERE billing_account_id=? AND organization_id=? FOR UPDATE", request.billingAccountId(), org);
        if (accounts.isEmpty()) throw new NotFoundException("Billing account not found");
        jdbc.update("INSERT INTO payment(organization_id,party_id,amount,payment_mode,payment_date,reference_number,notes,idempotency_key,status,created_at,updated_at) " +
                        "SELECT organization_id,party_id,?,'CASH',?,?,?,?, 'RECEIVED',?,? FROM billing_account WHERE billing_account_id=?",
                request.amount(), request.paymentDate() == null ? LocalDate.now() : request.paymentDate(), request.referenceNumber(),
                request.notes(), request.idempotencyKey(), LocalDateTime.now(), LocalDateTime.now(), request.billingAccountId());
        BigDecimal balance = decimal(accounts.getFirst().get("advance_balance")).add(request.amount());
        jdbc.update("UPDATE billing_account SET advance_balance=?,updated_at=?,version=version+1 WHERE billing_account_id=?", balance, LocalDateTime.now(), request.billingAccountId());
        return ApiResponse.ok(Map.of("billingAccountId", request.billingAccountId(), "advanceBalance", balance));
    }

    @GetMapping("/payments/{paymentId}/receipt")
    ApiResponse<Map<String, Object>> receipt(@PathVariable Long paymentId) {
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT p.payment_id,CONCAT('RCP-',p.payment_id) receipt_number,p.amount,p.payment_mode," +
                "p.payment_date,p.reference_number,p.notes,p.status,pr.full_name FROM payment p JOIN person pr ON pr.party_id=p.party_id " +
                "WHERE p.payment_id=? AND p.organization_id=?", paymentId, currentUser.organizationId());
        if (rows.isEmpty()) throw new NotFoundException("Payment not found");
        return ApiResponse.ok(rows.getFirst());
    }

    @PostMapping("/payments/{paymentId}/refunds")
    @Transactional
    ApiResponse<Map<String, Object>> refund(@PathVariable Long paymentId, @Valid @RequestBody RefundRequest request) {
        Long org = currentUser.organizationId();
        List<Map<String, Object>> payments = jdbc.queryForList("SELECT amount FROM payment WHERE payment_id=? AND organization_id=? FOR UPDATE", paymentId, org);
        if (payments.isEmpty()) throw new NotFoundException("Payment not found");
        BigDecimal refunded = amount("SELECT COALESCE(SUM(amount),0) FROM payment_refund WHERE organization_id=? AND payment_id=?", org, paymentId);
        if (refunded.add(request.amount()).compareTo(decimal(payments.getFirst().get("amount"))) > 0) throw new BadRequestException("Refund exceeds refundable amount");
        jdbc.update("INSERT INTO payment_refund(organization_id,payment_id,amount,refund_method,reference_number,reason,status,refunded_at,created_at,updated_at) " +
                        "VALUES(?,?,?,'CASH',?,?,'RECORDED',?,?,?)", org, paymentId, request.amount(), request.referenceNumber(), request.reason(),
                LocalDateTime.now(), LocalDateTime.now(), LocalDateTime.now());
        return ApiResponse.ok(Map.of("paymentId", paymentId, "refundedAmount", refunded.add(request.amount()), "method", "CASH"));
    }

    @PostMapping("/invoices/{invoiceId}/mark-paid")
    @Transactional
    ApiResponse<Map<String, Object>> markPaid(@PathVariable Long invoiceId) {
        Long org = currentUser.organizationId();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT i.invoice_id,i.billing_account_id,i.total_amount,i.paid_amount," +
                "(i.total_amount-i.paid_amount) balance,ba.party_id " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "WHERE i.invoice_id=? AND i.organization_id=? AND i.status IN ('PENDING','PARTIAL','OVERDUE') FOR UPDATE",
                invoiceId, org);
        if (rows.isEmpty()) throw new NotFoundException("Invoice not found or already settled");
        Map<String, Object> inv = rows.getFirst();
        BigDecimal balance = decimal(inv.get("balance"));
        Long partyId = ((Number) inv.get("party_id")).longValue();
        if (balance.compareTo(BigDecimal.ZERO) > 0) {
            String ikey = "checkout-markpaid-" + invoiceId + "-" + org;
            try {
                Long payId = jdbc.queryForObject(
                        "INSERT INTO payment(organization_id,party_id,amount,payment_mode,payment_date," +
                                "idempotency_key,status,created_at,updated_at) " +
                                "VALUES(?,?,?,'CASH',CURRENT_DATE,?,'RECEIVED',LOCALTIMESTAMP,LOCALTIMESTAMP) " +
                                "RETURNING payment_id",
                        Long.class, org, partyId, balance, ikey);
                jdbc.update("INSERT INTO payment_allocation(organization_id,payment_id,invoice_id,amount,allocated_at) " +
                        "VALUES(?,?,?,?,LOCALTIMESTAMP)", org, payId, invoiceId, balance);
            } catch (DuplicateKeyException ignored) {
            }
        }
        jdbc.update("UPDATE invoice SET paid_amount=total_amount,status='PAID',updated_at=LOCALTIMESTAMP,version=version+1 " +
                "WHERE invoice_id=? AND organization_id=?", invoiceId, org);
        return ApiResponse.ok("Invoice marked as paid", Map.of("invoiceId", invoiceId, "status", "PAID"));
    }

    @PostMapping("/invoices/{invoiceId}/write-off")
    @Transactional
    ApiResponse<Void> writeOff(@PathVariable Long invoiceId) {
        Long org = currentUser.organizationId();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT i.invoice_id,(i.total_amount-i.paid_amount) balance,ba.party_id " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "WHERE i.invoice_id=? AND i.organization_id=? AND i.status IN ('PENDING','PARTIAL','OVERDUE') FOR UPDATE",
                invoiceId, org);
        if (rows.isEmpty()) throw new NotFoundException("Invoice not found or already settled");
        BigDecimal balance = decimal(rows.getFirst().get("balance"));
        Long partyId = ((Number) rows.getFirst().get("party_id")).longValue();
        if (balance.compareTo(BigDecimal.ZERO) > 0) {
            String ikey = "checkout-writeoff-" + invoiceId + "-" + org;
            try {
                Long payId = jdbc.queryForObject(
                        "INSERT INTO payment(organization_id,party_id,amount,payment_mode,payment_date," +
                                "idempotency_key,status,created_at,updated_at) " +
                                "VALUES(?,?,?,'WRITE_OFF',CURRENT_DATE,?,'WRITTEN_OFF',LOCALTIMESTAMP,LOCALTIMESTAMP) " +
                                "RETURNING payment_id",
                        Long.class, org, partyId, balance, ikey);
                jdbc.update("INSERT INTO payment_allocation(organization_id,payment_id,invoice_id,amount,allocated_at) " +
                        "VALUES(?,?,?,?,LOCALTIMESTAMP)", org, payId, invoiceId, balance);
            } catch (DuplicateKeyException ignored) {
            }
        }
        jdbc.update("UPDATE invoice SET status='WRITTEN_OFF',updated_at=LOCALTIMESTAMP,version=version+1 " +
                "WHERE invoice_id=? AND organization_id=?", invoiceId, org);
        return ApiResponse.ok("Invoice written off", null);
    }

    // Delete = soft-cancel, and it is reversible via /restore below. Only a PENDING
    // invoice qualifies: a PARTIAL/OVERDUE/PAID one carries money or a chase history, so
    // it must go through write-off / refund instead — that keeps every payment_allocation
    // row attached to a live invoice. The row is never removed, so the
    // (billing_account_id, invoice_month) idempotency guard in
    // InvoiceGenerationService.createRecurringInvoice still sees it and will not
    // re-raise the month the owner just deleted.
    @DeleteMapping("/invoices/{invoiceId}")
    @Transactional
    ApiResponse<Void> deleteInvoice(@PathVariable Long invoiceId) {
        Long org = currentUser.organizationId();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT paid_amount,status FROM invoice " +
                "WHERE invoice_id=? AND organization_id=? FOR UPDATE",
                invoiceId, org);
        if (rows.isEmpty()) throw new NotFoundException("Invoice not found");
        Map<String, Object> inv = rows.getFirst();
        String status = String.valueOf(inv.get("status"));
        if ("CANCELLED".equals(status)) {
            return ApiResponse.ok("Invoice already cancelled", null);
        }
        if (!"PENDING".equals(status)) {
            throw new BadRequestException("Only a pending invoice can be deleted. This one is "
                    + status.toLowerCase() + " — write it off or refund it instead.");
        }
        // Belt and braces: PENDING should always mean nothing collected (a part-paid
        // invoice is PARTIAL), but never cancel money out from under an allocation.
        if (decimal(inv.get("paid_amount")).compareTo(BigDecimal.ZERO) > 0) {
            throw new BadRequestException("Cannot delete an invoice with collected payments — write it off instead");
        }
        jdbc.update("UPDATE invoice SET status='CANCELLED',updated_at=LOCALTIMESTAMP,version=version+1 " +
                "WHERE invoice_id=? AND organization_id=?", invoiceId, org);
        auditService.log(org, currentUser.userLoginId(), "INVOICE_CANCELLED", "INVOICE", invoiceId,
                "Pending invoice deleted (soft-cancelled)");
        return ApiResponse.ok("Invoice deleted", null);
    }

    // Undo of the delete above: CANCELLED → PENDING, putting the invoice back in the
    // dues lists. It returns to PENDING rather than OVERDUE even when the due date has
    // passed — every overdue read derives lateness from due_date < CURRENT_DATE over
    // status IN ('PENDING','PARTIAL','OVERDUE'), so a stale restored invoice shows as
    // overdue immediately with no status juggling here.
    @PostMapping("/invoices/{invoiceId}/restore")
    @Transactional
    ApiResponse<Map<String, Object>> restoreInvoice(@PathVariable Long invoiceId) {
        Long org = currentUser.organizationId();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT status FROM invoice WHERE invoice_id=? AND organization_id=? FOR UPDATE",
                invoiceId, org);
        if (rows.isEmpty()) throw new NotFoundException("Invoice not found");
        String status = String.valueOf(rows.getFirst().get("status"));
        if ("PENDING".equals(status)) {
            return ApiResponse.ok("Invoice already active", Map.of("invoiceId", invoiceId, "status", "PENDING"));
        }
        if (!"CANCELLED".equals(status)) {
            throw new BadRequestException("Only a deleted invoice can be restored. This one is " + status.toLowerCase() + ".");
        }
        jdbc.update("UPDATE invoice SET status='PENDING',updated_at=LOCALTIMESTAMP,version=version+1 " +
                "WHERE invoice_id=? AND organization_id=?", invoiceId, org);
        auditService.log(org, currentUser.userLoginId(), "INVOICE_RESTORED", "INVOICE", invoiceId,
                "Cancelled invoice restored to pending");
        return ApiResponse.ok("Invoice restored", Map.of("invoiceId", invoiceId, "status", "PENDING"));
    }

    // Override the charge breakdown of THIS month's invoice only — it never
    // touches the tenant's master rent (facility_party.monthly_rent). Editable
    // only while the invoice is still pending with nothing collected. Each
    // existing charge line (PG rent / AC charges / security deposit / …) is
    // re-priced individually and the invoice total is recomputed as their sum.
    // The security-deposit line is special: it also updates the master deposit
    // held on the occupancy row, since that's the figure the checkout screen
    // shows the owner to refund.
    @PatchMapping("/invoices/{invoiceId}/amount")
    @Transactional
    ApiResponse<Map<String, Object>> updateInvoiceAmount(@PathVariable Long invoiceId,
                                                         @Valid @RequestBody AmountRequest request) {
        Long org = currentUser.organizationId();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT i.paid_amount,i.status,ba.party_id FROM invoice i " +
                "JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "WHERE i.invoice_id=? AND i.organization_id=? FOR UPDATE",
                invoiceId, org);
        if (rows.isEmpty()) throw new NotFoundException("Invoice not found");
        Map<String, Object> inv = rows.getFirst();
        if (!"PENDING".equals(inv.get("status")) || decimal(inv.get("paid_amount")).compareTo(BigDecimal.ZERO) > 0) {
            throw new BadRequestException("Only a pending invoice with no payments can be edited");
        }
        // Only line items that actually belong to this invoice may be re-priced.
        java.util.Set<Long> validItemIds = new java.util.HashSet<>(jdbc.queryForList(
                "SELECT invoice_item_id FROM invoice_item WHERE invoice_id=?", Long.class, invoiceId));
        for (AmountRequest.Item item : request.items()) {
            if (!validItemIds.contains(item.invoiceItemId())) {
                throw new BadRequestException("Charge line does not belong to this invoice");
            }
            jdbc.update("UPDATE invoice_item SET amount=?,updated_at=LOCALTIMESTAMP WHERE invoice_item_id=? AND invoice_id=?",
                    item.amount(), item.invoiceItemId(), invoiceId);
        }
        BigDecimal total = jdbc.queryForObject(
                "SELECT COALESCE(SUM(amount),0) FROM invoice_item WHERE invoice_id=?", BigDecimal.class, invoiceId);
        if (total == null || total.compareTo(BigDecimal.ZERO) <= 0) {
            throw new BadRequestException("Total amount must be greater than zero");
        }
        jdbc.update("UPDATE invoice SET total_amount=?,updated_at=LOCALTIMESTAMP,version=version+1 " +
                "WHERE invoice_id=? AND organization_id=?", total, invoiceId, org);
        // Mirror an edited security-deposit line onto the master deposit held on
        // the active occupancy row (what checkout shows the owner to refund).
        List<Map<String, Object>> depositLine = jdbc.queryForList(
                "SELECT amount FROM invoice_item WHERE invoice_id=? AND item_type_id='SECURITY_DEPOSIT' LIMIT 1",
                invoiceId);
        if (!depositLine.isEmpty() && inv.get("party_id") != null) {
            BigDecimal deposit = decimal(depositLine.getFirst().get("amount"));
            Long partyId = ((Number) inv.get("party_id")).longValue();
            jdbc.update("UPDATE facility_party SET security_deposit=?,updated_at=LOCALTIMESTAMP " +
                    "WHERE organization_id=? AND party_id=? AND role_type_id='OCCUPANT' AND thru_date IS NULL",
                    deposit, org, partyId);
        }
        return ApiResponse.ok("Invoice amount updated", Map.of("invoiceId", invoiceId, "totalAmount", total));
    }

    private String partyPropFilter(String alias, Long propertyId) {
        if (propertyId == null) return "";
        String col = (alias == null || alias.isBlank()) ? "party_id" : alias + ".party_id";
        return " AND " + col + " IN (SELECT fp.party_id FROM facility_party fp WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')";
    }

    private BigDecimal amount(String sql, Object... args) {
        BigDecimal value = jdbc.queryForObject(sql, BigDecimal.class, args);
        return value == null ? BigDecimal.ZERO : value;
    }

    private int count(String sql, Object... args) {
        Integer value = jdbc.queryForObject(sql, Integer.class, args);
        return value == null ? 0 : value;
    }

    private Object[] cat(Object first, Object[] rest) {
        Object[] result = new Object[1 + rest.length];
        result[0] = first;
        System.arraycopy(rest, 0, result, 1, rest.length);
        return result;
    }

    private BigDecimal decimal(Object value) {
        return value instanceof BigDecimal decimal ? decimal : new BigDecimal(value.toString());
    }

    public record PaymentRequest(@NotNull Long invoiceId, @NotNull @DecimalMin("0.01") BigDecimal amount,
                                 String paymentMode, LocalDate paymentDate,
                                 String referenceNumber, String notes, @NotNull String idempotencyKey) {}
    public record CashPaymentRequest(@NotNull Long invoiceId, @NotNull @DecimalMin("0.01") BigDecimal amount,
                                     LocalDate paymentDate, String referenceNumber, String notes, @NotNull String idempotencyKey) {}
    public record AdvanceRequest(@NotNull Long billingAccountId, @NotNull @DecimalMin("0.01") BigDecimal amount,
                                 LocalDate paymentDate, String referenceNumber, String notes, @NotNull String idempotencyKey) {}
    public record RefundRequest(@NotNull @DecimalMin("0.01") BigDecimal amount, String referenceNumber, String reason) {}
    // checkoutGraceDays is optional so an older app build (which only sends lead days +
    // the automation toggle) keeps working — it falls back to the default, not to 0.
    public record BillingConfigRequest(@NotNull @Min(0) @Max(28) Integer invoiceLeadDays,
                                       @Min(0) @Max(28) Integer checkoutGraceDays,
                                       @NotNull Boolean autoGenerateEnabled) {}
    public record AmountRequest(@NotNull @NotEmpty @Valid List<Item> items) {
        public record Item(@NotNull Long invoiceItemId, @NotNull @DecimalMin("0.00") BigDecimal amount) {}
    }
}
