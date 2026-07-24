package com.pgmanager.billing;

import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;

/**
 * Automates monthly invoice creation. Runs daily at 1:00 AM and raises each active tenant's
 * recurring invoice a configurable number of days BEFORE their billing anniversary (their
 * move-in day-of-month), so the invoice is ready ahead of the due date instead of waiting on a
 * manual batch run.
 *
 * <p>Per-org behaviour comes from {@code organization_billing_config} (V26): {@code invoice_lead_days}
 * (default 1) and {@code auto_generate_enabled} (default on). A tenant is invoiced on the day when
 * {@code today + leadDays} equals this month's due date — computed with month-length clamping so a
 * 31st anniversary still fires in February, and lead days that cross a month boundary land in the
 * correct billing month. Idempotent: {@link InvoiceGenerationService#createRecurringInvoice} skips
 * any account already invoiced for the month, so a re-run (or overlap with the manual endpoint) is safe.
 *
 * <p>Runs after {@code BedTransferScheduler} (00:05) so a sharing-change transfer effective today is
 * applied before this evaluates the tenant's rent.
 */
@Component
@RequiredArgsConstructor
public class InvoiceAutoGenerationScheduler {
    private static final Logger log = LoggerFactory.getLogger(InvoiceAutoGenerationScheduler.class);

    private final JdbcTemplate jdbc;
    private final InvoiceGenerationService invoiceGenerationService;

    @Scheduled(cron = "0 15 1 * * *") // 1:00 AM every day
    public void generateDueInvoices() {
        LocalDate today = LocalDate.now();
        // One global sweep (RentReminderScheduler style): active occupant billing accounts in
        // ACTIVE orgs, joined to per-org config (defaults via COALESCE when no row exists).
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT ba.billing_account_id,ba.party_id,ba.organization_id," +
                "       fp.monthly_rent,fp.ac_charges,fp.from_date," +
                "       COALESCE(cfg.invoice_lead_days,1) AS lead_days," +
                "       COALESCE(cfg.auto_generate_enabled,1) AS auto_enabled " +
                "FROM billing_account ba " +
                "JOIN facility org ON org.facility_id=ba.organization_id " +
                "  AND org.facility_type_id='ORGANIZATION' AND org.status='ACTIVE' " +
                "JOIN facility_party fp ON fp.party_id=ba.party_id AND fp.organization_id=ba.organization_id " +
                "  AND fp.role_type_id='OCCUPANT' AND fp.thru_date IS NULL " +
                "LEFT JOIN organization_billing_config cfg ON cfg.organization_id=ba.organization_id " +
                "WHERE ba.status='ACTIVE'");

        int generated = 0;
        for (Map<String, Object> row : rows) {
            try {
                boolean autoEnabled = row.get("auto_enabled") == null
                        || ((Number) row.get("auto_enabled")).intValue() != 0;
                if (!autoEnabled) continue;
                if (row.get("from_date") == null) continue;

                int leadDays = row.get("lead_days") != null ? ((Number) row.get("lead_days")).intValue() : 1;
                int anniversaryDay = ((java.sql.Date) row.get("from_date")).toLocalDate().getDayOfMonth();

                // The prospective due date if we generate today; fire only when it lands exactly on
                // this account's anniversary (clamped to the target month's length).
                LocalDate targetDue = today.plusDays(leadDays);
                int dueDay = Math.min(anniversaryDay, targetDue.lengthOfMonth());
                if (targetDue.getDayOfMonth() != dueDay) continue;

                Long org = ((Number) row.get("organization_id")).longValue();
                Long baId = ((Number) row.get("billing_account_id")).longValue();
                Long partyId = ((Number) row.get("party_id")).longValue();
                BigDecimal rent = decimal(row.get("monthly_rent"));
                BigDecimal ac = decimal(row.get("ac_charges"));

                Long invoiceId = invoiceGenerationService.createRecurringInvoice(
                        org, baId, partyId, rent, ac, anniversaryDay, YearMonth.from(targetDue));
                if (invoiceId != null) generated++;
            } catch (Exception e) {
                log.warn("Auto invoice generation failed for billing_account_id={}: {}",
                        row.get("billing_account_id"), e.getMessage());
            }
        }
        if (generated > 0) log.info("Auto-generated {} invoice(s)", generated);
    }

    private BigDecimal decimal(Object value) {
        if (value == null) return BigDecimal.ZERO;
        return value instanceof BigDecimal d ? d : new BigDecimal(value.toString());
    }
}
