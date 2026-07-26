package com.pgmanager.tenant;

import com.pgmanager.admin.SuperAdminController;
import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.GlobalExceptionHandler;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.selfcheckin.SelfCheckinTokenService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The super-admin Tenant Login toggle and the owner-side probe that reads it, as one contract:
 * whatever the admin sets for an org is exactly what {@code GET /api/tenants/login-feature}
 * reports back, which is what shows or hides "Generate Tenant Logins" in owner Settings.
 *
 * <p>Both endpoints already delegated to {@link TenantLoginPolicy}, but nothing asserted the
 * round trip — so an accidental default-to-true on either side would have gone unnoticed.
 */
class TenantLoginFeatureGateTest {

    private MockMvc adminMvc;
    private MockMvc ownerMvc;
    private TenantLoginPolicy policy;
    private AuditService auditService;

    @BeforeEach
    void setUp() {
        policy = mock(TenantLoginPolicy.class);
        auditService = mock(AuditService.class);

        CurrentUser superAdmin = mock(CurrentUser.class);
        lenient().when(superAdmin.userLoginId()).thenReturn(1L);
        adminMvc = MockMvcBuilders.standaloneSetup(new SuperAdminController(
                        mock(JdbcTemplate.class), superAdmin,
                        mock(com.pgmanager.notification.NotificationService.class),
                        mock(com.pgmanager.auth.AuthService.class),
                        mock(com.pgmanager.notification.OrganizationChannelService.class),
                        mock(PasswordEncoder.class), auditService, policy,
                        mock(com.pgmanager.admin.OrganizationTenantRateService.class)))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        CurrentUser owner = mock(CurrentUser.class);
        lenient().when(owner.organizationId()).thenReturn(42L);
        lenient().when(owner.userLoginId()).thenReturn(7L);
        ownerMvc = MockMvcBuilders.standaloneSetup(new TenantController(
                        mock(TenantService.class), mock(TenantArchiveService.class), owner,
                        mock(SelfCheckinTokenService.class), policy, mock(TenantLoginService.class)))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    @Test
    void ownerProbeReportsEnabledWhenTheAdminHasTurnedItOn() throws Exception {
        when(policy.enabled(42L)).thenReturn(true);

        ownerMvc.perform(get("/api/tenants/login-feature"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.enabled").value(true));
    }

    @Test
    void ownerProbeReportsDisabledWhenTheAdminHasTurnedItOff() throws Exception {
        when(policy.enabled(42L)).thenReturn(false);

        ownerMvc.perform(get("/api/tenants/login-feature"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.enabled").value(false));
    }

    @Test
    void theProbeIsScopedToTheCallersOwnOrganization() throws Exception {
        when(policy.enabled(42L)).thenReturn(true);

        ownerMvc.perform(get("/api/tenants/login-feature")).andExpect(status().isOk());

        // Never an org id from the request - the owner must not be able to read
        // another organization's feature state.
        verify(policy).enabled(42L);
    }

    @Test
    void adminToggleOnPersistsAndAudits() throws Exception {
        adminMvc.perform(patch("/api/super-admin/organizations/42/tenant-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.enabled").value(true));

        verify(policy).setEnabled(42L, true);
        verify(auditService).log(eq(42L), eq(1L), eq("TENANT_LOGIN_FEATURE_TOGGLED"),
                eq("ORGANIZATION"), eq(42L), anyString());
    }

    @Test
    void adminToggleOffPersists() throws Exception {
        adminMvc.perform(patch("/api/super-admin/organizations/42/tenant-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":false}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.enabled").value(false));

        verify(policy).setEnabled(42L, false);
    }

    @Test
    void aMissingEnabledFlagTurnsTheFeatureOffRatherThanOn() throws Exception {
        // The feature is opt-in, so a malformed body must never grant it.
        adminMvc.perform(patch("/api/super-admin/organizations/42/tenant-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.enabled").value(false));

        verify(policy).setEnabled(42L, false);
    }

    @Test
    void adminStatusReadReflectsThePolicy() throws Exception {
        when(policy.enabled(42L)).thenReturn(true);

        adminMvc.perform(get("/api/super-admin/organizations/42/tenant-login"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.enabled").value(true));
    }
}
