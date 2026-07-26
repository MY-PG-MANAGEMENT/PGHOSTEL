package com.pgmanager.admin;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.GlobalExceptionHandler;
import com.pgmanager.security.CurrentUser;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Active Tenants report + the per-tenant pricing endpoints. JdbcTemplate and the rate service are
 * mocked, so this pins the arithmetic and the month handling without a database.
 */
class ActiveTenantsReportTest {

    private MockMvc mvc;
    private JdbcTemplate jdbc;
    private OrganizationTenantRateService rateService;
    private AuditService auditService;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        rateService = mock(OrganizationTenantRateService.class);
        auditService = mock(AuditService.class);
        CurrentUser currentUser = mock(CurrentUser.class);
        lenient().when(currentUser.userLoginId()).thenReturn(1L);

        mvc = MockMvcBuilders.standaloneSetup(new SuperAdminController(
                        jdbc, currentUser,
                        mock(com.pgmanager.notification.NotificationService.class),
                        mock(com.pgmanager.auth.AuthService.class),
                        mock(com.pgmanager.notification.OrganizationChannelService.class),
                        mock(PasswordEncoder.class), auditService,
                        mock(com.pgmanager.tenant.TenantLoginPolicy.class), rateService))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    private static Map<String, Object> orgRow(long id, String name, long tenants, long properties) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("organization_id", id);
        row.put("organization_name", name);
        row.put("status", "ACTIVE");
        row.put("active_tenants", tenants);
        row.put("property_count", properties);
        return row;
    }

    @Test
    void multipliesActiveTenantsByTheOrgRateAndTotalsTheAmount() throws Exception {
        when(jdbc.queryForList(anyString(), any(LocalDate.class), any(LocalDate.class), any(LocalDate.class))).thenReturn(List.of(
                orgRow(1L, "Sunrise PG", 20L, 3L),
                orgRow(2L, "Metro Stays", 5L, 1L)));
        when(rateService.defaultRate()).thenReturn(new BigDecimal("15.00"));
        // Org 2 is on a negotiated rate; org 1 follows the default.
        when(rateService.overrides()).thenReturn(Map.of(2L, new BigDecimal("25.00")));

        mvc.perform(get("/api/super-admin/reports/active-tenants").param("month", "2026-06"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.month").value("2026-06"))
                .andExpect(jsonPath("$.data.items[0].organizationName").value("Sunrise PG"))
                .andExpect(jsonPath("$.data.items[0].activeTenants").value(20))
                .andExpect(jsonPath("$.data.items[0].propertyCount").value(3))
                .andExpect(jsonPath("$.data.items[0].pricePerTenant").value(15.00))
                .andExpect(jsonPath("$.data.items[0].customRate").value(false))
                .andExpect(jsonPath("$.data.items[0].amount").value(300.00))   // 20 x 15
                .andExpect(jsonPath("$.data.items[1].pricePerTenant").value(25.00))
                .andExpect(jsonPath("$.data.items[1].customRate").value(true))
                .andExpect(jsonPath("$.data.items[1].amount").value(125.00))   // 5 x 25
                .andExpect(jsonPath("$.data.summary.totalActiveTenants").value(25))
                .andExpect(jsonPath("$.data.summary.totalProperties").value(4))
                .andExpect(jsonPath("$.data.summary.organizationCount").value(2))
                .andExpect(jsonPath("$.data.summary.totalAmount").value(425.00));
    }

    @Test
    void countsOnlyOrganizationsThatActuallyGeneratedACharge() throws Exception {
        when(jdbc.queryForList(anyString(), any(LocalDate.class), any(LocalDate.class), any(LocalDate.class))).thenReturn(List.of(
                orgRow(1L, "Busy PG", 4L, 1L),
                orgRow(2L, "Empty PG", 0L, 2L)));
        when(rateService.defaultRate()).thenReturn(new BigDecimal("15.00"));
        when(rateService.overrides()).thenReturn(Map.of());

        mvc.perform(get("/api/super-admin/reports/active-tenants").param("month", "2026-06"))
                .andExpect(status().isOk())
                // The zero-tenant org still gets a row - a zero line is information.
                .andExpect(jsonPath("$.data.items.length()").value(2))
                .andExpect(jsonPath("$.data.summary.billableOrganizations").value(1))
                .andExpect(jsonPath("$.data.summary.totalAmount").value(60.00));
    }

    @Test
    void scopesTheQueryToTheRequestedMonthBoundaries() throws Exception {
        when(jdbc.queryForList(anyString(), any(LocalDate.class), any(LocalDate.class), any(LocalDate.class))).thenReturn(List.of());
        when(rateService.defaultRate()).thenReturn(new BigDecimal("15.00"));
        when(rateService.overrides()).thenReturn(Map.of());

        mvc.perform(get("/api/super-admin/reports/active-tenants").param("month", "2026-02"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.monthStart").value("2026-02-01"))
                // February, so month end must be the 28th - not a hardcoded 30/31.
                .andExpect(jsonPath("$.data.monthEnd").value("2026-02-28"));

        verify(jdbc).queryForList(anyString(),
                eq(LocalDate.of(2026, 2, 28)), eq(LocalDate.of(2026, 2, 1)), eq(LocalDate.of(2026, 2, 28)));
    }

    @Test
    void defaultsToTheCurrentMonthWhenNoMonthIsGiven() throws Exception {
        when(jdbc.queryForList(anyString(), any(LocalDate.class), any(LocalDate.class), any(LocalDate.class))).thenReturn(List.of());
        when(rateService.defaultRate()).thenReturn(new BigDecimal("15.00"));
        when(rateService.overrides()).thenReturn(Map.of());

        LocalDate expected = LocalDate.now().withDayOfMonth(1);
        mvc.perform(get("/api/super-admin/reports/active-tenants"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.monthStart").value(expected.toString()));
    }

    @Test
    void rejectsAMalformedMonth() throws Exception {
        mvc.perform(get("/api/super-admin/reports/active-tenants").param("month", "June-2026"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("month must be in yyyy-MM format"));
    }

    @Test
    void rejectsAFutureMonth() throws Exception {
        String future = LocalDate.now().plusMonths(2).toString().substring(0, 7);

        mvc.perform(get("/api/super-admin/reports/active-tenants").param("month", future))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("month cannot be in the future"));
    }

    @Test
    void excludesArchivedTenantsFromTheBillableCount() throws Exception {
        when(jdbc.queryForList(anyString(), any(LocalDate.class), any(LocalDate.class), any(LocalDate.class))).thenReturn(List.of());
        when(rateService.defaultRate()).thenReturn(new BigDecimal("15.00"));
        when(rateService.overrides()).thenReturn(Map.of());

        mvc.perform(get("/api/super-admin/reports/active-tenants").param("month", "2026-06"))
                .andExpect(status().isOk());

        // Captured rather than matched with contains(): mixing a value matcher with untyped
        // any() across a varargs parameter misaligns the arity, and Mockito then reports
        // "not invoked" for a call that plainly happened.
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).queryForList(sql.capture(),
                any(LocalDate.class), any(LocalDate.class), any(LocalDate.class));
        // Archiving leaves thru_date null on purpose, so without this exclusion the platform
        // would keep charging for tenants the owner deleted.
        assertThat(sql.getValue()).contains("tenant_archive");
        assertThat(sql.getValue()).contains("role_type_id = 'TENANT'");
    }

    @Test
    void setsAPerOrganizationRateAndAuditsIt() throws Exception {
        when(jdbc.queryForObject(anyString(), eq(Integer.class), anyLong())).thenReturn(1);
        when(rateService.rateFor(7L)).thenReturn(new BigDecimal("30.00"));

        mvc.perform(put("/api/super-admin/tenant-rates/7")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"pricePerTenant\":30.00}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.pricePerTenant").value(30.00));

        verify(rateService).setOverride(eq(7L), eq(new BigDecimal("30.00")), eq(1L));
        verify(auditService).log(eq(7L), eq(1L), eq("ORGANIZATION_TENANT_RATE_CHANGED"),
                eq("FACILITY"), eq(7L), anyString());
    }

    @Test
    void clearingARatePutsTheOrgBackOnTheDefault() throws Exception {
        when(jdbc.queryForObject(anyString(), eq(Integer.class), anyLong())).thenReturn(1);
        when(rateService.rateFor(7L)).thenReturn(new BigDecimal("15.00"));

        mvc.perform(put("/api/super-admin/tenant-rates/7")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"pricePerTenant\":null}"))
                .andExpect(status().isOk());

        // Null is meaningful here - it clears the override rather than being a missing field.
        verify(rateService).setOverride(eq(7L), isNull(), eq(1L));
    }

    @Test
    void organizationIdZeroUpdatesThePlatformDefault() throws Exception {
        when(rateService.defaultRate()).thenReturn(new BigDecimal("20.00"));

        mvc.perform(put("/api/super-admin/tenant-rates/0")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"pricePerTenant\":20.00}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.defaultPricePerTenant").value(20.00));

        verify(rateService).setDefaultRate(eq(new BigDecimal("20.00")), eq(1L));
        verify(rateService, never()).setOverride(anyLong(), any(), anyLong());
    }

    @Test
    void rejectsARateForAnUnknownOrganization() throws Exception {
        when(jdbc.queryForObject(anyString(), eq(Integer.class), anyLong())).thenReturn(0);

        mvc.perform(put("/api/super-admin/tenant-rates/999")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"pricePerTenant\":10.00}"))
                .andExpect(status().isNotFound());
    }
}
