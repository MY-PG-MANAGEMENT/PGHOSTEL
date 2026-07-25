package com.pgmanager.billing;

import com.pgmanager.notification.NotificationService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * The manual generate path raises only the invoices that come due on the given day — a tenant
 * billed on another day-of-month must not be swept in just because the month matches.
 * JdbcTemplate is mocked so the day-matching and the idempotency guard are exercised
 * without a database.
 */
class InvoiceGenerationServiceTest {

    private JdbcTemplate jdbc;
    private InvoiceGenerationService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        service = new InvoiceGenerationService(jdbc, mock(NotificationService.class));
        lenient().when(jdbc.queryForObject(eq("SELECT LAST_INSERT_ID()"), eq(Long.class))).thenReturn(777L);
    }

    /** An occupancy row as the account query returns it; January so any day-of-month is valid. */
    private Map<String, Object> account(long baId, int anniversaryDay) {
        Map<String, Object> row = new HashMap<>();
        row.put("billing_account_id", baId);
        row.put("party_id", baId * 10);
        row.put("monthly_rent", new BigDecimal("8000"));
        row.put("ac_charges", BigDecimal.ZERO);
        row.put("from_date", java.sql.Date.valueOf(LocalDate.of(2024, 1, anniversaryDay)));
        return row;
    }

    private void stubAccounts(List<Map<String, Object>> accounts) {
        when(jdbc.queryForList(anyString(), any(Object[].class))).thenReturn(accounts);
    }

    private void stubAlreadyInvoiced(boolean exists) {
        when(jdbc.queryForObject(startsWith("SELECT COUNT(*) FROM invoice"), eq(Long.class),
                any(Object.class), any(Object.class))).thenReturn(exists ? 1L : 0L);
    }

    @Test
    void generatesOnlyTheAccountsDueOnThatDay() {
        LocalDate date = LocalDate.of(2026, 7, 15);
        stubAccounts(List.of(account(1L, 15), account(2L, 4)));
        stubAlreadyInvoiced(false);

        InvoiceGenerationService.GenerationResult result = service.generateDueOn(1L, date, null);

        assertThat(result.generated()).isEqualTo(1);
        assertThat(result.notDue()).isEqualTo(1);
        assertThat(result.skipped()).isZero();
        // Exactly one invoice header written — the tenant billed on the 4th is untouched.
        verify(jdbc, times(1)).update(startsWith("INSERT INTO invoice("), any(Object[].class));
    }

    @Test
    void clampsALateAnniversaryOntoTheLastDayOfAShortMonth() {
        stubAccounts(List.of(account(1L, 31)));
        stubAlreadyInvoiced(false);

        InvoiceGenerationService.GenerationResult result =
                service.generateDueOn(1L, LocalDate.of(2026, 2, 28), null);

        assertThat(result.generated()).isEqualTo(1);
        assertThat(result.notDue()).isZero();
    }

    @Test
    void countsAnAlreadyInvoicedAccountAsSkipped() {
        stubAccounts(List.of(account(1L, 15)));
        stubAlreadyInvoiced(true);

        InvoiceGenerationService.GenerationResult result =
                service.generateDueOn(1L, LocalDate.of(2026, 7, 15), null);

        assertThat(result.generated()).isZero();
        assertThat(result.skipped()).isEqualTo(1);
        verify(jdbc, never()).update(startsWith("INSERT INTO invoice("), any(Object[].class));
    }
}
