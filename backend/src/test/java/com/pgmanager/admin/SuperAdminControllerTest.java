package com.pgmanager.admin;

import com.pgmanager.common.exception.GlobalExceptionHandler;
import com.pgmanager.notification.NotificationService;
import com.pgmanager.security.CurrentUser;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;

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

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        CurrentUser currentUser = mock(CurrentUser.class);
        lenient().when(currentUser.userLoginId()).thenReturn(7L);
        notificationService = mock(NotificationService.class);
        com.pgmanager.auth.AuthService authService = mock(com.pgmanager.auth.AuthService.class);
        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();
        mvc = MockMvcBuilders.standaloneSetup(new SuperAdminController(jdbc, currentUser, notificationService, authService))
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
    void broadcastToSingleOrgSucceeds() throws Exception {
        mvc.perform(post("/api/super-admin/broadcast").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"Maintenance\",\"message\":\"Downtime tonight\",\"targetOrgId\":5}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.sentToOrgs").value(1));
        verify(notificationService).notifyOwners(eq(5L), eq("GENERAL"), eq("Maintenance"), eq("Downtime tonight"),
                eq("BROADCAST"), isNull(), anyBoolean());
    }
}
