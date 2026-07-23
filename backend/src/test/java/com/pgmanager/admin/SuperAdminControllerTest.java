package com.pgmanager.admin;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.GlobalExceptionHandler;
import com.pgmanager.notification.NotificationService;
import com.pgmanager.security.CurrentUser;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;

import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Tests the org-status whitelist (correctness fix) and broadcast validation.
 * JdbcTemplate mocked; no DB. Role-based 403 enforcement is covered by the
 * Testcontainers integration layer (needs the real security filter chain).
 */
class SuperAdminControllerTest {

    private MockMvc mvc;
    private JdbcTemplate jdbc;
    private NotificationService notificationService;
    private PasswordEncoder passwordEncoder;
    private AuditService auditService;
    private com.pgmanager.tenant.TenantLoginPolicy tenantLoginPolicy;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        CurrentUser currentUser = mock(CurrentUser.class);
        lenient().when(currentUser.userLoginId()).thenReturn(7L);
        notificationService = mock(NotificationService.class);
        com.pgmanager.auth.AuthService authService = mock(com.pgmanager.auth.AuthService.class);
        com.pgmanager.notification.OrganizationChannelService channelService =
                mock(com.pgmanager.notification.OrganizationChannelService.class);
        passwordEncoder = mock(PasswordEncoder.class);
        lenient().when(passwordEncoder.encode(anyString())).thenReturn("ENCODED");
        auditService = mock(AuditService.class);
        tenantLoginPolicy = mock(com.pgmanager.tenant.TenantLoginPolicy.class);
        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();
        mvc = MockMvcBuilders.standaloneSetup(new SuperAdminController(jdbc, currentUser, notificationService, authService, channelService, passwordEncoder, auditService, tenantLoginPolicy))
                .setControllerAdvice(new GlobalExceptionHandler())
                .setValidator(validator)
                .build();
    }

    @Test
    void organizationStatusRejectsInvalidStatus() throws Exception {
        mvc.perform(patch("/api/super-admin/organizations/1/status").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"status\":\"BOGUS\"}"))
                .andExpect(status().isBadRequest());
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }

    @Test
    void organizationStatusAcceptsWhitelistedStatus() throws Exception {
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);

        mvc.perform(patch("/api/super-admin/organizations/1/status").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"status\":\"INACTIVE\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));
        verify(jdbc).update(anyString(), any(Object[].class));
    }

    @Test
    void organizationStatusReturns404WhenOrgMissing() throws Exception {
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(0);

        mvc.perform(patch("/api/super-admin/organizations/999/status").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"status\":\"ACTIVE\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void broadcastRejectsBlankTitle() throws Exception {
        mvc.perform(post("/api/super-admin/broadcast").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"\",\"message\":\"hello\"}"))
                .andExpect(status().isBadRequest());
        verifyNoInteractions(notificationService);
    }

    @Test
    void resetPasswordUpdatesHashAndRevokesSessions() throws Exception {
        when(jdbc.queryForMap(anyString(), eq(3L)))
                .thenReturn(Map.of("username", "owner1", "role_type_id", "OWNER", "organization_id", 5L));
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);

        mvc.perform(post("/api/super-admin/users/3/reset-password").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"newPassword\":\"secret123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        verify(passwordEncoder).encode("secret123");
        // one update for the password hash, one for revoking refresh tokens
        verify(jdbc, times(2)).update(anyString(), any(Object[].class));
        verify(auditService).log(eq(5L), eq(7L), eq("PASSWORD_RESET_BY_ADMIN"), eq("USER_LOGIN"), eq(3L), anyString());
    }

    @Test
    void resetPasswordRejectsShortPassword() throws Exception {
        mvc.perform(post("/api/super-admin/users/3/reset-password").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"newPassword\":\"short\"}"))
                .andExpect(status().isBadRequest());
        verifyNoInteractions(passwordEncoder);
    }

    @Test
    void resetPasswordRejectsSuperAdmin() throws Exception {
        when(jdbc.queryForMap(anyString(), eq(1L)))
                .thenReturn(Map.of("username", "root", "role_type_id", "SUPER_ADMIN"));

        mvc.perform(post("/api/super-admin/users/1/reset-password").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"newPassword\":\"secret123\"}"))
                .andExpect(status().isBadRequest());
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }

    @Test
    void resetPasswordReturns404WhenUserMissing() throws Exception {
        when(jdbc.queryForMap(anyString(), eq(999L))).thenThrow(new EmptyResultDataAccessException(1));

        mvc.perform(post("/api/super-admin/users/999/reset-password").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"newPassword\":\"secret123\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void tenantLoginToggleEnablesFeature() throws Exception {
        mvc.perform(patch("/api/super-admin/organizations/5/tenant-login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"enabled\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.enabled").value(true));
        verify(tenantLoginPolicy).setEnabled(5L, true);
    }

    @Test
    void tenantLoginStatusReadsPolicy() throws Exception {
        when(tenantLoginPolicy.enabled(5L)).thenReturn(true);
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get("/api/super-admin/organizations/5/tenant-login"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.enabled").value(true));
    }

    @Test
    void broadcastToSingleOrgSucceeds() throws Exception {
        mvc.perform(post("/api/super-admin/broadcast").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"Maintenance\",\"message\":\"Downtime tonight\",\"targetOrgId\":5}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.sentToOrgs").value(1));
        verify(notificationService).notifyOwners(eq(5L), eq("GENERAL"), eq("Maintenance"), eq("Downtime tonight"),
                eq("BROADCAST"), isNull(), anyBoolean());
    }
}
