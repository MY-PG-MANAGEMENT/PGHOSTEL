package com.pgmanager.expense;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.security.CurrentUser;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
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
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Expense tracking module (schema: V16). JdbcTemplate throughout — the
 * dashboard is aggregate-heavy, same rationale as BillingController.
 * Categories and payment methods are string constants (no master tables).
 */
@RestController
@RequestMapping("/api/expenses")
@RequiredArgsConstructor
public class ExpenseController {
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;
    private final AuditService auditService;
    private final ExpenseWriter expenseWriter;

    // String constants, no master table (see docs/EXPENSES_SCHEMA_MAPPING.md). Categories are
    // only ever added — an existing row's category must keep resolving, and DEPOSIT_REFUND is
    // written by the tenant-checkout refund flow, not by hand.
    static final Set<String> CATEGORIES = Set.of(
            "FOOD", "SALARY", "ELECTRICITY", "MAINTENANCE", "LAUNDRY", "TRANSPORT", "RENT", "DEPOSIT_REFUND",
            "WATER", "CLEANING", "REPAIRS", "INTERNET", "GAS", "OTHERS");
    static final Set<String> PAYMENT_METHODS = Set.of("CASH", "UPI", "CARD", "BANK_TRANSFER");
    private static final String SPENT_STATUSES = "('APPROVED','PAID')";

    // ─────────────────────────────────────────────────────────── dashboard ──

    @GetMapping("/dashboard")
    ApiResponse<Map<String, Object>> dashboard(@RequestParam(required = false) Long propertyId,
                                               @RequestParam(required = false) String month) {
        Long org = currentUser.organizationId();
        YearMonth ym = parseMonth(month);
        LocalDate start = ym.atDay(1), end = ym.atEndOfMonth();
        LocalDate prevStart = ym.minusMonths(1).atDay(1), prevEnd = ym.minusMonths(1).atEndOfMonth();
        String prop = propertyId != null ? " AND property_facility_id=?" : "";
        Object[] scope = propertyId != null ? new Object[]{propertyId} : new Object[0];

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("month", ym.toString());

        // Summary
        BigDecimal total = amount(
                "SELECT COALESCE(SUM(amount),0) FROM expense WHERE organization_id=? AND status IN " + SPENT_STATUSES +
                " AND expense_date BETWEEN ? AND ?" + prop, args(org, start, end, scope));
        BigDecimal lastTotal = amount(
                "SELECT COALESCE(SUM(amount),0) FROM expense WHERE organization_id=? AND status IN " + SPENT_STATUSES +
                " AND expense_date BETWEEN ? AND ?" + prop, args(org, prevStart, prevEnd, scope));
        BigDecimal budget = overallBudget(org, propertyId, ym);
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("total", total);
        summary.put("lastMonthTotal", lastTotal);
        summary.put("changePct", lastTotal.signum() > 0
                ? total.subtract(lastTotal).multiply(BigDecimal.valueOf(100)).divide(lastTotal, 0, RoundingMode.HALF_UP)
                : null);
        summary.put("budget", budget);
        summary.put("remaining", budget != null ? budget.subtract(total) : null);
        result.put("summary", summary);

        // Category breakdown (this month)
        List<Map<String, Object>> categories = jdbc.queryForList(
                "SELECT category, SUM(amount) total FROM expense WHERE organization_id=? AND status IN " + SPENT_STATUSES +
                " AND expense_date BETWEEN ? AND ?" + prop + " GROUP BY category ORDER BY total DESC",
                args(org, start, end, scope));
        result.put("categories", categories);

        // Budget utilization (category budgets for this month joined with spend)
        long budgetScope = propertyId != null ? propertyId : 0L;
        List<Object> budgetArgs = new ArrayList<>(List.of(org, start, end));
        if (propertyId != null) budgetArgs.add(propertyId);
        budgetArgs.addAll(List.of(org, budgetScope, ym.toString()));
        result.put("budgets", jdbc.queryForList(
                "SELECT b.category, b.amount budget, COALESCE(s.spent,0) spent FROM expense_budget b " +
                "LEFT JOIN (SELECT category, SUM(amount) spent FROM expense WHERE organization_id=? AND status IN " + SPENT_STATUSES +
                "  AND expense_date BETWEEN ? AND ?" + prop + " GROUP BY category) s ON s.category=b.category " +
                "WHERE b.organization_id=? AND b.property_facility_id=? AND b.category<>'ALL' AND b.budget_month=? " +
                "ORDER BY b.category", budgetArgs.toArray()));

        // 6-month trend: expense vs income (received payments) vs profit
        result.put("trend", trend(org, propertyId, ym));

        // Pending approvals
        Long pendingCount = jdbc.queryForObject(
                "SELECT COUNT(*) FROM expense WHERE organization_id=? AND status='PENDING'" + prop,
                Long.class, args(org, scope));
        List<Map<String, Object>> pendingItems = jdbc.queryForList(
                "SELECT expense_id expenseId, title, category, vendor_name vendorName, amount, expense_date expenseDate " +
                "FROM expense WHERE organization_id=? AND status='PENDING'" + prop +
                " ORDER BY expense_date DESC, expense_id DESC LIMIT 10", args(org, scope));
        result.put("pendingApprovals", Map.of("count", pendingCount == null ? 0 : pendingCount, "items", pendingItems));

        // Recent transactions — rolling last 7 days only
        result.put("recentTransactions", jdbc.queryForList(
                // Whole dashboard month (1st → month end). PENDING included so a
                // just-created expense is visible immediately; summary/category
                // totals above stay APPROVED/PAID only.
                "SELECT expense_id expenseId, title, category, amount, payment_method paymentMethod, status, expense_date expenseDate " +
                "FROM expense WHERE organization_id=? AND status <> 'REJECTED'" +
                " AND expense_date BETWEEN ? AND ?" + prop +
                " ORDER BY expense_date DESC, expense_id DESC LIMIT 100", args(org, start, end, scope)));

        // Petty cash (opening = ledger sum before this month)
        result.put("pettyCash", pettyCash(org, propertyId, start, end));

        // Insights derived from the aggregates above
        result.put("insights", insights(org, propertyId, start, end, prevStart, prevEnd, categories, budget, total));
        return ApiResponse.ok(result);
    }

    @GetMapping
    ApiResponse<Map<String, Object>> list(@RequestParam(required = false) Long propertyId,
                                          @RequestParam(required = false) String month,
                                          @RequestParam(required = false) String status,
                                          @RequestParam(required = false) String category,
                                          @RequestParam(defaultValue = "0") int page,
                                          @RequestParam(defaultValue = "25") int size) {
        Long org = currentUser.organizationId();
        int safeSize = Math.min(Math.max(size, 1), 100);
        StringBuilder sql = new StringBuilder(
                "SELECT expense_id expenseId, property_facility_id propertyId, title, category, description, amount, " +
                "payment_method paymentMethod, vendor_name vendorName, status, expense_date expenseDate " +
                "FROM expense WHERE organization_id=?");
        List<Object> argList = new ArrayList<>(List.of(org));
        if (propertyId != null) { sql.append(" AND property_facility_id=?"); argList.add(propertyId); }
        if (month != null && !month.isBlank()) {
            YearMonth ym = parseMonth(month);
            sql.append(" AND expense_date BETWEEN ? AND ?");
            argList.add(ym.atDay(1));
            argList.add(ym.atEndOfMonth());
        }
        if (status != null && !status.isBlank()) { sql.append(" AND status=?"); argList.add(status.toUpperCase()); }
        if (category != null && !category.isBlank()) { sql.append(" AND category=?"); argList.add(category.toUpperCase()); }
        sql.append(" ORDER BY expense_date DESC, expense_id DESC LIMIT ? OFFSET ?");
        argList.add(safeSize);
        argList.add(Math.max(page, 0) * safeSize);
        return ApiResponse.ok(Map.of("items", jdbc.queryForList(sql.toString(), argList.toArray()),
                "page", page, "size", safeSize));
    }

    /** Full row for the edit form, plus whether this expense may be edited/deleted at all. */
    @GetMapping("/{expenseId}")
    ApiResponse<Map<String, Object>> detail(@PathVariable Long expenseId) {
        Long org = currentUser.organizationId();
        Map<String, Object> result = new LinkedHashMap<>(loadExpense(org, expenseId));
        String locked = lockReason(org, expenseId);
        result.put("editable", locked == null);
        result.put("lockedReason", locked);
        return ApiResponse.ok(result);
    }

    // ──────────────────────────────────────────────────────────── mutations ──

    @PostMapping
    @Transactional
    ApiResponse<Map<String, Object>> create(@Valid @RequestBody CreateExpenseRequest request) {
        Long org = currentUser.organizationId();
        String category = normalize(request.category(), CATEGORIES, "category");
        String method = request.paymentMethod() == null || request.paymentMethod().isBlank()
                ? "CASH" : normalize(request.paymentMethod(), PAYMENT_METHODS, "payment method");
        if (request.propertyId() != null) requirePropertyInOrg(org, request.propertyId());
        LocalDate date = request.expenseDate() == null ? LocalDate.now() : request.expenseDate();
        boolean approved = !request.requiresApproval();
        LocalDateTime now = LocalDateTime.now();
        jdbc.update("INSERT INTO expense(organization_id,property_facility_id,category,title,description,amount," +
                        "expense_date,payment_method,vendor_name,status,approved_by,approved_at,created_by,created_at,updated_at) " +
                        "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                org, request.propertyId(), category, request.title().trim(), request.description(), request.amount(),
                date, method, request.vendorName(), approved ? "APPROVED" : "PENDING",
                approved ? currentUser.userLoginId() : null, approved ? now : null,
                currentUser.userLoginId(), now, now);
        Long expenseId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        if (approved && "CASH".equals(method)) {
            expenseWriter.recordCashOut(org, request.propertyId(), expenseId, request.amount(),
                    request.title(), date, currentUser.userLoginId());
        }
        auditService.log(org, currentUser.userLoginId(), "EXPENSE_CREATED", "EXPENSE", expenseId,
                request.title() + " " + request.amount() + " (" + category + ")");
        return ApiResponse.ok("Expense recorded", Map.of("expenseId", expenseId, "status", approved ? "APPROVED" : "PENDING"));
    }

    /**
     * Corrects a mis-keyed expense (wrong amount, wrong category, …). Status is not part
     * of this — that stays with the approve/reject endpoint — but because the petty-cash
     * OUT row is a mirror of an approved CASH expense, any change here re-syncs it.
     */
    @PutMapping("/{expenseId}")
    @PreAuthorize("hasAnyRole('OWNER','PROPERTY_MANAGER','MANAGER','ACCOUNTANT')")
    @Transactional
    ApiResponse<Map<String, Object>> update(@PathVariable Long expenseId,
                                            @Valid @RequestBody UpdateExpenseRequest request) {
        Long org = currentUser.organizationId();
        Map<String, Object> existing = loadExpenseForUpdate(org, expenseId);
        String locked = lockReason(org, expenseId);
        if (locked != null) throw new BadRequestException(locked);

        String category = normalize(request.category(), CATEGORIES, "category");
        String method = request.paymentMethod() == null || request.paymentMethod().isBlank()
                ? "CASH" : normalize(request.paymentMethod(), PAYMENT_METHODS, "payment method");
        if (request.propertyId() != null) requirePropertyInOrg(org, request.propertyId());
        LocalDate date = request.expenseDate() != null ? request.expenseDate()
                : ((java.sql.Date) existing.get("expense_date")).toLocalDate();
        String title = request.title().trim();
        String status = (String) existing.get("status");

        jdbc.update("UPDATE expense SET property_facility_id=?, category=?, title=?, description=?, amount=?, " +
                        "expense_date=?, payment_method=?, vendor_name=?, updated_at=NOW() " +
                        "WHERE expense_id=? AND organization_id=?",
                request.propertyId(), category, title, request.description(), request.amount(),
                date, method, request.vendorName(), expenseId, org);
        syncCashMirror(org, expenseId, request.propertyId(), status, method, request.amount(), title, date);

        auditService.log(org, currentUser.userLoginId(), "EXPENSE_UPDATED", "EXPENSE", expenseId,
                existing.get("title") + " " + existing.get("amount") + " → " + title + " " + request.amount()
                        + " (" + category + ")");
        return ApiResponse.ok("Expense updated", Map.of("expenseId", expenseId, "status", status));
    }

    /**
     * Hard delete — an expense entered by mistake should leave no trace in any total, and
     * there is no "void" state in the schema. The mirrored petty-cash row goes with it;
     * `audit_log` keeps the record that it existed.
     */
    @DeleteMapping("/{expenseId}")
    @PreAuthorize("hasAnyRole('OWNER','PROPERTY_MANAGER','MANAGER','ACCOUNTANT')")
    @Transactional
    ApiResponse<Map<String, Object>> delete(@PathVariable Long expenseId) {
        Long org = currentUser.organizationId();
        Map<String, Object> existing = loadExpenseForUpdate(org, expenseId);
        String locked = lockReason(org, expenseId);
        if (locked != null) throw new BadRequestException(locked);

        jdbc.update("DELETE FROM petty_cash_entry WHERE organization_id=? AND expense_id=?", org, expenseId);
        jdbc.update("DELETE FROM expense WHERE expense_id=? AND organization_id=?", expenseId, org);
        auditService.log(org, currentUser.userLoginId(), "EXPENSE_DELETED", "EXPENSE", expenseId,
                existing.get("title") + " " + existing.get("amount") + " (" + existing.get("category") + ")");
        return ApiResponse.ok("Expense deleted", Map.of("expenseId", expenseId));
    }

    @PatchMapping("/{expenseId}/status")
    @Transactional
    ApiResponse<Map<String, Object>> updateStatus(@PathVariable Long expenseId, @Valid @RequestBody StatusRequest request) {
        Long org = currentUser.organizationId();
        String status = request.status().toUpperCase();
        if (!status.equals("APPROVED") && !status.equals("REJECTED")) {
            throw new BadRequestException("Status must be APPROVED or REJECTED");
        }
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT property_facility_id, title, amount, payment_method, expense_date, status FROM expense " +
                "WHERE expense_id=? AND organization_id=? FOR UPDATE", expenseId, org);
        if (rows.isEmpty()) throw new NotFoundException("Expense not found");
        Map<String, Object> expense = rows.getFirst();
        if (!"PENDING".equals(expense.get("status"))) throw new BadRequestException("Expense is already " + expense.get("status"));
        jdbc.update("UPDATE expense SET status=?, approved_by=?, approved_at=NOW(), updated_at=NOW() WHERE expense_id=?",
                status, currentUser.userLoginId(), expenseId);
        if (status.equals("APPROVED") && "CASH".equals(expense.get("payment_method"))) {
            Long propertyId = expense.get("property_facility_id") == null
                    ? null : ((Number) expense.get("property_facility_id")).longValue();
            expenseWriter.recordCashOut(org, propertyId, expenseId, decimal(expense.get("amount")),
                    (String) expense.get("title"), ((java.sql.Date) expense.get("expense_date")).toLocalDate(),
                    currentUser.userLoginId());
        }
        auditService.log(org, currentUser.userLoginId(), "EXPENSE_" + status, "EXPENSE", expenseId,
                expense.get("title") + " " + expense.get("amount"));
        return ApiResponse.ok("Expense " + status.toLowerCase(), Map.of("expenseId", expenseId, "status", status));
    }

    @PutMapping("/budget")
    @Transactional
    ApiResponse<Map<String, Object>> upsertBudget(@Valid @RequestBody BudgetRequest request) {
        Long org = currentUser.organizationId();
        String category = request.category() == null || request.category().isBlank() || "ALL".equalsIgnoreCase(request.category())
                ? "ALL" : normalize(request.category(), CATEGORIES, "category");
        if (request.propertyId() != null) requirePropertyInOrg(org, request.propertyId());
        YearMonth ym = parseMonth(request.month());
        long scope = request.propertyId() != null ? request.propertyId() : 0L;
        jdbc.update("INSERT INTO expense_budget(organization_id,property_facility_id,category,budget_month,amount,created_at,updated_at) " +
                        "VALUES(?,?,?,?,?,NOW(),NOW()) ON DUPLICATE KEY UPDATE amount=VALUES(amount), updated_at=NOW()",
                org, scope, category, ym.toString(), request.amount());
        auditService.log(org, currentUser.userLoginId(), "EXPENSE_BUDGET_SET", "EXPENSE_BUDGET", scope,
                category + " " + ym + " " + request.amount());
        return ApiResponse.ok("Budget saved", Map.of("category", category, "month", ym.toString(), "amount", request.amount()));
    }

    @PostMapping("/petty-cash")
    @Transactional
    ApiResponse<Map<String, Object>> addPettyCash(@Valid @RequestBody PettyCashRequest request) {
        Long org = currentUser.organizationId();
        String type = request.entryType().toUpperCase();
        if (!type.equals("IN") && !type.equals("OUT")) throw new BadRequestException("entryType must be IN or OUT");
        if (request.propertyId() != null) requirePropertyInOrg(org, request.propertyId());
        LocalDate date = request.entryDate() == null ? LocalDate.now() : request.entryDate();
        jdbc.update("INSERT INTO petty_cash_entry(organization_id,property_facility_id,entry_type,amount,note,entry_date," +
                        "created_by,created_at,updated_at) VALUES(?,?,?,?,?,?,?,NOW(),NOW())",
                org, request.propertyId() != null ? request.propertyId() : 0L, type, request.amount(),
                request.note(), date, currentUser.userLoginId());
        auditService.log(org, currentUser.userLoginId(), "PETTY_CASH_" + type, "PETTY_CASH",
                request.propertyId(), type + " " + request.amount());
        YearMonth ym = YearMonth.from(date);
        return ApiResponse.ok("Entry recorded", pettyCash(org, request.propertyId(), ym.atDay(1), ym.atEndOfMonth()));
    }

    // ─────────────────────────────────────────────────────────────── helpers ──

    private List<Map<String, Object>> trend(Long org, Long propertyId, YearMonth current) {
        YearMonth from = current.minusMonths(5);
        LocalDate fromDate = from.atDay(1), toDate = current.atEndOfMonth();
        String prop = propertyId != null ? " AND property_facility_id=?" : "";
        Map<String, BigDecimal> expenses = monthTotals(jdbc.queryForList(
                "SELECT DATE_FORMAT(expense_date,'%Y-%m') m, SUM(amount) total FROM expense " +
                "WHERE organization_id=? AND status IN " + SPENT_STATUSES + " AND expense_date BETWEEN ? AND ?" + prop +
                " GROUP BY m", args(org, fromDate, toDate, propertyId != null ? new Object[]{propertyId} : new Object[0])));
        String incomeProp = propertyId != null
                ? " AND party_id IN (SELECT fp.party_id FROM facility_party fp WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')"
                : "";
        Object[] incomeArgs = propertyId != null
                ? new Object[]{org, fromDate, toDate, org, propertyId}
                : new Object[]{org, fromDate, toDate};
        Map<String, BigDecimal> income = monthTotals(jdbc.queryForList(
                "SELECT DATE_FORMAT(payment_date,'%Y-%m') m, SUM(amount) total FROM payment " +
                "WHERE organization_id=? AND status='RECEIVED' AND payment_date BETWEEN ? AND ?" + incomeProp +
                " GROUP BY m", incomeArgs));
        List<Map<String, Object>> points = new ArrayList<>();
        for (YearMonth m = from; !m.isAfter(current); m = m.plusMonths(1)) {
            BigDecimal exp = expenses.getOrDefault(m.toString(), BigDecimal.ZERO);
            BigDecimal inc = income.getOrDefault(m.toString(), BigDecimal.ZERO);
            Map<String, Object> point = new LinkedHashMap<>();
            point.put("month", m.toString());
            point.put("expense", exp);
            point.put("income", inc);
            point.put("profit", inc.subtract(exp));
            points.add(point);
        }
        return points;
    }

    private Map<String, Object> pettyCash(Long org, Long propertyId, LocalDate start, LocalDate end) {
        String prop = propertyId != null ? " AND property_facility_id=?" : "";
        Object[] scope = propertyId != null ? new Object[]{propertyId} : new Object[0];
        BigDecimal opening = amount(
                "SELECT COALESCE(SUM(CASE WHEN entry_type='IN' THEN amount ELSE -amount END),0) " +
                "FROM petty_cash_entry WHERE organization_id=? AND entry_date<?" + prop, args(org, start, scope));
        BigDecimal cashIn = amount(
                "SELECT COALESCE(SUM(amount),0) FROM petty_cash_entry WHERE organization_id=? AND entry_type='IN' AND entry_date BETWEEN ? AND ?" + prop,
                args(org, start, end, scope));
        BigDecimal cashOut = amount(
                "SELECT COALESCE(SUM(amount),0) FROM petty_cash_entry WHERE organization_id=? AND entry_type='OUT' AND entry_date BETWEEN ? AND ?" + prop,
                args(org, start, end, scope));
        Map<String, Object> petty = new LinkedHashMap<>();
        petty.put("opening", opening);
        petty.put("cashIn", cashIn);
        petty.put("cashOut", cashOut);
        petty.put("balance", opening.add(cashIn).subtract(cashOut));
        return petty;
    }

    private List<String> insights(Long org, Long propertyId, LocalDate start, LocalDate end,
                                  LocalDate prevStart, LocalDate prevEnd,
                                  List<Map<String, Object>> categories, BigDecimal budget, BigDecimal total) {
        List<String> insights = new ArrayList<>();
        String prop = propertyId != null ? " AND property_facility_id=?" : "";
        Object[] scope = propertyId != null ? new Object[]{propertyId} : new Object[0];
        Map<String, BigDecimal> prev = new LinkedHashMap<>();
        for (Map<String, Object> row : jdbc.queryForList(
                "SELECT category, SUM(amount) total FROM expense WHERE organization_id=? AND status IN " + SPENT_STATUSES +
                " AND expense_date BETWEEN ? AND ?" + prop + " GROUP BY category", args(org, prevStart, prevEnd, scope))) {
            prev.put((String) row.get("category"), decimal(row.get("total")));
        }
        BigDecimal savings = BigDecimal.ZERO;
        for (Map<String, Object> row : categories) {
            String category = (String) row.get("category");
            BigDecimal cur = decimal(row.get("total"));
            BigDecimal was = prev.get(category);
            if (was == null || was.signum() <= 0) continue;
            BigDecimal pct = cur.subtract(was).multiply(BigDecimal.valueOf(100)).divide(was, 0, RoundingMode.HALF_UP);
            if (pct.compareTo(BigDecimal.valueOf(15)) >= 0) {
                if (insights.size() < 2) {
                    insights.add(displayName(category) + " expenses increased by " + pct + "% compared to last month.");
                }
                savings = savings.add(cur.subtract(was));
            }
        }
        if (budget != null && budget.signum() > 0) {
            BigDecimal utilization = total.multiply(BigDecimal.valueOf(100)).divide(budget, 0, RoundingMode.HALF_UP);
            if (utilization.compareTo(BigDecimal.valueOf(80)) >= 0) {
                insights.add("Monthly budget utilization reached " + utilization + "%.");
            }
        }
        if (savings.signum() > 0) {
            insights.add("Potential monthly savings: Rs." + savings.setScale(0, RoundingMode.HALF_UP) +
                    " by bringing rising categories back to last month's spend.");
        }
        if (insights.isEmpty()) {
            insights.add(total.signum() > 0
                    ? "Spending is stable — no unusual movement versus last month."
                    : "Record a few expenses to unlock spending insights.");
        }
        return insights;
    }

    private BigDecimal overallBudget(Long org, Long propertyId, YearMonth ym) {
        List<BigDecimal> rows = jdbc.queryForList(
                "SELECT amount FROM expense_budget WHERE organization_id=? AND property_facility_id=? AND category='ALL' AND budget_month=?",
                BigDecimal.class, org, propertyId != null ? propertyId : 0L, ym.toString());
        return rows.isEmpty() ? null : rows.getFirst();
    }

    private void requirePropertyInOrg(Long org, Long propertyId) {
        Long count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM facility WHERE facility_id=? AND organization_id=?", Long.class, propertyId, org);
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

    /** Camel-cased row for the app (same aliases as the list endpoint). */
    private Map<String, Object> loadExpense(Long org, Long expenseId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT expense_id expenseId, property_facility_id propertyId, title, category, description, amount, " +
                "payment_method paymentMethod, vendor_name vendorName, status, expense_date expenseDate " +
                "FROM expense WHERE expense_id=? AND organization_id=?", expenseId, org);
        if (rows.isEmpty()) throw new NotFoundException("Expense not found");
        return rows.getFirst();
    }

    /** Raw column names + row lock, for the mutating paths. */
    private Map<String, Object> loadExpenseForUpdate(Long org, Long expenseId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT property_facility_id, title, category, amount, payment_method, expense_date, status " +
                "FROM expense WHERE expense_id=? AND organization_id=? FOR UPDATE", expenseId, org);
        if (rows.isEmpty()) throw new NotFoundException("Expense not found");
        return rows.getFirst();
    }

    /**
     * null when the expense is a plain manual entry. A salary expense is owned by the
     * staff module (`staff_salary_payment.expense_id`) — editing it here would silently
     * desync payroll, so it is redirected instead.
     */
    private String lockReason(Long org, Long expenseId) {
        Long salaryLinks = jdbc.queryForObject(
                "SELECT COUNT(*) FROM staff_salary_payment WHERE organization_id=? AND expense_id=?",
                Long.class, org, expenseId);
        if (salaryLinks != null && salaryLinks > 0) {
            return "This is a staff salary payment. Manage it from the Staff screen.";
        }
        return null;
    }

    /**
     * Keeps the petty-cash OUT row in step with the expense it mirrors: present only while
     * the expense is an approved CASH spend, and carrying its current amount/date/note.
     */
    private void syncCashMirror(Long org, Long expenseId, Long propertyId, String status,
                                String method, BigDecimal amount, String title, LocalDate date) {
        boolean mirrored = "CASH".equals(method) && ("APPROVED".equals(status) || "PAID".equals(status));
        if (!mirrored) {
            jdbc.update("DELETE FROM petty_cash_entry WHERE organization_id=? AND expense_id=?", org, expenseId);
            return;
        }
        int updated = jdbc.update(
                "UPDATE petty_cash_entry SET property_facility_id=?, amount=?, note=?, entry_date=?, updated_at=NOW() " +
                "WHERE organization_id=? AND expense_id=?",
                propertyId != null ? propertyId : 0L, amount, title, date, org, expenseId);
        if (updated == 0) {
            expenseWriter.recordCashOut(org, propertyId, expenseId, amount, title, date, currentUser.userLoginId());
        }
    }

    private static String normalize(String value, Set<String> allowed, String label) {
        String normalized = value == null ? "" : value.trim().toUpperCase().replace(' ', '_');
        if (!allowed.contains(normalized)) {
            throw new BadRequestException("Invalid " + label + ": " + value + " (allowed: " + String.join(", ", allowed) + ")");
        }
        return normalized;
    }

    private static String displayName(String category) {
        String lower = category.toLowerCase().replace('_', ' ');
        return Character.toUpperCase(lower.charAt(0)) + lower.substring(1);
    }

    private static Map<String, BigDecimal> monthTotals(List<Map<String, Object>> rows) {
        Map<String, BigDecimal> totals = new LinkedHashMap<>();
        for (Map<String, Object> row : rows) totals.put((String) row.get("m"), decimal(row.get("total")));
        return totals;
    }

    private BigDecimal amount(String sql, Object[] args) {
        BigDecimal value = jdbc.queryForObject(sql, BigDecimal.class, args);
        return value == null ? BigDecimal.ZERO : value;
    }

    private static Object[] args(Object a, Object[] rest) {
        Object[] result = new Object[1 + rest.length];
        result[0] = a;
        System.arraycopy(rest, 0, result, 1, rest.length);
        return result;
    }

    private static Object[] args(Object a, Object b, Object[] rest) {
        Object[] result = new Object[2 + rest.length];
        result[0] = a;
        result[1] = b;
        System.arraycopy(rest, 0, result, 2, rest.length);
        return result;
    }

    private static Object[] args(Object a, Object b, Object c, Object[] rest) {
        Object[] result = new Object[3 + rest.length];
        result[0] = a;
        result[1] = b;
        result[2] = c;
        System.arraycopy(rest, 0, result, 3, rest.length);
        return result;
    }

    private static BigDecimal decimal(Object value) {
        return value instanceof BigDecimal decimal ? decimal : new BigDecimal(value.toString());
    }

    // ─────────────────────────────────────────────────────────────── requests ──

    public record CreateExpenseRequest(
            @NotBlank @Size(max = 120) String title,
            @NotBlank String category,
            @NotNull @DecimalMin("0.01") BigDecimal amount,
            LocalDate expenseDate,
            String paymentMethod,
            Long propertyId,
            @Size(max = 120) String vendorName,
            @Size(max = 500) String description,
            boolean requiresApproval) {}

    /** Same shape as create, minus `requiresApproval` — status changes go through PATCH /status. */
    public record UpdateExpenseRequest(
            @NotBlank @Size(max = 120) String title,
            @NotBlank String category,
            @NotNull @DecimalMin("0.01") BigDecimal amount,
            LocalDate expenseDate,
            String paymentMethod,
            Long propertyId,
            @Size(max = 120) String vendorName,
            @Size(max = 500) String description) {}

    public record StatusRequest(@NotBlank String status) {}

    public record BudgetRequest(Long propertyId, String category, String month,
                                @NotNull @DecimalMin("0.01") BigDecimal amount) {}

    public record PettyCashRequest(Long propertyId, @NotBlank String entryType,
                                   @NotNull @DecimalMin("0.01") BigDecimal amount,
                                   @Size(max = 255) String note, LocalDate entryDate) {}
}
