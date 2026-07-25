package com.pgmanager.tenant;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.occupancy.OccupancyRole;
import com.pgmanager.security.RoleType;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Owns the tenant-login lifecycle: provisioning on tenant create/upload, disabling on
 * checkout, and bulk generation when an existing org enables the feature later.
 *
 * <p>Username scheme is {@code {mobileNumber}@{organizationId}} — this satisfies the
 * global {@code user_login.username} unique constraint while letting the same mobile
 * number own independent logins in different organizations (full data isolation).
 *
 * <p>Lookups are keyed by <b>(organizationId, mobileNumber)</b> (via the person join),
 * <em>not</em> by partyId, because a tenant who rejoins gets a fresh party/person row —
 * we must find and reactivate the prior login rather than create a duplicate.
 */
@Service
@RequiredArgsConstructor
public class TenantLoginService {

    /** Temporary password for every auto-provisioned / reactivated tenant login. */
    public static final String TEMP_PASSWORD = "abc@123";
    public static final String REASON_CHECKED_OUT = "CHECKED_OUT";
    public static final String REASON_ARCHIVED = "ARCHIVED";

    private static final Logger log = LoggerFactory.getLogger(TenantLoginService.class);

    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwordEncoder;
    private final TenantLoginPolicy policy;
    private final AuditService auditService;

    /**
     * Provisions a tenant login when the feature is enabled. Implements the login-generation
     * logic: reuse an active login (re-pointed to the newest party), reactivate an inactive
     * one (rejoin), or create a new one. No-op when the feature is disabled.
     */
    public void provisionForTenant(Long organizationId, Long partyId, String mobile) {
        if (organizationId == null || partyId == null || mobile == null || mobile.isBlank()) return;
        // Login provisioning is best-effort: it must NEVER roll back or block tenant creation.
        // The ENTIRE body (incl. the feature-flag lookup) is guarded, and we catch before the
        // caller's @Transactional boundary so a failure here cannot mark the surrounding
        // transaction rollback-only.
        try {
            if (!policy.enabled(organizationId)) return;
            doProvision(organizationId, partyId, mobile);
        } catch (Exception e) {
            log.warn("Tenant login provisioning failed for org={} party={} (tenant still created): {}",
                    organizationId, partyId, e.getMessage(), e);
        }
    }

    private void doProvision(Long organizationId, Long partyId, String mobile) {
        LocalDateTime now = LocalDateTime.now();
        List<Map<String, Object>> candidates = jdbc.queryForList(
                "SELECT ul.user_login_id, ul.status FROM user_login ul " +
                "JOIN person pr ON pr.party_id = ul.party_id " +
                "WHERE ul.organization_id = ? AND ul.role_type_id = ? AND pr.mobile_number = ? " +
                "ORDER BY ul.user_login_id DESC",
                organizationId, RoleType.TENANT, mobile);

        // 1) An active login already exists in this org → reuse it (never duplicate an active login).
        for (Map<String, Object> c : candidates) {
            if ("ACTIVE".equals(c.get("status"))) {
                Long id = asLong(c.get("user_login_id"));
                jdbc.update("UPDATE user_login SET party_id=?, updated_at=? WHERE user_login_id=?",
                        partyId, now, id);
                return;
            }
        }

        // 2) Only inactive login(s) exist (rejoin same org) → reactivate the most recent.
        if (!candidates.isEmpty()) {
            Long id = asLong(candidates.get(0).get("user_login_id"));
            jdbc.update("UPDATE user_login SET status='ACTIVE', disabled_reason=NULL, party_id=?, " +
                    "password_hash=?, must_change_password=1, updated_at=? WHERE user_login_id=?",
                    partyId, passwordEncoder.encode(TEMP_PASSWORD), now, id);
            auditService.log(organizationId, null, "TENANT_LOGIN_REACTIVATED", "USER_LOGIN", id,
                    "Tenant login reactivated on rejoin");
            return;
        }

        // 3) No login for this org+mobile → create a new ACTIVE login with the temp password.
        String username = mobile + "@" + organizationId;
        jdbc.update("INSERT INTO user_login(party_id,username,password_hash,role_type_id,organization_id," +
                "status,must_change_password,created_at,updated_at) VALUES(?,?,?,?,?, 'ACTIVE', 1, ?, ?)",
                partyId, username, passwordEncoder.encode(TEMP_PASSWORD), RoleType.TENANT, organizationId, now, now);
        Long id = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        auditService.log(organizationId, null, "TENANT_LOGIN_CREATED", "USER_LOGIN", id, "Tenant login created");
    }

    /**
     * Disables all active tenant logins for a party on checkout: status → INACTIVE with reason
     * CHECKED_OUT, and revokes every refresh token so active sessions die on next refresh.
     * The login row is never deleted (so a rejoin can reactivate it).
     */
    public void disableForCheckout(Long organizationId, Long partyId) {
        disable(organizationId, partyId, REASON_CHECKED_OUT, "TENANT_LOGIN_DISABLED",
                "Tenant login disabled on checkout");
    }

    /**
     * Disables active tenant logins when the tenant is archived ("deleted" in the app).
     * Checkout normally already did this; this covers a tenant archived without ever
     * holding a bed. The login row survives so a rejoin can reactivate it.
     */
    public void disableForArchive(Long organizationId, Long partyId) {
        disable(organizationId, partyId, REASON_ARCHIVED, "TENANT_LOGIN_DISABLED",
                "Tenant login disabled on archive");
    }

    private void disable(Long organizationId, Long partyId, String reason, String auditEvent, String auditDetail) {
        if (organizationId == null || partyId == null) return;
        // Best-effort: a login-disable failure must not block checkout / archive (caught before
        // the caller's @Transactional boundary so the surrounding tx is never marked rollback-only).
        try {
            List<Long> ids = jdbc.queryForList(
                    "SELECT user_login_id FROM user_login WHERE organization_id=? AND party_id=? " +
                    "AND role_type_id=? AND status='ACTIVE'",
                    Long.class, organizationId, partyId, RoleType.TENANT);
            if (ids.isEmpty()) return;
            LocalDateTime now = LocalDateTime.now();
            for (Long id : ids) {
                jdbc.update("UPDATE user_login SET status='INACTIVE', disabled_reason=?, updated_at=? WHERE user_login_id=?",
                        reason, now, id);
                jdbc.update("UPDATE refresh_token SET revoked=TRUE, updated_at=? WHERE user_login_id=? AND revoked=FALSE",
                        now, id);
            }
            auditService.log(organizationId, null, auditEvent, "PARTY", partyId, auditDetail);
        } catch (Exception e) {
            log.warn("Tenant login disable ({}) failed for org={} party={} (caller still proceeds): {}",
                    reason, organizationId, partyId, e.getMessage(), e);
        }
    }

    /**
     * Bulk "Generate Tenant Login Accounts" for an org that enabled the feature after tenants
     * already existed. Skips inactive tenants, checked-out tenants, and tenants who already have
     * an active login; creates/reactivates a login for everyone else. Returns a progress summary.
     */
    @Transactional
    public Map<String, Object> generateForOrganization(Long organizationId) {
        if (!policy.enabled(organizationId)) {
            throw new BadRequestException("Tenant Login is not enabled for this organization");
        }
        // Every org-level TENANT membership (active AND ended), so we can report skip reasons.
        List<Map<String, Object>> tenants = jdbc.queryForList(
                "SELECT fp.party_id, fp.thru_date, pr.mobile_number FROM facility_party fp " +
                "JOIN person pr ON pr.party_id = fp.party_id " +
                "WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id=?",
                organizationId, organizationId, OccupancyRole.TENANT);

        // Pre-load the three membership sets once for the whole org (was 3 COUNT(*) queries
        // per tenant). Set lookups then decide skip reasons in memory.
        Set<Long> withOccupancyHistory = new HashSet<>(jdbc.queryForList(
                "SELECT DISTINCT party_id FROM facility_party WHERE organization_id=? AND role_type_id=?",
                Long.class, organizationId, OccupancyRole.OCCUPANT));
        Set<Long> withActiveOccupancy = new HashSet<>(jdbc.queryForList(
                "SELECT DISTINCT party_id FROM facility_party WHERE organization_id=? AND role_type_id=? AND thru_date IS NULL",
                Long.class, organizationId, OccupancyRole.OCCUPANT));
        Set<Long> withActiveLogin = new HashSet<>(jdbc.queryForList(
                "SELECT DISTINCT party_id FROM user_login WHERE organization_id=? AND role_type_id=? AND status='ACTIVE'",
                Long.class, organizationId, RoleType.TENANT));
        // Archived ("deleted") tenants are hidden from every tenant list — never give them a login.
        Set<Long> archived = new HashSet<>(jdbc.queryForList(
                "SELECT party_id FROM tenant_archive WHERE organization_id=?", Long.class, organizationId));

        int total = 0, created = 0, skippedExisting = 0, skippedInactive = 0, skippedCheckedOut = 0, skippedArchived = 0;
        for (Map<String, Object> row : tenants) {
            total++;
            Long partyId = asLong(row.get("party_id"));
            String mobile = (String) row.get("mobile_number");

            if (archived.contains(partyId)) {
                skippedArchived++;
                continue;
            }
            if (row.get("thru_date") != null || mobile == null || mobile.isBlank()) {
                skippedInactive++;
                continue;
            }
            // Checked out = has occupancy history but no currently-active bed assignment.
            if (withOccupancyHistory.contains(partyId) && !withActiveOccupancy.contains(partyId)) {
                skippedCheckedOut++;
                continue;
            }
            if (withActiveLogin.contains(partyId)) {
                skippedExisting++;
                continue;
            }
            try {
                provisionForTenant(organizationId, partyId, mobile);
                created++;
            } catch (Exception e) {
                log.warn("Tenant login generation failed for party {}: {}", partyId, e.getMessage());
                skippedExisting++;
            }
        }

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("total", total);
        summary.put("created", created);
        summary.put("skippedExisting", skippedExisting);
        summary.put("skippedInactive", skippedInactive);
        summary.put("skippedCheckedOut", skippedCheckedOut);
        summary.put("skippedArchived", skippedArchived);
        auditService.log(organizationId, null, "TENANT_LOGINS_GENERATED", "ORGANIZATION", organizationId,
                "Generated " + created + " tenant logins");
        return summary;
    }

    private static Long asLong(Object o) {
        return o == null ? null : ((Number) o).longValue();
    }
}
