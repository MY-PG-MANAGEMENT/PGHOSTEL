package com.pgmanager.admin;

import com.pgmanager.auth.AuthService;
import com.pgmanager.auth.dto.AuthDtos.RegisterOwnerRequest;
import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.notification.NotificationService;
import com.pgmanager.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.time.LocalDateTime;
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

    private static final Set<String> ALLOWED_ORG_STATUSES = Set.of("ACTIVE", "INACTIVE", "SUSPENDED");

    @GetMapping("/dashboard")
    ApiResponse<Map<String, Object>> dashboard() {
        return ApiResponse.ok(Map.of(
                "totalOrganizations", scalar("SELECT COUNT(*) FROM facility WHERE facility_type_id='ORGANIZATION'"),
                "activeOrganizations", scalar("SELECT COUNT(*) FROM facility WHERE facility_type_id='ORGANIZATION' AND status='ACTIVE'"),
                "totalProperties", scalar("SELECT COUNT(*) FROM facility WHERE facility_type_id='PROPERTY'"),
                "totalTenants", scalar("SELECT COUNT(DISTINCT party_id) FROM facility_party WHERE role_type_id='TENANT' AND thru_date IS NULL"),
                "monthlyRevenue", amount("SELECT COALESCE(SUM(p.amount),0) FROM payment p WHERE p.payment_date>=DATE_FORMAT(CURRENT_DATE,'%Y-%m-01')"),
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
        return ApiResponse.ok(null);
    }

    @GetMapping("/properties")
    ApiResponse<List<Map<String, Object>>> properties() {
        return ApiResponse.ok(jdbc.queryForList("SELECT p.facility_id,p.facility_name,p.organization_id,o.facility_name organization_name,p.status " +
                "FROM facility p JOIN facility o ON o.facility_id=p.organization_id WHERE p.facility_type_id='PROPERTY' ORDER BY p.created_at DESC"));
    }

    @GetMapping("/users")
    ApiResponse<List<Map<String, Object>>> users() {
        return ApiResponse.ok(jdbc.queryForList("SELECT u.user_login_id,u.username,u.role_type_id,u.organization_id,u.status,p.full_name,p.mobile_number " +
                "FROM user_login u JOIN person p ON p.party_id=u.party_id ORDER BY u.created_at DESC"));
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

    @GetMapping("/plans")
    ApiResponse<List<Map<String, Object>>> plans() {
        return ApiResponse.ok(jdbc.queryForList("SELECT plan_id,plan_code,name,price_monthly,property_limit,active FROM subscription_plan ORDER BY price_monthly"));
    }

    @PostMapping("/plans")
    ApiResponse<Map<String, Object>> createPlan(@Valid @RequestBody PlanRequest request) {
        jdbc.update("INSERT INTO subscription_plan(plan_code,name,price_monthly,property_limit,active,created_at,updated_at) VALUES(?,?,?,?,TRUE,?,?)",
                request.planCode(), request.name(), request.priceMonthly(), request.propertyLimit(), LocalDateTime.now(), LocalDateTime.now());
        Long id = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        return ApiResponse.ok(Map.of("planId", id, "planCode", request.planCode(), "active", true));
    }

    @GetMapping("/reports/revenue")
    ApiResponse<List<Map<String, Object>>> revenueReport() {
        return ApiResponse.ok(jdbc.queryForList("SELECT DATE_FORMAT(payment_date,'%Y-%m') period,organization_id,SUM(amount) amount " +
                "FROM payment WHERE status='RECEIVED' GROUP BY period,organization_id ORDER BY period DESC"));
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

    @GetMapping("/organizations/{organizationId}/tenants")
    ApiResponse<List<Map<String, Object>>> organizationTenants(@PathVariable Long organizationId) {
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT p.party_id, p.full_name, p.mobile_number, p.email, " +
                "occ.from_date move_in_date, f.facility_name bed_name " +
                "FROM facility_party fp " +
                "JOIN person p ON p.party_id = fp.party_id " +
                "LEFT JOIN facility_party occ ON occ.organization_id = fp.organization_id " +
                "  AND occ.party_id = fp.party_id AND occ.role_type_id = 'OCCUPANT' AND occ.thru_date IS NULL " +
                "LEFT JOIN facility f ON f.facility_id = occ.facility_id " +
                "WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT' AND fp.thru_date IS NULL " +
                "ORDER BY p.full_name",
                organizationId, organizationId));
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
                        "VALUES(?,?,FALSE,?,?) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value),updated_by_user_login_id=VALUES(updated_by_user_login_id),updated_at=VALUES(updated_at)",
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

    public record PlanRequest(@NotBlank String planCode, @NotBlank String name, @DecimalMin("0") BigDecimal priceMonthly, Integer propertyLimit) {}
    public record BroadcastRequest(@NotBlank String title, @NotBlank String message, Long targetOrgId, Boolean important) {}
}
