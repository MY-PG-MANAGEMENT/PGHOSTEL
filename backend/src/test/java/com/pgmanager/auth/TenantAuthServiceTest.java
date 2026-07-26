package com.pgmanager.auth;

import com.pgmanager.audit.AuditService;
import com.pgmanager.auth.dto.AuthDtos.AuthResponse;
import com.pgmanager.auth.dto.AuthDtos.TenantLoginRequest;
import com.pgmanager.security.AppUserDetailsService;
import com.pgmanager.security.AppUserPrincipal;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** Mobile+password tenant auth: not-found, org disambiguation, wrong password, success. */
class TenantAuthServiceTest {

    private JdbcTemplate jdbc;
    private PasswordEncoder passwordEncoder;
    private AppUserDetailsService userDetailsService;
    private AuthService authService;
    private TenantAuthService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        passwordEncoder = mock(PasswordEncoder.class);
        userDetailsService = mock(AppUserDetailsService.class);
        authService = mock(AuthService.class);
        AuditService auditService = mock(AuditService.class);
        service = new TenantAuthService(jdbc, passwordEncoder, userDetailsService, authService, auditService);
    }

    private Map<String, Object> candidate(long id, long org, String orgName, int mustChange) {
        return candidate(id, org, orgName, mustChange, "ACTIVE");
    }

    private Map<String, Object> candidate(long id, long org, String orgName, int mustChange, String orgStatus) {
        return Map.of("user_login_id", id, "username", "9876543210@" + org, "organization_id", org,
                "password_hash", "HASH", "must_change_password", mustChange, "org_name", orgName,
                "org_status", orgStatus);
    }

    @Test
    void unknownMobileRejected() {
        when(jdbc.queryForList(anyString(), any(Object[].class))).thenReturn(List.of());
        assertThatThrownBy(() -> service.login(new TenantLoginRequest("9876543210", "pw", null)))
                .isInstanceOf(ResponseStatusException.class);
    }

    @Test
    void multipleOrgsPromptsSelection() {
        when(jdbc.queryForList(anyString(), any(Object[].class)))
                .thenReturn(List.of(candidate(1L, 10L, "Org A", 0), candidate(2L, 20L, "Org B", 0)));

        var result = service.login(new TenantLoginRequest("9876543210", "pw", null));

        assertThat(result.needsOrgSelection()).isTrue();
        assertThat(result.organizations()).hasSize(2);
        assertThat(result.auth()).isNull();
    }

    @Test
    void wrongPasswordRejected() {
        when(jdbc.queryForList(anyString(), any(Object[].class)))
                .thenReturn(List.of(candidate(1L, 10L, "Org A", 0)));
        when(passwordEncoder.matches(eq("pw"), anyString())).thenReturn(false);

        assertThatThrownBy(() -> service.login(new TenantLoginRequest("9876543210", "pw", null)))
                .isInstanceOf(ResponseStatusException.class);
    }

    @Test
    void deactivatedOrganizationRejectedWithForbidden() {
        when(jdbc.queryForList(anyString(), any(Object[].class)))
                .thenReturn(List.of(candidate(1L, 10L, "Org A", 0, "INACTIVE")));

        assertThatThrownBy(() -> service.login(new TenantLoginRequest("9876543210", "pw", null)))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("deactivated");
        verify(passwordEncoder, never()).matches(anyString(), anyString());
    }

    @Test
    void deactivatedOrganizationDroppedFromOrgPicker() {
        when(jdbc.queryForList(anyString(), any(Object[].class)))
                .thenReturn(List.of(candidate(1L, 10L, "Org A", 0),
                        candidate(2L, 20L, "Org B", 0, "SUSPENDED")));
        when(passwordEncoder.matches(eq("pw"), anyString())).thenReturn(true);
        AppUserPrincipal principal = new AppUserPrincipal(1L, 100L, 10L, "9876543210@10", "HASH", "TENANT", "ACTIVE", "Ravi");
        when(userDetailsService.loadUserByUsername("9876543210@10")).thenReturn(principal);
        when(authService.issueTokensFor(principal))
                .thenReturn(new AuthResponse("access", "refresh", 10L, "TENANT", "Ravi", false, 100L));

        // Only one org survives the status filter, so there is nothing to disambiguate.
        var result = service.login(new TenantLoginRequest("9876543210", "pw", null));

        assertThat(result.needsOrgSelection()).isFalse();
        assertThat(result.auth().organizationId()).isEqualTo(10L);
    }

    @Test
    void successReturnsTokensAndMustChangeFlag() {
        when(jdbc.queryForList(anyString(), any(Object[].class)))
                .thenReturn(List.of(candidate(1L, 10L, "Org A", 1)));
        when(passwordEncoder.matches(eq("pw"), anyString())).thenReturn(true);
        AppUserPrincipal principal = new AppUserPrincipal(1L, 100L, 10L, "9876543210@10", "HASH", "TENANT", "ACTIVE", "Ravi");
        when(userDetailsService.loadUserByUsername("9876543210@10")).thenReturn(principal);
        when(authService.issueTokensFor(principal))
                .thenReturn(new AuthResponse("access", "refresh", 10L, "TENANT", "Ravi", false, 100L));

        var result = service.login(new TenantLoginRequest("9876543210", "pw", null));

        assertThat(result.needsOrgSelection()).isFalse();
        assertThat(result.auth().accessToken()).isEqualTo("access");
        assertThat(result.auth().mustChangePassword()).isTrue();
        assertThat(result.auth().partyId()).isEqualTo(100L);
        verify(jdbc).update(contains("last_login_at"), any(Object[].class));
    }
}
