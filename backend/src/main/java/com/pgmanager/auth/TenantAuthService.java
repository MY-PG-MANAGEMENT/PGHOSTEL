package com.pgmanager.auth;

import com.pgmanager.audit.AuditService;
import com.pgmanager.auth.dto.AuthDtos.AuthResponse;
import com.pgmanager.auth.dto.AuthDtos.TenantLoginRequest;
import com.pgmanager.security.AppUserDetailsService;
import com.pgmanager.security.AppUserPrincipal;
import com.pgmanager.security.RoleType;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * Authenticates tenants by <b>mobile + password</b>. The owner/admin path in
 * {@link AuthService} is username-based (via Spring's {@code AuthenticationManager});
 * tenants never type a username, so this resolves the login manually and verifies the
 * password with {@link PasswordEncoder}.
 *
 * <p>Because the same mobile can own logins in multiple organizations, resolution can
 * return several candidates. When it does and the caller has not chosen an org, we return
 * {@code needsOrgSelection} + the org list instead of logging in.
 */
@Service
@RequiredArgsConstructor
public class TenantAuthService {

    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwordEncoder;
    private final AppUserDetailsService userDetailsService;
    private final AuthService authService;
    private final AuditService auditService;

    /** Result of a tenant login attempt: either a token pair, or an org-selection prompt. */
    public record TenantAuthResult(boolean needsOrgSelection, List<Map<String, Object>> organizations, AuthResponse auth) {}

    @Transactional
    public TenantAuthResult login(TenantLoginRequest request) {
        List<Map<String, Object>> candidates = jdbc.queryForList(
                "SELECT ul.user_login_id, ul.username, ul.organization_id, ul.password_hash, " +
                "ul.must_change_password, o.facility_name AS org_name " +
                "FROM user_login ul " +
                "JOIN person pr ON pr.party_id = ul.party_id " +
                "LEFT JOIN facility o ON o.facility_id = ul.organization_id " +
                "WHERE ul.role_type_id = ? AND ul.status = 'ACTIVE' AND pr.mobile_number = ?",
                RoleType.TENANT, request.mobile());

        if (candidates.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid mobile number or password");
        }

        // Narrow to the chosen org when supplied.
        if (request.organizationId() != null) {
            candidates = candidates.stream()
                    .filter(c -> request.organizationId().equals(asLong(c.get("organization_id"))))
                    .toList();
            if (candidates.isEmpty()) {
                throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid mobile number or password");
            }
        }

        // Same mobile active in more than one org and no choice yet → ask the caller to pick.
        if (candidates.size() > 1) {
            List<Map<String, Object>> orgs = candidates.stream()
                    .map(c -> Map.of(
                            "organizationId", asLong(c.get("organization_id")),
                            "organizationName", c.get("org_name") == null ? "" : c.get("org_name")))
                    .distinct()
                    .toList();
            return new TenantAuthResult(true, orgs, null);
        }

        Map<String, Object> login = candidates.get(0);
        String hash = (String) login.get("password_hash");
        if (!passwordEncoder.matches(request.password(), hash)) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid mobile number or password");
        }

        String username = (String) login.get("username");
        Long userLoginId = asLong(login.get("user_login_id"));
        Long organizationId = asLong(login.get("organization_id"));
        boolean mustChange = toBool(login.get("must_change_password"));

        jdbc.update("UPDATE user_login SET last_login_at=? WHERE user_login_id=?", LocalDateTime.now(), userLoginId);

        AppUserPrincipal principal = (AppUserPrincipal) userDetailsService.loadUserByUsername(username);
        AuthResponse tokens = authService.issueTokensFor(principal);
        auditService.log(organizationId, userLoginId, "TENANT_LOGIN", "USER_LOGIN", userLoginId, "Tenant logged in");

        // Re-emit with the tenant's must-change-password flag so the app can force a reset.
        AuthResponse auth = new AuthResponse(tokens.accessToken(), tokens.refreshToken(), tokens.organizationId(),
                tokens.roleTypeId(), tokens.fullName(), mustChange, tokens.partyId());
        return new TenantAuthResult(false, null, auth);
    }

    private static Long asLong(Object o) {
        return o == null ? null : ((Number) o).longValue();
    }

    private static boolean toBool(Object o) {
        return com.pgmanager.common.util.JdbcValues.toBoolean(o, false);
    }
}
