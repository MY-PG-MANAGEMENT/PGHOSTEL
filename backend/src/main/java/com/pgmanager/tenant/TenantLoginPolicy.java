package com.pgmanager.tenant;

import com.pgmanager.common.cache.CacheConfig;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

/**
 * Single source of truth for whether the opt-in <b>Tenant Login</b> feature is
 * enabled for an organization. Backed by an {@code organization_feature} row keyed
 * by {@code feature_master.feature_code = 'TENANT_LOGIN'} (seeded in V22) — the same
 * opt-in pattern used for messaging channels in
 * {@link com.pgmanager.notification.OrganizationChannelService}.
 *
 * <p>The toggle is controlled <b>only</b> by the Super Admin. A missing row (or
 * {@code enabled = FALSE}) means tenant login is disabled and no login accounts
 * are ever provisioned.
 */
@Service
@RequiredArgsConstructor
public class TenantLoginPolicy {

    public static final String FEATURE_CODE = "TENANT_LOGIN";

    private final JdbcTemplate jdbc;

    /**
     * True only when an enabled {@code organization_feature} row exists for TENANT_LOGIN.
     * Cached per {@code org:TENANT_LOGIN} (shares {@link CacheConfig#ORG_FEATURES} with the
     * messaging channels — same table, distinct code) and evicted by {@link #setEnabled}.
     */
    @Cacheable(cacheNames = CacheConfig.ORG_FEATURES,
            key = "#organizationId + ':' + T(com.pgmanager.tenant.TenantLoginPolicy).FEATURE_CODE",
            condition = "#organizationId != null")
    public boolean enabled(Long organizationId) {
        if (organizationId == null) return false;
        // NOTE: `of` is a RESERVED keyword in MySQL 8.0 — using it as a table alias is a syntax
        // error, so alias organization_feature as `orgf`.
        Boolean value = jdbc.query(
                "SELECT orgf.enabled FROM organization_feature orgf " +
                "JOIN feature_master fm ON fm.feature_id = orgf.feature_id " +
                "WHERE orgf.organization_id = ? AND fm.feature_code = ?",
                rs -> rs.next() ? rs.getBoolean(1) : Boolean.FALSE,
                organizationId, FEATURE_CODE);
        return Boolean.TRUE.equals(value);
    }

    /**
     * Enable/disable Tenant Login for an org (upsert). Super-admin only at the controller layer.
     * Evicts the cached {@code org:TENANT_LOGIN} flag so the next {@link #enabled} read is fresh.
     */
    @CacheEvict(cacheNames = CacheConfig.ORG_FEATURES,
            key = "#organizationId + ':' + T(com.pgmanager.tenant.TenantLoginPolicy).FEATURE_CODE")
    public void setEnabled(Long organizationId, boolean enabled) {
        Long featureId = jdbc.queryForObject(
                "SELECT feature_id FROM feature_master WHERE feature_code = ?", Long.class, FEATURE_CODE);
        LocalDateTime now = LocalDateTime.now();
        jdbc.update(
                "INSERT INTO organization_feature(organization_id,feature_id,enabled,created_at,updated_at) " +
                "VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),updated_at=VALUES(updated_at)",
                organizationId, featureId, enabled, now, now);
    }
}
