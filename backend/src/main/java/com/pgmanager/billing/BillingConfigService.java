package com.pgmanager.billing;

import com.pgmanager.common.util.JdbcValues;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * Reads and writes the per-organization invoice-automation config
 * ({@code organization_billing_config}, V26).
 *
 * <p>The config controls the daily {@link InvoiceAutoGenerationScheduler}: how many
 * days before a tenant's billing anniversary the monthly invoice is raised
 * ({@code invoiceLeadDays}) and whether automation runs at all for the org
 * ({@code autoGenerateEnabled}). A missing row resolves to {@link #DEFAULT} so every
 * org is automated out of the box; the manual generate endpoint is unaffected either way.
 *
 * <p>{@code checkoutGraceDays} (V27) is the other side of that lead time: how long after
 * the due date the freshly raised invoice still counts as unconsumed, so a tenant checking
 * out in that window has it dropped rather than billed — see {@link CheckoutInvoiceService}.
 *
 * <p>JdbcTemplate-based, matching the billing package convention.
 */
@Service
@RequiredArgsConstructor
public class BillingConfigService {
    private final JdbcTemplate jdbc;

    /** Lead days is clamped to this inclusive range (0 = generate on the due date itself). */
    public static final int MIN_LEAD_DAYS = 0;
    public static final int MAX_LEAD_DAYS = 28;

    /** Checkout grace days is clamped to this inclusive range (0 = only up to the due date). */
    public static final int MIN_GRACE_DAYS = 0;
    public static final int MAX_GRACE_DAYS = 28;

    /** Defaults applied when an org has no config row. */
    public static final BillingConfig DEFAULT = new BillingConfig(1, 2, true);

    public record BillingConfig(int invoiceLeadDays, int checkoutGraceDays, boolean autoGenerateEnabled) {}

    /** Returns the org's config, or {@link #DEFAULT} when no row exists. */
    public BillingConfig get(Long organizationId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT invoice_lead_days, checkout_grace_days, auto_generate_enabled " +
                "FROM organization_billing_config WHERE organization_id=?",
                organizationId);
        if (rows.isEmpty()) return DEFAULT;
        Map<String, Object> row = rows.getFirst();
        int leadDays = JdbcValues.toInt(row.get("invoice_lead_days"), DEFAULT.invoiceLeadDays());
        int graceDays = JdbcValues.toInt(row.get("checkout_grace_days"), DEFAULT.checkoutGraceDays());
        // auto_generate_enabled is TINYINT(1) — MySQL hands it back as a Boolean, so it must
        // not be cast to Number (that threw once an org actually had a config row).
        boolean enabled = JdbcValues.toBoolean(row.get("auto_generate_enabled"), true);
        return new BillingConfig(clampLeadDays(leadDays), clampGraceDays(graceDays), enabled);
    }

    /** Inserts or updates the org's config; returns the persisted (clamped) values. */
    public BillingConfig upsert(Long organizationId, int invoiceLeadDays, int checkoutGraceDays,
                                boolean autoGenerateEnabled) {
        int leadDays = clampLeadDays(invoiceLeadDays);
        int graceDays = clampGraceDays(checkoutGraceDays);
        LocalDateTime now = LocalDateTime.now();
        jdbc.update(
                "INSERT INTO organization_billing_config" +
                "(organization_id,invoice_lead_days,checkout_grace_days,auto_generate_enabled,created_at,updated_at) " +
                "VALUES(?,?,?,?,?,?) " +
                "ON DUPLICATE KEY UPDATE invoice_lead_days=VALUES(invoice_lead_days)," +
                "checkout_grace_days=VALUES(checkout_grace_days)," +
                "auto_generate_enabled=VALUES(auto_generate_enabled),updated_at=VALUES(updated_at)",
                organizationId, leadDays, graceDays, autoGenerateEnabled ? 1 : 0, now, now);
        return new BillingConfig(leadDays, graceDays, autoGenerateEnabled);
    }

    private int clampLeadDays(int value) {
        return Math.max(MIN_LEAD_DAYS, Math.min(MAX_LEAD_DAYS, value));
    }

    private int clampGraceDays(int value) {
        return Math.max(MIN_GRACE_DAYS, Math.min(MAX_GRACE_DAYS, value));
    }
}
