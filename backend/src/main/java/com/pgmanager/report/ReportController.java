package com.pgmanager.report;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.security.PropertyAccessGuard;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Downloadable reports. JdbcTemplate throughout (aggregate-heavy, same rationale
 * as BillingController). Each endpoint returns the rows *and* a summary; the app
 * renders the PDF, so the layout can change without a backend release.
 */
@RestController
@RequestMapping("/api/reports")
@RequiredArgsConstructor
public class ReportController {
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;
    private final PropertyAccessGuard propertyAccessGuard;

    /**
     * Rent Collection — one row per invoice raised for the given month, with what was
     * charged, what came in, and what is still outstanding.
     *
     * Field notes:
     * <ul>
     *   <li><b>rentAmount</b> is the MONTHLY_RENT line item (base rent, AC excluded — see V18).</li>
     *   <li><b>additionalCharges</b> is every other positive line (AC_CHARGES, SECURITY_DEPOSIT,
     *       TEMP_STAY, OTHER), so rent + additional − discount always reconciles to the total.</li>
     *   <li><b>discount</b> sums negative line items; the schema has no dedicated DISCOUNT type
     *       yet, so today this is 0 unless an invoice was edited down with a credit line.</li>
     *   <li><b>roomBed</b> is resolved from the occupancy that covers the invoice month, not the
     *       tenant's current bed — a tenant who moved in March still reports March's bed.</li>
     *   <li><b>status</b> is derived from the money (Paid / Partial / Pending), not the stored
     *       status column, so an OVERDUE-but-part-paid invoice reads as Partial.</li>
     * </ul>
     */
    @GetMapping("/rent-collection")
    ApiResponse<Map<String, Object>> rentCollection(@RequestParam(required = false) Long propertyId,
                                                    @RequestParam(required = false) String month) {
        // Scope to what this login may see: unchanged for an owner; a property-scoped
        // login gets their own property substituted in, or a 403/400.
        propertyId = propertyAccessGuard.resolvePropertyId(propertyId);
        Long org = currentUser.organizationId();
        YearMonth ym = parseMonth(month);
        LocalDate start = ym.atDay(1), end = ym.atEndOfMonth();

        // Scalar subqueries rather than joins: a tenant can hold several occupancy /
        // membership rows in one month, and a join would emit a duplicate invoice row
        // for each (and need a GROUP BY that ONLY_FULL_GROUP_BY rejects).
        List<Object> args = new ArrayList<>();
        args.add(end);      // occupancy overlaps the month …
        args.add(start);    // … from_date <= monthEnd AND (thru_date IS NULL OR >= monthStart)
        args.add(org);
        args.add(start);
        args.add(end);
        String propFilter = "";
        if (propertyId != null) {
            propFilter = " AND ba.party_id IN (SELECT fp.party_id FROM facility_party fp " +
                    "WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')";
            args.add(org);
            args.add(propertyId);
        }

        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT i.invoice_id invoiceId, i.invoice_number invoiceNo, i.invoice_month rentMonth, " +
                "       i.due_date dueDate, i.total_amount totalAmount, i.paid_amount paidAmount, " +
                "       (i.total_amount - i.paid_amount) dueAmount, " +
                "       per.full_name tenantName, " +
                // Line-item rollups: base rent, everything else charged, any credit lines.
                "       COALESCE((SELECT SUM(ii.amount) FROM invoice_item ii " +
                "                 WHERE ii.invoice_id=i.invoice_id AND ii.item_type_id='MONTHLY_RENT'),0) rentAmount, " +
                "       COALESCE((SELECT SUM(ii.amount) FROM invoice_item ii " +
                "                 WHERE ii.invoice_id=i.invoice_id AND ii.item_type_id<>'MONTHLY_RENT' AND ii.amount>0),0) additionalCharges, " +
                "       COALESCE((SELECT -SUM(ii.amount) FROM invoice_item ii " +
                "                 WHERE ii.invoice_id=i.invoice_id AND ii.amount<0),0) discount, " +
                // Bed held during the invoice month, with its room.
                "       COALESCE((SELECT TRIM(CONCAT(COALESCE(room.facility_name,''), " +
                "                       CASE WHEN bed.facility_name IS NULL THEN '' " +
                "                            ELSE CONCAT(' / ', bed.facility_name) END)) " +
                "                 FROM facility_party occ " +
                "                 JOIN facility bed ON bed.facility_id=occ.facility_id AND bed.facility_type_id='BED' " +
                "                 LEFT JOIN facility_group_member bgm ON bgm.child_facility_id=bed.facility_id AND bgm.thru_date IS NULL " +
                "                 LEFT JOIN facility room ON room.facility_id=bgm.parent_facility_id AND room.facility_type_id='ROOM' " +
                "                 WHERE occ.party_id=ba.party_id AND occ.organization_id=i.organization_id " +
                "                   AND occ.role_type_id IN ('OCCUPANT','TEMP_OCCUPANT') " +
                "                   AND occ.from_date <= ? AND (occ.thru_date IS NULL OR occ.thru_date >= ?) " +
                "                 ORDER BY occ.thru_date IS NULL DESC, occ.from_date DESC LIMIT 1),'') roomBed, " +
                // Property from the tenant's property-scoped TENANT membership.
                "       COALESCE((SELECT f.facility_name FROM facility_party pm " +
                "                 JOIN facility f ON f.facility_id=pm.facility_id AND f.facility_type_id='PROPERTY' " +
                "                 WHERE pm.party_id=ba.party_id AND pm.organization_id=i.organization_id " +
                "                   AND pm.role_type_id='TENANT' AND pm.facility_id<>i.organization_id " +
                "                 ORDER BY pm.thru_date IS NULL DESC, pm.from_date DESC LIMIT 1),'') property, " +
                // Most recent receipt against this invoice.
                "       (SELECT p.payment_date FROM payment_allocation a JOIN payment p ON p.payment_id=a.payment_id " +
                "        WHERE a.invoice_id=i.invoice_id AND p.status='RECEIVED' " +
                "        ORDER BY p.payment_date DESC, p.payment_id DESC LIMIT 1) paymentDate, " +
                "       (SELECT p.payment_mode FROM payment_allocation a JOIN payment p ON p.payment_id=a.payment_id " +
                "        WHERE a.invoice_id=i.invoice_id AND p.status='RECEIVED' " +
                "        ORDER BY p.payment_date DESC, p.payment_id DESC LIMIT 1) paymentMode " +
                "FROM invoice i " +
                "JOIN billing_account ba ON ba.billing_account_id = i.billing_account_id " +
                "JOIN person per ON per.party_id = ba.party_id " +
                "WHERE i.organization_id = ? AND i.invoice_month BETWEEN ? AND ?" + propFilter +
                " ORDER BY per.full_name, i.invoice_number",
                args.toArray());

        BigDecimal totalAmount = BigDecimal.ZERO, paidAmount = BigDecimal.ZERO, dueAmount = BigDecimal.ZERO;
        int paid = 0, partial = 0, pending = 0;
        List<Map<String, Object>> items = new ArrayList<>(rows.size());
        for (Map<String, Object> row : rows) {
            Map<String, Object> item = new LinkedHashMap<>(row);
            BigDecimal total = decimal(row.get("totalAmount"));
            BigDecimal received = decimal(row.get("paidAmount"));
            BigDecimal due = total.subtract(received);
            String status = received.compareTo(total) >= 0 && total.signum() > 0 ? "Paid"
                    : received.signum() > 0 ? "Partial" : "Pending";
            switch (status) {
                case "Paid" -> paid++;
                case "Partial" -> partial++;
                default -> pending++;
            }
            item.put("status", status);
            items.add(item);
            totalAmount = totalAmount.add(total);
            paidAmount = paidAmount.add(received);
            dueAmount = dueAmount.add(due);
        }

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("invoiceCount", items.size());
        summary.put("totalAmount", totalAmount);
        summary.put("paidAmount", paidAmount);
        summary.put("dueAmount", dueAmount);
        summary.put("paidCount", paid);
        summary.put("partialCount", partial);
        summary.put("pendingCount", pending);
        summary.put("collectionPct", totalAmount.signum() > 0
                ? paidAmount.multiply(BigDecimal.valueOf(100))
                        .divide(totalAmount, 0, java.math.RoundingMode.HALF_UP)
                : BigDecimal.ZERO);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("month", ym.toString());
        result.put("propertyName", propertyId == null ? null : propertyName(org, propertyId));
        result.put("organizationName", propertyName(org, org));
        result.put("summary", summary);
        result.put("items", items);
        return ApiResponse.ok(result);
    }

    /**
     * Outstanding Dues — one row per tenant who still owes money, as of the end of the
     * selected month (or today, whichever is earlier, so "days overdue" never runs into
     * the future for a historical month).
     *
     * <p>An unpaid invoice counts when its {@code invoice_month} is on or before the selected
     * month and it still has a balance, so the report is cumulative rather than
     * month-in-isolation: a tenant three months behind shows the whole arrears.
     * {@code reminderStatus} comes from the last RENT_REMINDER notification sent to them.
     */
    @GetMapping("/outstanding-dues")
    ApiResponse<Map<String, Object>> outstandingDues(@RequestParam(required = false) Long propertyId,
                                                     @RequestParam(required = false) String month,
                                                     @RequestParam(required = false) Long partyId) {
        // Scope to what this login may see: unchanged for an owner; a property-scoped
        // login gets their own property substituted in, or a 403/400.
        propertyId = propertyAccessGuard.resolvePropertyId(propertyId);
        Long org = currentUser.organizationId();
        YearMonth ym = parseMonth(month);
        LocalDate monthEnd = ym.atEndOfMonth();
        LocalDate asOf = monthEnd.isAfter(LocalDate.now()) ? LocalDate.now() : monthEnd;

        List<Object> args = new ArrayList<>();
        args.add(asOf);                 // roomBed: occupancy covering the as-of date
        args.add(asOf);
        args.add(asOf);                 // daysOverdue baseline
        args.add(org);
        args.add(ym.atDay(1));          // invoice_month <= selected month
        String filters = "";
        if (propertyId != null) {
            filters += " AND ba.party_id IN (SELECT fp.party_id FROM facility_party fp " +
                    "WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')";
            args.add(org);
            args.add(propertyId);
        }
        if (partyId != null) {
            filters += " AND ba.party_id=?";
            args.add(partyId);
        }

        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT ba.party_id partyId, per.full_name tenantName, " +
                "       COALESCE(per.mobile_number,'') phone, " +
                "       COALESCE((SELECT f.facility_name FROM facility_party pm " +
                "                 JOIN facility f ON f.facility_id=pm.facility_id AND f.facility_type_id='PROPERTY' " +
                "                 WHERE pm.party_id=ba.party_id AND pm.organization_id=i.organization_id " +
                "                   AND pm.role_type_id='TENANT' AND pm.facility_id<>i.organization_id " +
                "                 ORDER BY pm.thru_date IS NULL DESC, pm.from_date DESC LIMIT 1),'') property, " +
                "       COALESCE((SELECT TRIM(CONCAT(COALESCE(room.facility_name,''), " +
                "                       CASE WHEN bed.facility_name IS NULL THEN '' " +
                "                            ELSE CONCAT(' / ', bed.facility_name) END)) " +
                "                 FROM facility_party occ " +
                "                 JOIN facility bed ON bed.facility_id=occ.facility_id AND bed.facility_type_id='BED' " +
                "                 LEFT JOIN facility_group_member bgm ON bgm.child_facility_id=bed.facility_id AND bgm.thru_date IS NULL " +
                "                 LEFT JOIN facility room ON room.facility_id=bgm.parent_facility_id AND room.facility_type_id='ROOM' " +
                "                 WHERE occ.party_id=ba.party_id AND occ.organization_id=i.organization_id " +
                "                   AND occ.role_type_id IN ('OCCUPANT','TEMP_OCCUPANT') " +
                "                   AND occ.from_date <= ? AND (occ.thru_date IS NULL OR occ.thru_date >= ?) " +
                "                 ORDER BY occ.thru_date IS NULL DESC, occ.from_date DESC LIMIT 1),'') roomBed, " +
                "       SUM(i.total_amount - i.paid_amount) dueAmount, " +
                "       MIN(i.due_date) dueSince, " +
                "       GREATEST(CAST(? AS date) - MIN(i.due_date), 0) daysOverdue, " +
                "       (SELECT MAX(p.payment_date) FROM payment p " +
                "        WHERE p.organization_id=i.organization_id AND p.party_id=ba.party_id AND p.status='RECEIVED') lastPaymentDate, " +
                "       MIN(CASE WHEN i.due_date >= CURRENT_DATE THEN i.due_date END) nextDueDate, " +
                "       (SELECT MAX(n.created_at) FROM notification n " +
                "        JOIN notification_recipient nr ON nr.notification_id=n.notification_id " +
                "        WHERE n.organization_id=i.organization_id AND nr.party_id=ba.party_id " +
                "          AND n.category_id='RENT_REMINDER') lastReminderAt " +
                "FROM invoice i " +
                "JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "JOIN person per ON per.party_id=ba.party_id " +
                "WHERE i.organization_id=? AND i.invoice_month <= ? " +
                "  AND i.status <> 'CANCELLED' AND (i.total_amount - i.paid_amount) > 0" + filters +
                " GROUP BY ba.party_id, per.full_name, per.mobile_number, i.organization_id " +
                " ORDER BY dueAmount DESC, per.full_name",
                args.toArray());

        BigDecimal totalDue = BigDecimal.ZERO;
        int overdue = 0;
        List<Map<String, Object>> items = new ArrayList<>(rows.size());
        for (Map<String, Object> row : rows) {
            Map<String, Object> item = new LinkedHashMap<>(row);
            Object reminder = row.get("lastReminderAt");
            item.put("reminderStatus", reminder == null ? "Not sent" : "Sent");
            item.remove("lastReminderAt");
            item.put("lastReminderAt", reminder);
            totalDue = totalDue.add(decimal(row.get("dueAmount")));
            if (toInt(row.get("daysOverdue")) > 0) overdue++;
            items.add(item);
        }

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("tenantCount", items.size());
        summary.put("totalDue", totalDue);
        summary.put("overdueCount", overdue);
        summary.put("asOf", asOf.toString());

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("month", ym.toString());
        result.put("propertyName", propertyId == null ? null : propertyName(org, propertyId));
        result.put("organizationName", propertyName(org, org));
        result.put("summary", summary);
        result.put("items", items);
        return ApiResponse.ok(result);
    }

    /**
     * Expense Report — the month's operational spend, one row per expense.
     * Only APPROVED/PAID rows count, matching what the expenses dashboard totals;
     * a PENDING (unapproved) expense is not money out yet.
     */
    @GetMapping("/expenses")
    ApiResponse<Map<String, Object>> expenses(@RequestParam(required = false) Long propertyId,
                                              @RequestParam(required = false) String month,
                                              @RequestParam(required = false) String category) {
        // Scope to what this login may see: unchanged for an owner; a property-scoped
        // login gets their own property substituted in, or a 403/400.
        propertyId = propertyAccessGuard.resolvePropertyId(propertyId);
        Long org = currentUser.organizationId();
        YearMonth ym = parseMonth(month);

        List<Object> args = new ArrayList<>(List.of(org, ym.atDay(1), ym.atEndOfMonth()));
        String filters = "";
        if (propertyId != null) {
            filters += " AND e.property_facility_id=?";
            args.add(propertyId);
        }
        if (category != null && !category.isBlank() && !"ALL".equalsIgnoreCase(category)) {
            filters += " AND e.category=?";
            args.add(category.trim().toUpperCase());
        }

        List<Map<String, Object>> items = jdbc.queryForList(
                "SELECT e.expense_id expenseId, e.expense_date expenseDate, e.category, " +
                "       COALESCE(e.vendor_name,'') vendor, COALESCE(e.description, e.title) description, " +
                "       e.title, COALESCE(prop.facility_name,'') property, e.amount, " +
                "       e.payment_method paymentMethod, " +
                // Paid By: whoever approved it, else whoever entered it.
                "       COALESCE(payer.full_name, ul.username, '') paidBy " +
                "FROM expense e " +
                "LEFT JOIN facility prop ON prop.facility_id=e.property_facility_id AND prop.facility_type_id='PROPERTY' " +
                "LEFT JOIN user_login ul ON ul.user_login_id=COALESCE(e.approved_by, e.created_by) " +
                "LEFT JOIN person payer ON payer.party_id=ul.party_id " +
                "WHERE e.organization_id=? AND e.status IN ('APPROVED','PAID') " +
                "  AND e.expense_date BETWEEN ? AND ?" + filters +
                " ORDER BY e.expense_date, e.expense_id",
                args.toArray());

        BigDecimal total = BigDecimal.ZERO;
        Map<String, BigDecimal> byCategory = new LinkedHashMap<>();
        for (Map<String, Object> item : items) {
            BigDecimal amount = decimal(item.get("amount"));
            total = total.add(amount);
            byCategory.merge("" + item.get("category"), amount, BigDecimal::add);
        }
        List<Map<String, Object>> categories = new ArrayList<>();
        byCategory.entrySet().stream()
                .sorted((a, b) -> b.getValue().compareTo(a.getValue()))
                .forEach(e -> categories.add(Map.of("category", e.getKey(), "total", e.getValue())));

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("expenseCount", items.size());
        summary.put("totalAmount", total);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("month", ym.toString());
        result.put("category", category == null || category.isBlank() ? "ALL" : category.toUpperCase());
        result.put("propertyName", propertyId == null ? null : propertyName(org, propertyId));
        result.put("organizationName", propertyName(org, org));
        result.put("summary", summary);
        result.put("categories", categories);
        result.put("items", items);
        return ApiResponse.ok(result);
    }

    /**
     * Profit &amp; Loss for a date range, on a **cash basis** — money actually received and
     * actually spent, not what was invoiced. That keeps it reconcilable with the
     * transactions ledger, which treats a RECEIVED payment as income.
     *
     * <p>Total Rent is the slice of receipts allocated to invoices; Other Income is the
     * remainder (advances, unallocated receipts), so rent + other == total income exactly.
     */
    @GetMapping("/profit-loss")
    ApiResponse<Map<String, Object>> profitLoss(@RequestParam(required = false) Long propertyId,
                                                @RequestParam(required = false) String from,
                                                @RequestParam(required = false) String to) {
        // Scope to what this login may see: unchanged for an owner; a property-scoped
        // login gets their own property substituted in, or a 403/400.
        propertyId = propertyAccessGuard.resolvePropertyId(propertyId);
        Long org = currentUser.organizationId();
        LocalDate today = LocalDate.now();
        LocalDate start = parseDate(from, YearMonth.from(today).atDay(1));
        LocalDate end = parseDate(to, YearMonth.from(today).atEndOfMonth());
        if (end.isBefore(start)) {
            LocalDate swap = start;
            start = end;
            end = swap;
        }

        String payProp = propertyId != null
                ? " AND p.party_id IN (SELECT fp.party_id FROM facility_party fp " +
                  "WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')"
                : "";
        Object[] payArgs = propertyId != null
                ? new Object[]{org, start, end, org, propertyId}
                : new Object[]{org, start, end};

        BigDecimal totalIncome = amount(
                "SELECT COALESCE(SUM(p.amount),0) FROM payment p " +
                "WHERE p.organization_id=? AND p.status='RECEIVED' AND p.payment_date BETWEEN ? AND ?" + payProp,
                payArgs);
        BigDecimal rentIncome = amount(
                "SELECT COALESCE(SUM(a.amount),0) FROM payment_allocation a " +
                "JOIN payment p ON p.payment_id=a.payment_id " +
                "WHERE p.organization_id=? AND p.status='RECEIVED' AND p.payment_date BETWEEN ? AND ?" + payProp,
                payArgs);
        // Allocations can exceed the receipts of the window when an older advance is applied
        // inside it; clamp so "other income" never goes negative.
        if (rentIncome.compareTo(totalIncome) > 0) rentIncome = totalIncome;
        BigDecimal otherIncome = totalIncome.subtract(rentIncome);

        String expProp = propertyId != null ? " AND e.property_facility_id=?" : "";
        Object[] expArgs = propertyId != null
                ? new Object[]{org, start, end, propertyId}
                : new Object[]{org, start, end};
        BigDecimal totalExpenses = amount(
                "SELECT COALESCE(SUM(e.amount),0) FROM expense e " +
                "WHERE e.organization_id=? AND e.status IN ('APPROVED','PAID') AND e.expense_date BETWEEN ? AND ?" + expProp,
                expArgs);

        BigDecimal netProfit = totalIncome.subtract(totalExpenses);
        BigDecimal margin = totalIncome.signum() > 0
                ? netProfit.multiply(BigDecimal.valueOf(100))
                        .divide(totalIncome, 1, java.math.RoundingMode.HALF_UP)
                : BigDecimal.ZERO;

        // Month-by-month split so a multi-month range is actionable, not just one number.
        List<Map<String, Object>> months = new ArrayList<>();
        YearMonth cursor = YearMonth.from(start), last = YearMonth.from(end);
        while (!cursor.isAfter(last)) {
            LocalDate mStart = cursor.atDay(1).isBefore(start) ? start : cursor.atDay(1);
            LocalDate mEnd = cursor.atEndOfMonth().isAfter(end) ? end : cursor.atEndOfMonth();
            Object[] mPayArgs = propertyId != null
                    ? new Object[]{org, mStart, mEnd, org, propertyId}
                    : new Object[]{org, mStart, mEnd};
            Object[] mExpArgs = propertyId != null
                    ? new Object[]{org, mStart, mEnd, propertyId}
                    : new Object[]{org, mStart, mEnd};
            BigDecimal income = amount(
                    "SELECT COALESCE(SUM(p.amount),0) FROM payment p " +
                    "WHERE p.organization_id=? AND p.status='RECEIVED' AND p.payment_date BETWEEN ? AND ?" + payProp,
                    mPayArgs);
            BigDecimal spend = amount(
                    "SELECT COALESCE(SUM(e.amount),0) FROM expense e " +
                    "WHERE e.organization_id=? AND e.status IN ('APPROVED','PAID') AND e.expense_date BETWEEN ? AND ?" + expProp,
                    mExpArgs);
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("month", cursor.toString());
            row.put("income", income);
            row.put("expenses", spend);
            row.put("net", income.subtract(spend));
            months.add(row);
            cursor = cursor.plusMonths(1);
        }

        List<Map<String, Object>> expenseByCategory = jdbc.queryForList(
                "SELECT e.category, SUM(e.amount) total FROM expense e " +
                "WHERE e.organization_id=? AND e.status IN ('APPROVED','PAID') AND e.expense_date BETWEEN ? AND ?" + expProp +
                " GROUP BY e.category ORDER BY total DESC",
                expArgs);

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("totalRent", rentIncome);
        summary.put("otherIncome", otherIncome);
        summary.put("totalIncome", totalIncome);
        summary.put("totalExpenses", totalExpenses);
        summary.put("netProfit", netProfit);
        summary.put("profitMarginPct", margin);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("fromDate", start.toString());
        result.put("toDate", end.toString());
        result.put("propertyName", propertyId == null ? null : propertyName(org, propertyId));
        result.put("organizationName", propertyName(org, org));
        result.put("summary", summary);
        result.put("months", months);
        result.put("expenseByCategory", expenseByCategory);
        return ApiResponse.ok(result);
    }

    private BigDecimal amount(String sql, Object[] args) {
        BigDecimal value = jdbc.queryForObject(sql, BigDecimal.class, args);
        return value == null ? BigDecimal.ZERO : value;
    }

    private static LocalDate parseDate(String raw, LocalDate fallback) {
        if (raw == null || raw.isBlank()) return fallback;
        try {
            return LocalDate.parse(raw.trim());
        } catch (DateTimeParseException e) {
            return fallback;
        }
    }

    private static int toInt(Object value) {
        return value instanceof Number n ? n.intValue()
                : value == null ? 0 : Integer.parseInt(value.toString());
    }

    private String propertyName(Long org, Long facilityId) {
        List<String> names = jdbc.queryForList(
                "SELECT facility_name FROM facility WHERE facility_id=? AND (facility_id=? OR organization_id=?)",
                String.class, facilityId, org, org);
        return names.isEmpty() ? null : names.getFirst();
    }

    private static YearMonth parseMonth(String month) {
        if (month == null || month.isBlank()) return YearMonth.now();
        try {
            return YearMonth.parse(month.trim());
        } catch (DateTimeParseException e) {
            return YearMonth.now();
        }
    }

    private static BigDecimal decimal(Object value) {
        if (value == null) return BigDecimal.ZERO;
        return value instanceof BigDecimal decimal ? decimal : new BigDecimal(value.toString());
    }
}
