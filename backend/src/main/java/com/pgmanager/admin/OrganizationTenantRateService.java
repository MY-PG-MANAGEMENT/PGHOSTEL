package com.pgmanager.admin;

import com.pgmanager.common.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * What the platform charges each organization per active tenant per month.
 *
 * <p>Two levels: a global default in {@code system_setting}
 * ({@code platform.price_per_active_tenant}) and per-org overrides in
 * {@code organization_tenant_rate} (V31). A missing override means "use the default", so a new
 * organization is priced correctly with no row written — the same missing-row-means-defaults
 * pattern as {@code BillingConfigService}.
 *
 * <p>JdbcTemplate rather than JPA, consistent with the rest of the admin package.
 */
@Service
@RequiredArgsConstructor
public class OrganizationTenantRateService {

    static final String DEFAULT_RATE_KEY = "platform.price_per_active_tenant";

    /** Used only if the setting row is missing or unparseable, so a report never prices at zero. */
    static final BigDecimal FALLBACK_RATE = new BigDecimal("15.00");

    /** Guards against a fat-fingered rate that would produce an absurd invoice. */
    private static final BigDecimal MAX_RATE = new BigDecimal("100000");

    private final JdbcTemplate jdbc;

    /**
     * The platform-wide default. Falls back to {@link #FALLBACK_RATE} rather than throwing: a
     * deleted or corrupted setting row must not take the whole report down.
     */
    public BigDecimal defaultRate() {
        List<String> values = jdbc.queryForList(
                "SELECT setting_value FROM system_setting WHERE setting_key=?", String.class, DEFAULT_RATE_KEY);
        if (values.isEmpty() || values.get(0) == null || values.get(0).isBlank()) return FALLBACK_RATE;
        try {
            return new BigDecimal(values.get(0).trim()).setScale(2, RoundingMode.HALF_UP);
        } catch (NumberFormatException ex) {
            return FALLBACK_RATE;
        }
    }

    /** Per-org overrides, keyed by organization id. Orgs on the default are absent. */
    public Map<Long, BigDecimal> overrides() {
        Map<Long, BigDecimal> rates = new HashMap<>();
        jdbc.query("SELECT organization_id,price_per_tenant FROM organization_tenant_rate",
                rs -> {
                    rates.put(rs.getLong("organization_id"), rs.getBigDecimal("price_per_tenant"));
                });
        return rates;
    }

    /** The effective rate for one org: its override, else the platform default. */
    public BigDecimal rateFor(Long organizationId) {
        return overrides().getOrDefault(organizationId, defaultRate());
    }

    /**
     * Sets or clears one org's override. A null price clears it, putting the org back on the
     * platform default — that is the only way back, since there is no "same as default" value
     * that would keep tracking a later change to the default.
     */
    public void setOverride(Long organizationId, BigDecimal price, Long userLoginId) {
        if (price == null) {
            jdbc.update("DELETE FROM organization_tenant_rate WHERE organization_id=?", organizationId);
            return;
        }
        validate(price);
        LocalDateTime now = LocalDateTime.now();
        jdbc.update("INSERT INTO organization_tenant_rate" +
                        "(organization_id,price_per_tenant,updated_by_user_login_id,created_at,updated_at) " +
                        "VALUES(?,?,?,?,?) " +
                        "ON CONFLICT (organization_id) DO UPDATE SET price_per_tenant=EXCLUDED.price_per_tenant," +
                        "updated_by_user_login_id=EXCLUDED.updated_by_user_login_id,updated_at=EXCLUDED.updated_at",
                organizationId, price.setScale(2, RoundingMode.HALF_UP), userLoginId, now, now);
    }

    /** Updates the platform-wide default that every non-overridden org uses. */
    public void setDefaultRate(BigDecimal price, Long userLoginId) {
        validate(price);
        jdbc.update("INSERT INTO system_setting(setting_key,setting_value,encrypted,updated_by_user_login_id,updated_at) " +
                        "VALUES(?,?,FALSE,?,?) " +
                        "ON CONFLICT (setting_key) DO UPDATE SET setting_value=EXCLUDED.setting_value," +
                        "updated_by_user_login_id=EXCLUDED.updated_by_user_login_id,updated_at=EXCLUDED.updated_at",
                DEFAULT_RATE_KEY, price.setScale(2, RoundingMode.HALF_UP).toPlainString(),
                userLoginId, LocalDateTime.now());
    }

    private void validate(BigDecimal price) {
        if (price.signum() < 0) throw new BadRequestException("Price cannot be negative");
        if (price.compareTo(MAX_RATE) > 0) throw new BadRequestException("Price cannot exceed " + MAX_RATE);
    }
}
