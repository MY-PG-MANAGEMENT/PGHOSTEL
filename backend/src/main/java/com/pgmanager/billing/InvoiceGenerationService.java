package com.pgmanager.billing;

import com.pgmanager.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Shared write-path for a tenant's <em>recurring</em> monthly invoice — the base rent
 * (split into MONTHLY_RENT + optional AC_CHARGES) with no security deposit.
 *
 * <p>Two callers share the {@link #createRecurringInvoice} primitive so numbering, due-date
 * and line-item logic live in exactly one place:
 * <ul>
 *   <li>{@link BillingController} — the manual {@code POST /generate-invoices} fallback, via
 *       {@link #generateDueOn} (only the occupants whose billing anniversary falls on the
 *       given day — never the whole month).</li>
 *   <li>{@link InvoiceAutoGenerationScheduler} — the daily 1 AM automation, which invoices each
 *       tenant a configurable number of days before their billing anniversary.</li>
 * </ul>
 *
 * <p>The move-in / temp-stay / backfill invoices (which carry the one-time deposit) remain in
 * {@link MoveInBillingService}; this service handles only the deposit-free recurring case.
 */
@Service
@RequiredArgsConstructor
public class InvoiceGenerationService {
    private final JdbcTemplate jdbc;
    private final NotificationService notificationService;

    public record GenerationResult(int generated, int skipped, int notDue, LocalDate date) {}

    /**
     * Generates recurring invoices for the active occupant billing accounts in the org whose
     * billing anniversary falls on {@code date} (optionally scoped to a property) — i.e. only
     * the invoices that come due that day, not the whole month. The anniversary is the
     * occupancy {@code from_date} day-of-month, clamped to the month length so a 31st tenant
     * falls due on the last day of a short month (same rule the scheduler applies).
     *
     * <p>Idempotent: an account already invoiced for that month counts as {@code skipped}.
     * Accounts due on another day count as {@code notDue} and are left untouched.
     * This is the manual/fallback path behind {@code POST /generate-invoices}.
     */
    @Transactional
    public GenerationResult generateDueOn(Long org, LocalDate date, Long propertyId) {
        List<Object> args = new ArrayList<>();
        args.add(org);
        String propFilter = "";
        if (propertyId != null) {
            propFilter = " AND ba.party_id IN (SELECT fp.party_id FROM facility_party fp " +
                    "WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')";
            args.add(org);
            args.add(propertyId);
        }
        List<Map<String, Object>> accounts = jdbc.queryForList(
                "SELECT ba.billing_account_id,ba.party_id,fp.monthly_rent,fp.ac_charges,fp.from_date " +
                "FROM billing_account ba JOIN facility_party fp ON fp.party_id=ba.party_id " +
                "  AND fp.organization_id=ba.organization_id AND fp.role_type_id='OCCUPANT' AND fp.thru_date IS NULL " +
                "WHERE ba.organization_id=?" + propFilter + " AND ba.status='ACTIVE'", args.toArray());

        YearMonth month = YearMonth.from(date);
        int generated = 0;
        int skipped = 0;
        int notDue = 0;
        for (Map<String, Object> account : accounts) {
            int anniversaryDay = dayOfMonth(account.get("from_date"));
            int dueDay = Math.min(Math.max(anniversaryDay, 1), date.lengthOfMonth());
            if (dueDay != date.getDayOfMonth()) {
                notDue++;
                continue;
            }
            Long baId = ((Number) account.get("billing_account_id")).longValue();
            Long partyId = ((Number) account.get("party_id")).longValue();
            BigDecimal rent = decimal(account.get("monthly_rent"));
            BigDecimal ac = decimal(account.get("ac_charges"));
            if (createRecurringInvoice(org, baId, partyId, rent, ac, anniversaryDay, month) != null) generated++;
            else skipped++;
        }
        return new GenerationResult(generated, skipped, notDue, date);
    }

    /**
     * Creates the recurring invoice for one billing account and {@code month}, returning its id
     * (or {@code null} if one already exists for that account+month — the idempotency guard).
     *
     * <p>Total = {@code rent} (AC is only a breakdown of it, never added on top; the security
     * deposit is deliberately never part of a recurring invoice). The due date falls on the
     * tenant's billing anniversary day, clamped to the month length.
     *
     * <p>{@code @Transactional} so the invoice INSERT and its line-item INSERTs either all land
     * or none do — a half-written invoice would bill the wrong total. (It no longer has to be
     * transactional merely to keep a connection: the id now comes back from {@code RETURNING} on
     * the insert itself rather than a separate {@code LAST_INSERT_ID()} read.) Within
     * {@link #generateDueOn} the self-invocation simply joins that method's transaction, keeping
     * the manual batch atomic as before.
     */
    @Transactional
    public Long createRecurringInvoice(Long org, Long baId, Long partyId, BigDecimal monthlyRent,
                                       BigDecimal acCharges, int anniversaryDay, YearMonth month) {
        LocalDate invoiceMonth = month.atDay(1);
        Long exists = jdbc.queryForObject(
                "SELECT COUNT(*) FROM invoice WHERE billing_account_id=? AND invoice_month=?",
                Long.class, baId, invoiceMonth);
        if (exists != null && exists > 0) return null;

        BigDecimal rent = monthlyRent != null ? monthlyRent : BigDecimal.ZERO;
        // ac_charges is a breakdown of monthly_rent (already included in it) — it only splits
        // the invoice items, never changes the total.
        BigDecimal ac = acCharges != null ? acCharges : BigDecimal.ZERO;
        if (ac.compareTo(BigDecimal.ZERO) < 0 || ac.compareTo(rent) > 0) ac = BigDecimal.ZERO;
        BigDecimal baseRent = rent.subtract(ac);

        int day = Math.min(Math.max(anniversaryDay, 1), invoiceMonth.lengthOfMonth());
        LocalDate dueDate = invoiceMonth.withDayOfMonth(day);
        String invNum = "INV-" + org + "-" + baId + "-" + invoiceMonth.toString().substring(0, 7).replace("-", "");
        LocalDateTime now = LocalDateTime.now();
        Long invoiceId = jdbc.queryForObject(
                "INSERT INTO invoice(organization_id,billing_account_id,invoice_number,invoice_month,issue_date,due_date," +
                        "total_amount,paid_amount,status,created_at,updated_at,version) VALUES(?,?,?,?,?,?,?,0,'PENDING',?,?,0) " +
                        "RETURNING invoice_id",
                Long.class, org, baId, invNum, invoiceMonth, invoiceMonth, dueDate, rent, now, now);
        jdbc.update("INSERT INTO invoice_item(invoice_id,item_type_id,description,amount,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                invoiceId, "MONTHLY_RENT", "Monthly Rent", baseRent, now, now);
        if (ac.compareTo(BigDecimal.ZERO) > 0) {
            jdbc.update("INSERT INTO invoice_item(invoice_id,item_type_id,description,amount,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                    invoiceId, "AC_CHARGES", "AC Charges", ac, now, now);
        }
        notificationService.notifyTenantInvoice(org, partyId, invoiceId, invNum, rent, dueDate, invoiceMonth);
        return invoiceId;
    }

    private int dayOfMonth(Object fromDate) {
        if (fromDate instanceof java.sql.Date d) return d.toLocalDate().getDayOfMonth();
        if (fromDate instanceof LocalDate d) return d.getDayOfMonth();
        return 1;
    }

    private BigDecimal decimal(Object value) {
        if (value == null) return BigDecimal.ZERO;
        return value instanceof BigDecimal d ? d : new BigDecimal(value.toString());
    }
}
