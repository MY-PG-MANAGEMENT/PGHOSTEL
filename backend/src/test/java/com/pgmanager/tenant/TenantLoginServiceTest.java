package com.pgmanager.tenant;

import com.pgmanager.audit.AuditService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * The tenant-login generation matrix (feature gate, create, reactivate, reuse). JdbcTemplate mocked.
 */
class TenantLoginServiceTest {

    private static final long ORG = 1L;
    private static final long PARTY = 100L;
    private static final String MOBILE = "9876543210";

    private JdbcTemplate jdbc;
    private PasswordEncoder passwordEncoder;
    private TenantLoginPolicy policy;
    private AuditService auditService;
    private TenantLoginService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        passwordEncoder = mock(PasswordEncoder.class);
        policy = mock(TenantLoginPolicy.class);
        auditService = mock(AuditService.class);
        lenient().when(passwordEncoder.encode(anyString())).thenReturn("ENCODED");
        // The new login's id comes back from RETURNING on the INSERT itself.
        lenient().when(jdbc.queryForObject(contains("INSERT INTO user_login"), eq(Long.class), any(Object[].class)))
                .thenReturn(5L);
        service = new TenantLoginService(jdbc, passwordEncoder, policy, auditService);
    }

    @Test
    void doesNothingWhenFeatureDisabled() {
        when(policy.enabled(ORG)).thenReturn(false);
        service.provisionForTenant(ORG, PARTY, MOBILE);
        verify(jdbc, never()).queryForList(anyString(), any(Object[].class));
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }

    @Test
    void createsLoginWhenNoCandidateExists() {
        when(policy.enabled(ORG)).thenReturn(true);
        when(jdbc.queryForList(anyString(), any(Object[].class))).thenReturn(List.of());

        service.provisionForTenant(ORG, PARTY, MOBILE);

        verify(passwordEncoder).encode(TenantLoginService.TEMP_PASSWORD);
        verify(jdbc).queryForObject(contains("INSERT INTO user_login"), eq(Long.class), any(Object[].class));
    }

    @Test
    void reactivatesInactiveLoginOnRejoin() {
        when(policy.enabled(ORG)).thenReturn(true);
        when(jdbc.queryForList(anyString(), any(Object[].class)))
                .thenReturn(List.of(Map.of("user_login_id", 9L, "status", "INACTIVE")));

        service.provisionForTenant(ORG, PARTY, MOBILE);

        verify(jdbc).update(contains("status='ACTIVE'"), any(Object[].class));
        verify(jdbc, never()).update(contains("INSERT INTO user_login"), any(Object[].class));
        verify(auditService).log(eq(ORG), isNull(), eq("TENANT_LOGIN_REACTIVATED"), eq("USER_LOGIN"), eq(9L), anyString());
    }

    @Test
    void reusesActiveLoginWithoutDuplicating() {
        when(policy.enabled(ORG)).thenReturn(true);
        when(jdbc.queryForList(anyString(), any(Object[].class)))
                .thenReturn(List.of(Map.of("user_login_id", 9L, "status", "ACTIVE")));

        service.provisionForTenant(ORG, PARTY, MOBILE);

        // Re-points the existing active login to the newest party; never inserts or reactivates.
        verify(jdbc).update(contains("SET party_id=?, updated_at=?"), any(Object[].class));
        verify(jdbc, never()).update(contains("INSERT INTO user_login"), any(Object[].class));
        verify(jdbc, never()).update(contains("status='ACTIVE'"), any(Object[].class));
    }

    @Test
    void disableForCheckoutMarksInactiveAndRevokesTokens() {
        when(jdbc.queryForList(anyString(), eq(Long.class), any(Object[].class)))
                .thenReturn(List.of(9L));

        service.disableForCheckout(ORG, PARTY);

        verify(jdbc).update(contains("status='INACTIVE'"), any(Object[].class));
        verify(jdbc).update(contains("UPDATE refresh_token SET revoked=TRUE"), any(Object[].class));
    }
}
