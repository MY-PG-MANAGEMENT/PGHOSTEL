package com.pgmanager.billing;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.security.CurrentUser;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
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

    @GetMapping("/dashboard")
    ApiResponse<Map<String, Object>> dashboard() {
        Long org = currentUser.organizationId();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("totalCollection", amount("SELECT COALESCE(SUM(amount),0) FROM payment WHERE organization_id=? AND status='RECEIVED'", org));
        result.put("receivedToday", amount("SELECT COALESCE(SUM(amount),0) FROM payment WHERE organization_id=? AND payment_date=CURRENT_DATE AND status='RECEIVED'", org));
        result.put("pendingCollection", amount("SELECT COALESCE(SUM(total_amount-paid_amount),0) FROM invoice WHERE organization_id=? AND status IN ('PENDING','PARTIAL','OVERDUE')", org));
        result.put("overdue", amount("SELECT COALESCE(SUM(total_amount-paid_amount),0) FROM invoice WHERE organization_id=? AND status='OVERDUE'", org));
        result.put("recentPayments", jdbc.queryForList("SELECT payment_id,party_id,amount,payment_mode,payment_date,reference_number,status " +
                "FROM payment WHERE organization_id=? ORDER BY payment_date DESC,payment_id DESC LIMIT 10", org));
        return ApiResponse.ok(result);
    }

    @GetMapping("/invoices")
    ApiResponse<Map<String, Object>> invoices(@RequestParam(required = false) String status,
                                               @RequestParam(defaultValue = "0") int page,
                                               @RequestParam(defaultValue = "25") int size) {
        int safeSize = Math.min(Math.max(size, 1), 100);
        String filter = status == null || status.isBlank() ? "" : " AND i.status=?";
        Object[] args = status == null || status.isBlank()
                ? new Object[]{currentUser.organizationId(), safeSize, Math.max(page, 0) * safeSize}
                : new Object[]{currentUser.organizationId(), status.toUpperCase(), safeSize, Math.max(page, 0) * safeSize};
        List<Map<String, Object>> items = jdbc.queryForList("SELECT i.invoice_id,i.invoice_number,i.invoice_month,i.issue_date,i.due_date," +
                "i.total_amount,i.paid_amount,(i.total_amount-i.paid_amount) balance,i.status,ba.party_id,p.full_name " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "JOIN person p ON p.party_id=ba.party_id WHERE i.organization_id=?" + filter +
                " ORDER BY i.due_date DESC LIMIT ? OFFSET ?", args);
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

    @PostMapping("/payments/cash")
    @Transactional
    ApiResponse<Map<String, Object>> collectCash(@Valid @RequestBody CashPaymentRequest request) {
        Long org = currentUser.organizationId();
        List<Map<String, Object>> invoices = jdbc.queryForList("SELECT i.invoice_id,i.billing_account_id,i.total_amount,i.paid_amount,ba.party_id " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id WHERE i.invoice_id=? AND i.organization_id=? FOR UPDATE",
                request.invoiceId(), org);
        if (invoices.isEmpty()) throw new NotFoundException("Invoice not found");
        Map<String, Object> invoice = invoices.getFirst();
        BigDecimal balance = decimal(invoice.get("total_amount")).subtract(decimal(invoice.get("paid_amount")));
        if (request.amount().compareTo(balance) > 0) throw new BadRequestException("Payment exceeds invoice balance; record the excess as advance");
        try {
            jdbc.update("INSERT INTO payment(organization_id,party_id,amount,payment_mode,payment_date,reference_number,notes," +
                            "idempotency_key,status,created_at,updated_at) VALUES(?,?,?,'CASH',?,?,?,?,?,'RECEIVED',?,?)",
                    org, invoice.get("party_id"), request.amount(), request.paymentDate() == null ? LocalDate.now() : request.paymentDate(),
                    request.referenceNumber(), request.notes(), request.idempotencyKey(), LocalDateTime.now(), LocalDateTime.now());
        } catch (DuplicateKeyException duplicate) {
            return ApiResponse.ok("Payment already recorded", jdbc.queryForMap("SELECT payment_id,amount,status FROM payment WHERE organization_id=? AND idempotency_key=?",
                    org, request.idempotencyKey()));
        }
        Long paymentId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        jdbc.update("INSERT INTO payment_allocation(organization_id,payment_id,invoice_id,amount,allocated_at) VALUES(?,?,?,?,?)",
                org, paymentId, request.invoiceId(), request.amount(), LocalDateTime.now());
        BigDecimal paid = decimal(invoice.get("paid_amount")).add(request.amount());
        String status = paid.compareTo(decimal(invoice.get("total_amount"))) >= 0 ? "PAID" : "PARTIAL";
        jdbc.update("UPDATE invoice SET paid_amount=?,status=?,updated_at=?,version=version+1 WHERE invoice_id=?",
                paid, status, LocalDateTime.now(), request.invoiceId());
        return ApiResponse.ok("Cash payment recorded", Map.of("paymentId", paymentId, "invoiceId", request.invoiceId(),
                "amount", request.amount(), "status", status, "receiptNumber", "RCP-" + paymentId));
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

    private BigDecimal amount(String sql, Object... args) {
        BigDecimal value = jdbc.queryForObject(sql, BigDecimal.class, args);
        return value == null ? BigDecimal.ZERO : value;
    }

    private BigDecimal decimal(Object value) {
        return value instanceof BigDecimal decimal ? decimal : new BigDecimal(value.toString());
    }

    public record CashPaymentRequest(@NotNull Long invoiceId, @NotNull @DecimalMin("0.01") BigDecimal amount,
                                     LocalDate paymentDate, String referenceNumber, String notes, @NotNull String idempotencyKey) {}
    public record AdvanceRequest(@NotNull Long billingAccountId, @NotNull @DecimalMin("0.01") BigDecimal amount,
                                 LocalDate paymentDate, String referenceNumber, String notes, @NotNull String idempotencyKey) {}
    public record RefundRequest(@NotNull @DecimalMin("0.01") BigDecimal amount, String referenceNumber, String reason) {}
}
