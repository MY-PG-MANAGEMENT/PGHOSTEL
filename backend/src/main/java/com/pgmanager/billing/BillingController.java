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
    ApiResponse<Map<String, Object>> dashboard(@RequestParam(required = false) Long propertyId) {
        Long org = currentUser.organizationId();
        String payProp = propertyId != null
                ? " AND party_id IN (SELECT fp.party_id FROM facility_party fp WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')"
                : "";
        String payAliasProp = propertyId != null
                ? " AND p.party_id IN (SELECT fp.party_id FROM facility_party fp WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')"
                : "";
        String invProp = propertyId != null
                ? " AND ba.party_id IN (SELECT fp.party_id FROM facility_party fp WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')"
                : "";
        String invScalarProp = propertyId != null
                ? " AND billing_account_id IN (SELECT ba.billing_account_id FROM billing_account ba WHERE ba.organization_id=? AND ba.party_id IN (SELECT fp.party_id FROM facility_party fp WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT'))"
                : "";
        Object[] pp2 = propertyId != null ? new Object[]{org, propertyId} : new Object[0];
        Object[] pp3 = propertyId != null ? new Object[]{org, org, propertyId} : new Object[0];
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("totalCollection", amount(
                "SELECT COALESCE(SUM(amount),0) FROM payment WHERE organization_id=? AND status='RECEIVED' AND payment_date BETWEEN DATE_FORMAT(CURRENT_DATE,'%Y-%m-01') AND LAST_DAY(CURRENT_DATE)" + payProp,
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
        Long org = currentUser.organizationId();
        int safeSize = Math.min(Math.max(size, 1), 100);
        String statusFilter = (status == null || status.isBlank()) ? "" : " AND i.status=?";
        String partyFilter = partyId != null ? " AND ba.party_id=?" : "";
        String propFilter = propertyId != null
                ? " AND ba.party_id IN (SELECT fp.party_id FROM facility_party fp WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')"
                : "";
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
        Long org = currentUser.organizationId();
        int safeSize = Math.min(Math.max(size, 1), 500);
        String partyFilter = (partyId != null) ? " AND p.party_id=?" : "";
        String fromFilter  = (fromDate != null && !fromDate.isBlank()) ? " AND p.payment_date>=?" : "";
        String toFilter    = (toDate   != null && !toDate.isBlank())   ? " AND p.payment_date<=?" : "";
        String propFilter  = propertyId != null
                ? " AND p.party_id IN (SELECT fp.party_id FROM facility_party fp WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')"
                : "";
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
        List<Map<String, Object>> invoices = jdbc.queryForList("SELECT i.invoice_id,i.billing_account_id,i.total_amount,i.paid_amount,ba.party_id " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id WHERE i.invoice_id=? AND i.organization_id=? FOR UPDATE",
                request.invoiceId(), org);
        if (invoices.isEmpty()) throw new NotFoundException("Invoice not found");
        Map<String, Object> invoice = invoices.getFirst();
        BigDecimal balance = decimal(invoice.get("total_amount")).subtract(decimal(invoice.get("paid_amount")));
        if (request.amount().compareTo(balance) > 0) throw new BadRequestException("Payment exceeds invoice balance");
        String mode = request.paymentMode() == null ? "CASH" : request.paymentMode().toUpperCase();
        try {
            jdbc.update("INSERT INTO payment(organization_id,party_id,amount,payment_mode,payment_date,reference_number,notes," +
                            "idempotency_key,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,'RECEIVED',?,?)",
                    org, invoice.get("party_id"), request.amount(), mode,
                    request.paymentDate() == null ? LocalDate.now() : request.paymentDate(),
                    request.referenceNumber(), request.notes(), request.idempotencyKey(), LocalDateTime.now(), LocalDateTime.now());
        } catch (DuplicateKeyException duplicate) {
            return ApiResponse.ok("Payment already recorded", jdbc.queryForMap(
                    "SELECT payment_id,amount,status FROM payment WHERE organization_id=? AND idempotency_key=?",
                    org, request.idempotencyKey()));
        }
        Long paymentId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        jdbc.update("INSERT INTO payment_allocation(organization_id,payment_id,invoice_id,amount,allocated_at) VALUES(?,?,?,?,?)",
                org, paymentId, request.invoiceId(), request.amount(), LocalDateTime.now());
        BigDecimal paid = decimal(invoice.get("paid_amount")).add(request.amount());
        String status = paid.compareTo(decimal(invoice.get("total_amount"))) >= 0 ? "PAID" : "PARTIAL";
        jdbc.update("UPDATE invoice SET paid_amount=?,status=?,updated_at=?,version=version+1 WHERE invoice_id=?",
                paid, status, LocalDateTime.now(), request.invoiceId());
        return ApiResponse.ok("Payment recorded", Map.of("paymentId", paymentId, "invoiceId", request.invoiceId(),
                "amount", request.amount(), "paymentMode", mode, "status", status, "receiptNumber", "RCP-" + paymentId));
    }

    @PostMapping("/payments/cash")
    @Transactional
    ApiResponse<Map<String, Object>> collectCash(@Valid @RequestBody CashPaymentRequest request) {
        return collectPayment(new PaymentRequest(request.invoiceId(), request.amount(), "CASH",
                request.paymentDate(), request.referenceNumber(), request.notes(), request.idempotencyKey()));
    }

    @PostMapping("/generate-invoices")
    @Transactional
    ApiResponse<Map<String, Object>> generateInvoices(@RequestParam(required = false) String month) {
        Long org = currentUser.organizationId();
        LocalDate invoiceMonth;
        try {
            invoiceMonth = month != null ? LocalDate.parse(month + "-01") : LocalDate.now().withDayOfMonth(1);
        } catch (Exception e) {
            throw new BadRequestException("Invalid month format; use YYYY-MM");
        }
        List<Map<String, Object>> accounts = jdbc.queryForList(
                "SELECT ba.billing_account_id,ba.party_id,fp.monthly_rent,fp.from_date " +
                "FROM billing_account ba JOIN facility_party fp ON fp.party_id=ba.party_id " +
                "  AND fp.organization_id=ba.organization_id AND fp.role_type_id='OCCUPANT' AND fp.thru_date IS NULL " +
                "WHERE ba.organization_id=? AND ba.status='ACTIVE'", org);
        int generated = 0;
        for (Map<String, Object> account : accounts) {
            Long baId = ((Number) account.get("billing_account_id")).longValue();
            Long partyId = ((Number) account.get("party_id")).longValue();
            BigDecimal rent = account.get("monthly_rent") != null ? decimal(account.get("monthly_rent")) : BigDecimal.ZERO;
            Long exists = jdbc.queryForObject("SELECT COUNT(*) FROM invoice WHERE billing_account_id=? AND invoice_month=?",
                    Long.class, baId, invoiceMonth);
            if (exists != null && exists > 0) continue;
            int dayOfMonth = 1;
            if (account.get("from_date") != null) {
                dayOfMonth = ((java.sql.Date) account.get("from_date")).toLocalDate().getDayOfMonth();
            }
            LocalDate dueDate = invoiceMonth.withDayOfMonth(Math.min(dayOfMonth, invoiceMonth.lengthOfMonth()));
            String invNum = "INV-" + org + "-" + baId + "-" + invoiceMonth.toString().substring(0, 7).replace("-", "");
            jdbc.update("INSERT INTO invoice(organization_id,billing_account_id,invoice_number,invoice_month,issue_date,due_date," +
                            "total_amount,paid_amount,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,0,'PENDING',?,?)",
                    org, baId, invNum, invoiceMonth, invoiceMonth, dueDate, rent, LocalDateTime.now(), LocalDateTime.now());
            Long invoiceId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
            jdbc.update("INSERT INTO invoice_item(invoice_id,item_type_id,description,amount,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                    invoiceId, "MONTHLY_RENT", "Monthly Rent", rent, LocalDateTime.now(), LocalDateTime.now());
            generated++;
        }
        return ApiResponse.ok(Map.of("generated", generated, "skipped", accounts.size() - generated,
                "month", invoiceMonth.toString()));
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
                jdbc.update("INSERT INTO payment(organization_id,party_id,amount,payment_mode,payment_date," +
                                "idempotency_key,status,created_at,updated_at) VALUES(?,?,?,'CASH',CURRENT_DATE,?,'RECEIVED',NOW(),NOW())",
                        org, partyId, balance, ikey);
                Long payId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
                jdbc.update("INSERT INTO payment_allocation(organization_id,payment_id,invoice_id,amount,allocated_at) " +
                        "VALUES(?,?,?,?,NOW())", org, payId, invoiceId, balance);
            } catch (DuplicateKeyException ignored) {
            }
        }
        jdbc.update("UPDATE invoice SET paid_amount=total_amount,status='PAID',updated_at=NOW(),version=version+1 " +
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
                jdbc.update("INSERT INTO payment(organization_id,party_id,amount,payment_mode,payment_date," +
                                "idempotency_key,status,created_at,updated_at) VALUES(?,?,?,'WRITE_OFF',CURRENT_DATE,?,'WRITTEN_OFF',NOW(),NOW())",
                        org, partyId, balance, ikey);
                Long payId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
                jdbc.update("INSERT INTO payment_allocation(organization_id,payment_id,invoice_id,amount,allocated_at) " +
                        "VALUES(?,?,?,?,NOW())", org, payId, invoiceId, balance);
            } catch (DuplicateKeyException ignored) {
            }
        }
        jdbc.update("UPDATE invoice SET status='WRITTEN_OFF',updated_at=NOW(),version=version+1 " +
                "WHERE invoice_id=? AND organization_id=?", invoiceId, org);
        return ApiResponse.ok("Invoice written off", null);
    }

    private BigDecimal amount(String sql, Object... args) {
        BigDecimal value = jdbc.queryForObject(sql, BigDecimal.class, args);
        return value == null ? BigDecimal.ZERO : value;
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
}
