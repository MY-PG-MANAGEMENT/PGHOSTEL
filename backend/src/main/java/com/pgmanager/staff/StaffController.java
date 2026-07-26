package com.pgmanager.staff;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.expense.ExpenseWriter;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.security.PropertyAccessGuard;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
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
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Staff management (schema: V17): employees with a profession and monthly
 * salary, plus month-by-month salary payments. Paying a salary records a
 * SALARY expense through ExpenseWriter so the expenses dashboard reflects
 * payroll; the unique (staff_id, pay_month) key guards double payment.
 * JdbcTemplate throughout, same rationale as billing/expenses.
 */
@RestController
@RequestMapping("/api/staff")
@RequiredArgsConstructor
public class StaffController {
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;
    private final AuditService auditService;
    private final ExpenseWriter expenseWriter;
    private final PropertyAccessGuard propertyAccessGuard;

    static final Set<String> PAYMENT_METHODS = Set.of("CASH", "UPI", "CARD", "BANK_TRANSFER");

    // ──────────────────────────────────────────────────────────────── list ──

    @GetMapping
    ApiResponse<Map<String, Object>> list(@RequestParam(required = false) Long propertyId,
                                          @RequestParam(required = false) String month) {
        // Scope to what this login may see: unchanged for an owner; a property-scoped
        // login gets their own property substituted in, or a 403/400.
        propertyId = propertyAccessGuard.resolvePropertyId(propertyId);
        Long org = currentUser.organizationId();
        YearMonth ym = parseMonth(month);
        StringBuilder sql = new StringBuilder(
                "SELECT s.staff_id staffId, s.property_facility_id propertyId, s.full_name fullName, s.profession, " +
                "s.mobile_number mobileNumber, s.monthly_salary monthlySalary, s.join_date joinDate, s.status, s.notes, " +
                "p.amount paidAmount, p.paid_date paidDate, p.payment_method paymentMethod " +
                "FROM staff s LEFT JOIN staff_salary_payment p ON p.staff_id=s.staff_id AND p.pay_month=? " +
                "WHERE s.organization_id=?");
        List<Object> args = new ArrayList<>(List.of(ym.toString(), org));
        if (propertyId != null) { sql.append(" AND s.property_facility_id=?"); args.add(propertyId); }
        sql.append(" ORDER BY s.status, s.full_name");
        List<Map<String, Object>> items = jdbc.queryForList(sql.toString(), args.toArray());

        int activeCount = 0, paidCount = 0, dueCount = 0;
        BigDecimal payroll = BigDecimal.ZERO, paidTotal = BigDecimal.ZERO, dueTotal = BigDecimal.ZERO;
        for (Map<String, Object> s : items) {
            boolean active = "ACTIVE".equals(s.get("status"));
            boolean paid = s.get("paidAmount") != null;
            BigDecimal salary = decimal(s.get("monthlySalary"));
            if (active) {
                activeCount++;
                payroll = payroll.add(salary);
            }
            if (paid) {
                paidCount++;
                paidTotal = paidTotal.add(decimal(s.get("paidAmount")));
            } else if (active) {
                dueCount++;
                dueTotal = dueTotal.add(salary);
            }
        }
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("totalStaff", items.size());
        summary.put("activeStaff", activeCount);
        summary.put("monthlyPayroll", payroll);
        summary.put("paidCount", paidCount);
        summary.put("paidTotal", paidTotal);
        summary.put("dueCount", dueCount);
        summary.put("dueTotal", dueTotal);
        return ApiResponse.ok(Map.of("month", ym.toString(), "items", items, "summary", summary));
    }

    @GetMapping("/{staffId}/payments")
    ApiResponse<Map<String, Object>> payments(@PathVariable Long staffId) {
        Long org = currentUser.organizationId();
        requireStaff(org, staffId);
        return ApiResponse.ok(Map.of("items", jdbc.queryForList(
                "SELECT pay_month payMonth, amount, payment_method paymentMethod, paid_date paidDate " +
                "FROM staff_salary_payment WHERE organization_id=? AND staff_id=? ORDER BY pay_month DESC LIMIT 24",
                org, staffId)));
    }

    // ──────────────────────────────────────────────────────────────── crud ──

    @PostMapping
    @Transactional
    ApiResponse<Map<String, Object>> create(@Valid @RequestBody StaffRequest request) {
        Long org = currentUser.organizationId();
        if (request.propertyId() != null) requirePropertyInOrg(org, request.propertyId());
        jdbc.update("INSERT INTO staff(organization_id,property_facility_id,full_name,profession,mobile_number," +
                        "monthly_salary,join_date,status,notes,created_at,updated_at) VALUES(?,?,?,?,?,?,?,'ACTIVE',?,NOW(),NOW())",
                org, request.propertyId(), request.fullName().trim(), request.profession().trim(),
                request.mobileNumber(), request.monthlySalary(), request.joinDate(), request.notes());
        Long staffId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        auditService.log(org, currentUser.userLoginId(), "STAFF_CREATED", "STAFF", staffId,
                request.fullName() + " (" + request.profession() + ") " + request.monthlySalary());
        return ApiResponse.ok("Staff added", Map.of("staffId", staffId));
    }

    @PutMapping("/{staffId}")
    @Transactional
    ApiResponse<Map<String, Object>> update(@PathVariable Long staffId, @Valid @RequestBody StaffRequest request) {
        Long org = currentUser.organizationId();
        requireStaff(org, staffId);
        if (request.propertyId() != null) requirePropertyInOrg(org, request.propertyId());
        String status = request.status() == null ? "ACTIVE" : request.status().toUpperCase();
        if (!status.equals("ACTIVE") && !status.equals("INACTIVE")) {
            throw new BadRequestException("Status must be ACTIVE or INACTIVE");
        }
        jdbc.update("UPDATE staff SET property_facility_id=?, full_name=?, profession=?, mobile_number=?, " +
                        "monthly_salary=?, join_date=?, status=?, notes=?, updated_at=NOW() WHERE staff_id=? AND organization_id=?",
                request.propertyId(), request.fullName().trim(), request.profession().trim(), request.mobileNumber(),
                request.monthlySalary(), request.joinDate(), status, request.notes(), staffId, org);
        auditService.log(org, currentUser.userLoginId(), "STAFF_UPDATED", "STAFF", staffId,
                request.fullName() + " (" + request.profession() + ") " + status);
        return ApiResponse.ok("Staff updated", Map.of("staffId", staffId, "status", status));
    }

    @DeleteMapping("/{staffId}")
    @Transactional
    ApiResponse<Void> deactivate(@PathVariable Long staffId) {
        Long org = currentUser.organizationId();
        requireStaff(org, staffId);
        jdbc.update("UPDATE staff SET status='INACTIVE', updated_at=NOW() WHERE staff_id=? AND organization_id=?",
                staffId, org);
        auditService.log(org, currentUser.userLoginId(), "STAFF_DEACTIVATED", "STAFF", staffId, null);
        return ApiResponse.ok("Staff deactivated", null);
    }

    // ───────────────────────────────────────────────────────────────── pay ──

    @PostMapping("/pay")
    @Transactional
    ApiResponse<Map<String, Object>> pay(@Valid @RequestBody PayRequest request) {
        Long org = currentUser.organizationId();
        YearMonth ym = parseMonth(request.month());
        if (ym.isAfter(YearMonth.now())) throw new BadRequestException("Cannot pay salaries for a future month");
        String method = request.paymentMethod() == null || request.paymentMethod().isBlank()
                ? "CASH" : request.paymentMethod().toUpperCase();
        if (!PAYMENT_METHODS.contains(method)) throw new BadRequestException("Invalid payment method: " + method);
        LocalDate today = LocalDate.now();
        int paid = 0, skipped = 0;
        BigDecimal totalPaid = BigDecimal.ZERO;
        for (Long staffId : request.staffIds()) {
            List<Map<String, Object>> rows = jdbc.queryForList(
                    "SELECT full_name, property_facility_id, monthly_salary, status FROM staff " +
                    "WHERE staff_id=? AND organization_id=? FOR UPDATE", staffId, org);
            if (rows.isEmpty() || !"ACTIVE".equals(rows.getFirst().get("status"))) {
                skipped++;
                continue;
            }
            Map<String, Object> staff = rows.getFirst();
            BigDecimal salary = decimal(staff.get("monthly_salary"));
            try {
                jdbc.update("INSERT INTO staff_salary_payment(organization_id,staff_id,pay_month,amount,payment_method," +
                                "paid_date,created_by,created_at,updated_at) VALUES(?,?,?,?,?,?,?,NOW(),NOW())",
                        org, staffId, ym.toString(), salary, method, today, currentUser.userLoginId());
            } catch (DuplicateKeyException alreadyPaid) {
                skipped++;
                continue;
            }
            Long propertyId = staff.get("property_facility_id") == null
                    ? null : ((Number) staff.get("property_facility_id")).longValue();
            Long expenseId = expenseWriter.insertApproved(org, propertyId, "SALARY",
                    "Salary - " + staff.get("full_name") + " (" + ym + ")", salary, method, today,
                    currentUser.userLoginId());
            jdbc.update("UPDATE staff_salary_payment SET expense_id=?, updated_at=NOW() WHERE staff_id=? AND pay_month=?",
                    expenseId, staffId, ym.toString());
            auditService.log(org, currentUser.userLoginId(), "STAFF_SALARY_PAID", "STAFF", staffId,
                    staff.get("full_name") + " " + ym + " " + salary + " (" + method + ")");
            paid++;
            totalPaid = totalPaid.add(salary);
        }
        return ApiResponse.ok(paid + " salaries paid",
                Map.of("paid", paid, "skipped", skipped, "totalAmount", totalPaid, "month", ym.toString()));
    }

    // ─────────────────────────────────────────────────────────────── helpers ──

    private void requireStaff(Long org, Long staffId) {
        Long count = jdbc.queryForObject("SELECT COUNT(*) FROM staff WHERE staff_id=? AND organization_id=?",
                Long.class, staffId, org);
        if (count == null || count == 0) throw new NotFoundException("Staff not found");
    }

    private void requirePropertyInOrg(Long org, Long propertyId) {
        Long count = jdbc.queryForObject("SELECT COUNT(*) FROM facility WHERE facility_id=? AND organization_id=?",
                Long.class, propertyId, org);
        if (count == null || count == 0) throw new NotFoundException("Property not found");
    }

    private static YearMonth parseMonth(String month) {
        if (month == null || month.isBlank()) return YearMonth.now();
        try {
            return YearMonth.parse(month);
        } catch (Exception e) {
            throw new BadRequestException("Invalid month format; use YYYY-MM");
        }
    }

    private static BigDecimal decimal(Object value) {
        return value instanceof BigDecimal decimal ? decimal : new BigDecimal(value.toString());
    }

    // ─────────────────────────────────────────────────────────────── requests ──

    public record StaffRequest(
            @NotBlank @Size(max = 120) String fullName,
            @NotBlank @Size(max = 60) String profession,
            @NotNull @DecimalMin("0.01") BigDecimal monthlySalary,
            @Size(max = 15) String mobileNumber,
            Long propertyId,
            LocalDate joinDate,
            String status,
            @Size(max = 255) String notes) {}

    public record PayRequest(@NotEmpty List<Long> staffIds, String month, String paymentMethod) {}
}
