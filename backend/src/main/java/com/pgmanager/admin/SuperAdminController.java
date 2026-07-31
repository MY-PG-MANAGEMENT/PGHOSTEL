package com.pgmanager.admin;

import com.pgmanager.audit.AuditService;
import com.pgmanager.auth.AuthService;
import com.pgmanager.auth.OrganizationStatusGuard;
import com.pgmanager.auth.dto.AuthDtos.RegisterOwnerRequest;
import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.notification.NotificationService;
import com.pgmanager.notification.OrganizationChannelService;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.security.RoleType;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
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
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/api/super-admin")
@RequiredArgsConstructor
public class SuperAdminController {
    private final JdbcTemplate jdbc;
    private final CurrentUser currentUser;
    private final NotificationService notificationService;
    private final AuthService authService;
    private final OrganizationChannelService channelService;
    private final PasswordEncoder passwordEncoder;
    private final AuditService auditService;
    private final com.pgmanager.tenant.TenantLoginPolicy tenantLoginPolicy;
    private final OrganizationTenantRateService tenantRateService;

    private static final Set<String> ALLOWED_ORG_STATUSES = Set.of("ACTIVE", "INACTIVE", "SUSPENDED");

    @GetMapping("/dashboard")
    ApiResponse<Map<String, Object>> dashboard() {
        return ApiResponse.ok(Map.of(
                "totalOrganizations", scalar("SELECT COUNT(*) FROM facility WHERE facility_type_id='ORGANIZATION'"),
                "activeOrganizations", scalar("SELECT COUNT(*) FROM facility WHERE facility_type_id='ORGANIZATION' AND status='ACTIVE'"),
                "totalProperties", scalar("SELECT COUNT(*) FROM facility WHERE facility_type_id='PROPERTY'"),
                "totalTenants", scalar("SELECT COUNT(DISTINCT party_id) FROM facility_party WHERE role_type_id='TENANT' AND thru_date IS NULL"),
                "monthlyRevenue", amount("SELECT COALESCE(SUM(p.amount),0) FROM payment p WHERE p.payment_date>=DATE_TRUNC('month',CURRENT_DATE)::date"),
                "recentActivity", jdbc.queryForList("SELECT action,entity_type,entity_id,created_at FROM audit_log ORDER BY created_at DESC LIMIT 10")
        ));
    }

    @GetMapping("/organizations")
    ApiResponse<List<Map<String, Object>>> organizations(@RequestParam(required = false) String status) {
        return ApiResponse.ok(status == null || status.isBlank()
                ? jdbc.queryForList("SELECT facility_id organization_id,facility_name,status,created_at FROM facility WHERE facility_type_id='ORGANIZATION' ORDER BY created_at DESC")
                : jdbc.queryForList("SELECT facility_id organization_id,facility_name,status,created_at FROM facility WHERE facility_type_id='ORGANIZATION' AND status=? ORDER BY created_at DESC", status));
    }

    @PostMapping("/organizations")
    ApiResponse<Map<String, Object>> createOrganization(@Valid @RequestBody RegisterOwnerRequest request) {
        AuthService.OwnerAccount account = authService.createOwnerAccount(request);
        return ApiResponse.ok("Organization created", Map.of(
                "organizationId", account.organizationId(),
                "organizationName", account.organizationName(),
                "ownerUserLoginId", account.userLoginId(),
                "ownerUsername", account.username()
        ));
    }

    @PatchMapping("/organizations/{organizationId}/status")
    ApiResponse<Void> organizationStatus(@PathVariable Long organizationId, @RequestBody Map<String, String> body) {
        String status = body.get("status");
        if (status == null || !ALLOWED_ORG_STATUSES.contains(status)) {
            throw new BadRequestException("status must be one of " + ALLOWED_ORG_STATUSES);
        }
        int count = jdbc.update("UPDATE facility SET status=?,updated_at=? WHERE facility_id=? AND facility_type_id='ORGANIZATION'",
                status, LocalDateTime.now(), organizationId);
        if (count == 0) throw new NotFoundException("Organization not found");
        if (!OrganizationStatusGuard.ACTIVE.equals(status)) {
            // Logging in is blocked by OrganizationStatusGuard, but anyone already signed in holds a
            // refresh token. Revoke them so those sessions die with their access token instead of
            // rolling on for the full refresh window.
            jdbc.update("UPDATE refresh_token SET revoked=TRUE,updated_at=? " +
                    "WHERE revoked=FALSE AND user_login_id IN (SELECT user_login_id FROM user_login WHERE organization_id=?)",
                    LocalDateTime.now(), organizationId);
        }
        auditService.log(organizationId, currentUser.userLoginId(), "ORGANIZATION_STATUS_CHANGED", "FACILITY", organizationId,
                "Super admin set organization status to " + status);
        return ApiResponse.ok(null);
    }

    @GetMapping("/properties")
    ApiResponse<List<Map<String, Object>>> properties() {
        return ApiResponse.ok(jdbc.queryForList("SELECT p.facility_id,p.facility_name,p.organization_id,o.facility_name organization_name,p.status " +
                "FROM facility p JOIN facility o ON o.facility_id=p.organization_id WHERE p.facility_type_id='PROPERTY' ORDER BY p.created_at DESC"));
    }

    @PostMapping("/users/{userLoginId}/reset-password")
    ApiResponse<Void> resetUserPassword(@PathVariable Long userLoginId, @Valid @RequestBody ResetPasswordRequest request) {
        Map<String, Object> user;
        try {
            user = jdbc.queryForMap("SELECT username,role_type_id,organization_id FROM user_login WHERE user_login_id=?", userLoginId);
        } catch (EmptyResultDataAccessException e) {
            throw new NotFoundException("User login not found");
        }
        if (RoleType.SUPER_ADMIN.equals(user.get("role_type_id"))) {
            throw new BadRequestException("Super admin passwords cannot be reset here");
        }
        jdbc.update("UPDATE user_login SET password_hash=?,updated_at=? WHERE user_login_id=?",
                passwordEncoder.encode(request.newPassword()), LocalDateTime.now(), userLoginId);
        // Invalidate any active sessions so the old password stops working immediately.
        jdbc.update("UPDATE refresh_token SET revoked=TRUE,updated_at=? WHERE user_login_id=? AND revoked=FALSE",
                LocalDateTime.now(), userLoginId);
        Object orgRaw = user.get("organization_id");
        Long orgId = orgRaw == null ? null : ((Number) orgRaw).longValue();
        auditService.log(orgId, currentUser.userLoginId(), "PASSWORD_RESET_BY_ADMIN", "USER_LOGIN", userLoginId,
                "Super admin reset password for " + user.get("username"));
        return ApiResponse.ok("Password reset", null);
    }

    @GetMapping("/roles")
    ApiResponse<List<Map<String, Object>>> roles() {
        return ApiResponse.ok(jdbc.queryForList("SELECT r.role_type_id,r.description,COUNT(rp.permission_id) permission_count " +
                "FROM role_type r LEFT JOIN role_permission rp ON rp.role_type_id=r.role_type_id AND rp.thru_date IS NULL " +
                "GROUP BY r.role_type_id,r.description ORDER BY r.role_type_id"));
    }

    @GetMapping("/roles/{roleTypeId}/permissions")
    ApiResponse<List<Map<String, Object>>> permissions(@PathVariable String roleTypeId) {
        return ApiResponse.ok(jdbc.queryForList("SELECT p.permission_id,p.module_code,p.description,(rp.permission_id IS NOT NULL) granted " +
                "FROM permission p LEFT JOIN role_permission rp ON rp.permission_id=p.permission_id AND rp.role_type_id=? AND rp.thru_date IS NULL " +
                "ORDER BY p.module_code,p.permission_id", roleTypeId));
    }

    /**
     * Active Tenants report — the platform's own monthly billing basis, one row per organization.
     *
     * <p>Returns data, not a file: the Flutter admin screen renders the PDF, so a layout change
     * needs no backend release (same split as the owner-side {@code ReportController}).
     *
     * <p><b>"Active in the month" means overlapping the month, not active today.</b> A tenant who
     * moved out on the 20th still consumed the service that month and is still billable, and a
     * report for a past month must not silently change as tenants leave. So the count is
     * {@code from_date <= month end AND (thru_date IS NULL OR thru_date >= month start)} over the
     * org-level TENANT membership row — which is also why archived tenants are excluded explicitly:
     * archiving deliberately leaves {@code thru_date} null (see the tenant archive notes), so
     * without that filter a deleted tenant would keep being charged for.
     *
     * <p>Property count is likewise as-of month end, so a historical report is not inflated by
     * properties added later.
     */
    @GetMapping("/reports/active-tenants")
    ApiResponse<Map<String, Object>> activeTenantsReport(@RequestParam(required = false) String month) {
        LocalDate monthStart = parseMonth(month);
        LocalDate monthEnd = monthStart.withDayOfMonth(monthStart.lengthOfMonth());

        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT o.facility_id organization_id, o.facility_name organization_name, o.status, " +
                "(SELECT COUNT(DISTINCT fp.party_id) FROM facility_party fp " +
                "   WHERE fp.organization_id = o.facility_id AND fp.facility_id = o.facility_id " +
                "     AND fp.role_type_id = 'TENANT' " +
                "     AND fp.from_date <= ? AND (fp.thru_date IS NULL OR fp.thru_date >= ?) " +
                "     AND NOT EXISTS (SELECT 1 FROM tenant_archive ta " +
                "                     WHERE ta.organization_id = o.facility_id AND ta.party_id = fp.party_id) " +
                ") active_tenants, " +
                "(SELECT COUNT(*) FROM facility p WHERE p.organization_id = o.facility_id " +
                "   AND p.facility_type_id = 'PROPERTY' AND p.created_at::date <= CAST(? AS date)) property_count " +
                "FROM facility o WHERE o.facility_type_id = 'ORGANIZATION' " +
                "ORDER BY o.facility_name",
                monthEnd, monthStart, monthEnd);

        BigDecimal defaultRate = tenantRateService.defaultRate();
        Map<Long, BigDecimal> overrides = tenantRateService.overrides();

        long totalTenants = 0;
        long totalProperties = 0;
        BigDecimal totalAmount = BigDecimal.ZERO;
        List<Map<String, Object>> items = new java.util.ArrayList<>(rows.size());

        for (Map<String, Object> row : rows) {
            Long orgId = ((Number) row.get("organization_id")).longValue();
            long activeTenants = ((Number) row.get("active_tenants")).longValue();
            long propertyCount = ((Number) row.get("property_count")).longValue();
            BigDecimal rate = overrides.getOrDefault(orgId, defaultRate);
            BigDecimal amount = rate.multiply(BigDecimal.valueOf(activeTenants));

            Map<String, Object> item = new LinkedHashMap<>();
            item.put("organizationId", orgId);
            item.put("organizationName", row.get("organization_name"));
            item.put("status", row.get("status"));
            item.put("activeTenants", activeTenants);
            item.put("propertyCount", propertyCount);
            item.put("pricePerTenant", rate);
            // Lets the report show which orgs are on a negotiated rate versus the platform default.
            item.put("customRate", overrides.containsKey(orgId));
            item.put("amount", amount);
            items.add(item);

            totalTenants += activeTenants;
            totalProperties += propertyCount;
            totalAmount = totalAmount.add(amount);
        }

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("organizationCount", items.size());
        // Orgs with no tenants that month still appear as rows (a zero line is information), but
        // this counts the ones that actually generated a charge.
        summary.put("billableOrganizations", items.stream().filter(i -> ((Number) i.get("activeTenants")).longValue() > 0).count());
        summary.put("totalActiveTenants", totalTenants);
        summary.put("totalProperties", totalProperties);
        summary.put("defaultPricePerTenant", defaultRate);
        summary.put("totalAmount", totalAmount);

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("month", monthStart.toString().substring(0, 7));
        payload.put("monthStart", monthStart.toString());
        payload.put("monthEnd", monthEnd.toString());
        payload.put("summary", summary);
        payload.put("items", items);
        return ApiResponse.ok(payload);
    }

    /** {@code yyyy-MM}, defaulting to the current month. Rejects a future month. */
    private LocalDate parseMonth(String month) {
        if (month == null || month.isBlank()) {
            return LocalDate.now().withDayOfMonth(1);
        }
        LocalDate parsed;
        try {
            parsed = LocalDate.parse(month.trim() + "-01");
        } catch (Exception ex) {
            throw new BadRequestException("month must be in yyyy-MM format");
        }
        if (parsed.isAfter(LocalDate.now().withDayOfMonth(1))) {
            throw new BadRequestException("month cannot be in the future");
        }
        return parsed;
    }

    /**
     * Per-tenant pricing for the Admin → System Settings editor: every organization with its
     * effective rate, plus the platform default that non-overridden orgs follow.
     */
    @GetMapping("/tenant-rates")
    ApiResponse<Map<String, Object>> tenantRates() {
        BigDecimal defaultRate = tenantRateService.defaultRate();
        Map<Long, BigDecimal> overrides = tenantRateService.overrides();
        List<Map<String, Object>> orgs = jdbc.queryForList(
                "SELECT facility_id organization_id,facility_name,status FROM facility " +
                "WHERE facility_type_id='ORGANIZATION' ORDER BY facility_name");
        List<Map<String, Object>> items = new java.util.ArrayList<>(orgs.size());
        for (Map<String, Object> org : orgs) {
            Long orgId = ((Number) org.get("organization_id")).longValue();
            Map<String, Object> item = new LinkedHashMap<>(org);
            item.put("pricePerTenant", overrides.getOrDefault(orgId, defaultRate));
            item.put("customRate", overrides.containsKey(orgId));
            items.add(item);
        }
        return ApiResponse.ok(Map.of("defaultPricePerTenant", defaultRate, "items", items));
    }

    /**
     * Sets one org's rate, or clears it back to the default when {@code pricePerTenant} is null.
     * {@code organizationId = 0} is the sentinel for "the platform default itself", so the editor
     * can change the default through the same endpoint instead of round-tripping the generic
     * system-settings screen (where it would be one untyped string among many).
     */
    @PutMapping("/tenant-rates/{organizationId}")
    ApiResponse<Map<String, Object>> updateTenantRate(@PathVariable Long organizationId,
                                                     @RequestBody TenantRateRequest request) {
        if (organizationId == 0L) {
            if (request.pricePerTenant() == null) throw new BadRequestException("Default price is required");
            tenantRateService.setDefaultRate(request.pricePerTenant(), currentUser.userLoginId());
            auditService.log(null, currentUser.userLoginId(), "PLATFORM_TENANT_RATE_CHANGED", "SYSTEM_SETTING", null,
                    "Default price per active tenant set to " + request.pricePerTenant());
            return ApiResponse.ok("Default price updated", Map.of("defaultPricePerTenant", tenantRateService.defaultRate()));
        }
        Integer exists = jdbc.queryForObject(
                "SELECT COUNT(*) FROM facility WHERE facility_id=? AND facility_type_id='ORGANIZATION'",
                Integer.class, organizationId);
        if (exists == null || exists == 0) throw new NotFoundException("Organization not found");

        tenantRateService.setOverride(organizationId, request.pricePerTenant(), currentUser.userLoginId());
        auditService.log(organizationId, currentUser.userLoginId(), "ORGANIZATION_TENANT_RATE_CHANGED",
                "FACILITY", organizationId,
                request.pricePerTenant() == null
                        ? "Per-tenant rate reset to the platform default"
                        : "Per-tenant rate set to " + request.pricePerTenant());
        return ApiResponse.ok("Price updated", Map.of("pricePerTenant", tenantRateService.rateFor(organizationId)));
    }

    @GetMapping("/organizations/{organizationId}")
    ApiResponse<Map<String, Object>> organizationDetail(@PathVariable Long organizationId) {
        Map<String, Object> org = jdbc.queryForMap(
                "SELECT facility_id organization_id, facility_name, status, created_at FROM facility " +
                "WHERE facility_id=? AND facility_type_id='ORGANIZATION'", organizationId);
        org.put("propertyCount",   scalar("SELECT COUNT(*) FROM facility WHERE organization_id=? AND facility_type_id='PROPERTY'", organizationId));
        org.put("tenantCount",     scalar("SELECT COUNT(DISTINCT party_id) FROM facility_party WHERE organization_id=? AND facility_id=? AND role_type_id='TENANT' AND thru_date IS NULL", organizationId, organizationId));
        org.put("occupiedBeds",    scalar("SELECT COUNT(*) FROM facility_party WHERE organization_id=? AND role_type_id='OCCUPANT' AND thru_date IS NULL", organizationId));
        org.put("totalBeds",       scalar("SELECT COUNT(*) FROM facility WHERE organization_id=? AND facility_type_id='BED'", organizationId));
        return ApiResponse.ok(org);
    }

    /**
     * The organization's staff logins — everyone but the tenants, owner first. Backs the
     * Organizations → Users tab, which is where passwords are reset from (there is no
     * cross-organization user list; a reset always starts from the org that owns the login).
     */
    @GetMapping("/organizations/{organizationId}/users")
    ApiResponse<List<Map<String, Object>>> organizationUsers(@PathVariable Long organizationId) {
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT u.user_login_id,u.username,u.role_type_id,u.status,u.last_login_at," +
                "p.full_name,p.mobile_number " +
                "FROM user_login u JOIN person p ON p.party_id=u.party_id " +
                "WHERE u.organization_id=? AND u.role_type_id<>'TENANT' " +
                "ORDER BY (u.role_type_id='OWNER') DESC,p.full_name",
                organizationId));
    }

    @GetMapping("/organizations/{organizationId}/tenants")
    ApiResponse<List<Map<String, Object>>> organizationTenants(@PathVariable Long organizationId) {
        // The portal login is read through scalar subqueries rather than a join: a rejoining tenant
        // can leave an older INACTIVE login behind, and joining would duplicate the tenant row.
        // Prefer the ACTIVE login when both exist.
        String login = "SELECT ul.%s FROM user_login ul " +
                "WHERE ul.organization_id=fp.organization_id AND ul.party_id=fp.party_id " +
                "  AND ul.role_type_id='TENANT' " +
                "ORDER BY (ul.status='ACTIVE') DESC,ul.user_login_id DESC LIMIT 1";
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT p.party_id, p.full_name, p.mobile_number, p.email, " +
                "occ.from_date move_in_date, f.facility_name bed_name, " +
                "(" + login.formatted("user_login_id") + ") user_login_id, " +
                "(" + login.formatted("username") + ") username, " +
                "(" + login.formatted("status") + ") login_status " +
                "FROM facility_party fp " +
                "JOIN person p ON p.party_id = fp.party_id " +
                "LEFT JOIN facility_party occ ON occ.organization_id = fp.organization_id " +
                "  AND occ.party_id = fp.party_id AND occ.role_type_id = 'OCCUPANT' AND occ.thru_date IS NULL " +
                "LEFT JOIN facility f ON f.facility_id = occ.facility_id " +
                "WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT' AND fp.thru_date IS NULL " +
                "ORDER BY p.full_name",
                organizationId, organizationId));
    }

    @GetMapping("/organizations/{organizationId}/channels")
    ApiResponse<Map<String, Boolean>> organizationChannels(@PathVariable Long organizationId) {
        return ApiResponse.ok(channelService.channels(organizationId));
    }

    @PatchMapping("/organizations/{organizationId}/channels")
    ApiResponse<Map<String, Boolean>> updateOrganizationChannels(@PathVariable Long organizationId,
                                                                 @RequestBody Map<String, Object> body) {
        String channel = body.get("channel") == null ? null : String.valueOf(body.get("channel"));
        Object raw = body.get("enabled");
        boolean enabled = Boolean.TRUE.equals(raw) || "true".equalsIgnoreCase(String.valueOf(raw));
        return ApiResponse.ok("Channel updated", channelService.setChannel(organizationId, channel, enabled));
    }

    @GetMapping("/organizations/{organizationId}/tenant-login")
    ApiResponse<Map<String, Boolean>> tenantLoginStatus(@PathVariable Long organizationId) {
        return ApiResponse.ok(Map.of("enabled", tenantLoginPolicy.enabled(organizationId)));
    }

    @PatchMapping("/organizations/{organizationId}/tenant-login")
    ApiResponse<Map<String, Boolean>> setTenantLogin(@PathVariable Long organizationId,
                                                     @RequestBody Map<String, Object> body) {
        Object raw = body.get("enabled");
        boolean enabled = Boolean.TRUE.equals(raw) || "true".equalsIgnoreCase(String.valueOf(raw));
        tenantLoginPolicy.setEnabled(organizationId, enabled);
        auditService.log(organizationId, currentUser.userLoginId(), "TENANT_LOGIN_FEATURE_TOGGLED",
                "ORGANIZATION", organizationId, "Tenant Login " + (enabled ? "enabled" : "disabled"));
        return ApiResponse.ok("Tenant Login " + (enabled ? "enabled" : "disabled"), Map.of("enabled", enabled));
    }

    @GetMapping("/audit-logs")
    ApiResponse<List<Map<String, Object>>> auditLogs(@RequestParam(defaultValue = "100") int limit) {
        return ApiResponse.ok(jdbc.queryForList("SELECT audit_log_id,organization_id,user_login_id,action,entity_type,entity_id,ip_address,details,created_at " +
                "FROM audit_log ORDER BY created_at DESC LIMIT ?", Math.min(Math.max(limit, 1), 500)));
    }

    @GetMapping("/system-settings")
    ApiResponse<List<Map<String, Object>>> settings() {
        return ApiResponse.ok(jdbc.queryForList("SELECT setting_key,CASE WHEN encrypted THEN '********' ELSE setting_value END setting_value,encrypted,updated_at FROM system_setting"));
    }

    @PatchMapping("/system-settings")
    ApiResponse<Void> updateSettings(@RequestBody Map<String, String> values) {
        values.forEach((key, value) -> jdbc.update("INSERT INTO system_setting(setting_key,setting_value,encrypted,updated_by_user_login_id,updated_at) " +
                        "VALUES(?,?,FALSE,?,?) ON CONFLICT (setting_key) DO UPDATE SET " +
                        "setting_value=EXCLUDED.setting_value," +
                        "updated_by_user_login_id=EXCLUDED.updated_by_user_login_id,updated_at=EXCLUDED.updated_at",
                key, value, currentUser.userLoginId(), LocalDateTime.now()));
        return ApiResponse.ok(null);
    }

    @PostMapping("/broadcast")
    ApiResponse<Map<String, Object>> broadcast(@Valid @RequestBody BroadcastRequest request) {
        List<Long> orgIds = request.targetOrgId() != null
                ? List.of(request.targetOrgId())
                : jdbc.queryForList(
                        "SELECT facility_id FROM facility WHERE facility_type_id='ORGANIZATION' AND status='ACTIVE'",
                        Long.class);
        int sent = 0;
        for (Long orgId : orgIds) {
            try {
                notificationService.notifyOwners(orgId, "GENERAL", request.title(), request.message(),
                        "BROADCAST", null, Boolean.TRUE.equals(request.important()));
                sent++;
            } catch (Exception ignored) {}
        }
        return ApiResponse.ok(Map.of("sentToOrgs", sent));
    }

    private Long scalar(String sql, Object... args) { Long value = jdbc.queryForObject(sql, Long.class, args); return value == null ? 0 : value; }
    private BigDecimal amount(String sql) { BigDecimal value = jdbc.queryForObject(sql, BigDecimal.class); return value == null ? BigDecimal.ZERO : value; }

    public record BroadcastRequest(@NotBlank String title, @NotBlank String message, Long targetOrgId, Boolean important) {}

    /**
     * A null {@code pricePerTenant} is meaningful, not missing: it clears the org's override and
     * puts it back on the platform default. Validation lives in
     * {@link OrganizationTenantRateService} so the default-rate path is checked the same way.
     */
    public record TenantRateRequest(BigDecimal pricePerTenant) {}
    public record ResetPasswordRequest(@NotBlank @Size(min = 8, message = "Password must be at least 8 characters") String newPassword) {}
}
