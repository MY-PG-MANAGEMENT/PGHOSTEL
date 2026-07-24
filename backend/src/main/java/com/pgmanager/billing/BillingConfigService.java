package com.pgmanager.billing;

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
 * <p>JdbcTemplate-based, matching the billing package convention.
 */
@Service
@RequiredArgsConstructor
public class BillingConfigService {
    private final JdbcTemplate jdbc;

    /** Lead days is clamped to this inclusive range (0 = generate on the due date itself). */
    public static final int MIN_LEAD_DAYS = 0;
    public static final int MAX_LEAD_DAYS = 28;

    /** Defaults applied when an org has no config row. */
    public static final BillingConfig DEFAULT = new BillingConfig(1, true);

    public record BillingConfig(int invoiceLeadDays, boolean autoGenerateEnabled) {}

    /** Returns the org's config, or {@link #DEFAULT} when no row exists. */
    public BillingConfig get(Long organizationId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT invoice_lead_days, auto_generate_enabled FROM organization_billing_config WHERE organization_id=?",
                organizationId);
        if (rows.isEmpty()) return DEFAULT;
        Map<String, Object> row = rows.getFirst();
        int leadDays = row.get("invoice_lead_days") != null
                ? ((Number) row.get("invoice_lead_days")).intValue() : DEFAULT.invoiceLeadDays();
        boolean enabled = row.get("auto_generate_enabled") == null
                || ((Number) row.get("auto_generate_enabled")).intValue() != 0;
        return new BillingConfig(clampLeadDays(leadDays), enabled);
    }

    /** Inserts or updates the org's config; returns the persisted (clamped) values. */
    public BillingConfig upsert(Long organizationId, int invoiceLeadDays, boolean autoGenerateEnabled) {
        int leadDays = clampLeadDays(invoiceLeadDays);
        LocalDateTime now = LocalDateTime.now();
        jdbc.update(
                "INSERT INTO organization_billing_config" +
                "(organization_id,invoice_lead_days,auto_generate_enabled,created_at,updated_at) VALUES(?,?,?,?,?) " +
                "ON DUPLICATE KEY UPDATE invoice_lead_days=VALUES(invoice_lead_days)," +
                "auto_generate_enabled=VALUES(auto_generate_enabled),updated_at=VALUES(updated_at)",
                organizationId, leadDays, autoGenerateEnabled ? 1 : 0, now, now);
        return new BillingConfig(leadDays, autoGenerateEnabled);
    }

    private int clampLeadDays(int value) {
        return Math.max(MIN_LEAD_DAYS, Math.min(MAX_LEAD_DAYS, value));
    }
}
