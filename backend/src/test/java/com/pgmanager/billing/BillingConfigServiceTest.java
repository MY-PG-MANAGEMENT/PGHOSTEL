package com.pgmanager.billing;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Regression cover for reading the config row. MySQL hands {@code auto_generate_enabled}
 * (TINYINT(1)) back as a {@link Boolean}, so casting it to Number blew up with a 500 the
 * moment an org actually saved a setting — until then every org fell through the
 * "no row → DEFAULT" branch and the cast was never reached.
 */
class BillingConfigServiceTest {

    private JdbcTemplate jdbc;
    private BillingConfigService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        service = new BillingConfigService(jdbc);
    }

    private void stubRow(Object leadDays, Object graceDays, Object autoEnabled) {
        Map<String, Object> row = new HashMap<>();
        row.put("invoice_lead_days", leadDays);
        row.put("checkout_grace_days", graceDays);
        row.put("auto_generate_enabled", autoEnabled);
        when(jdbc.queryForList(anyString(), any(Object[].class))).thenReturn(List.of(row));
    }

    @Test
    void readsTheFlagWhenTheDriverReturnsABoolean() {
        stubRow(1, 1, Boolean.TRUE);

        BillingConfigService.BillingConfig config = service.get(1L);

        assertThat(config.invoiceLeadDays()).isEqualTo(1);
        assertThat(config.checkoutGraceDays()).isEqualTo(1);
        assertThat(config.autoGenerateEnabled()).isTrue();
    }

    @Test
    void readsAFalseBooleanFlag() {
        stubRow(1, 2, Boolean.FALSE);

        assertThat(service.get(1L).autoGenerateEnabled()).isFalse();
    }

    /** Through COALESCE / other drivers the same column arrives as a Number. */
    @Test
    void readsTheFlagWhenTheDriverReturnsANumber() {
        stubRow(1, 2, 0);

        assertThat(service.get(1L).autoGenerateEnabled()).isFalse();
    }

    @Test
    void fallsBackToDefaultsWhenTheOrgHasNoRow() {
        when(jdbc.queryForList(anyString(), any(Object[].class))).thenReturn(List.of());

        assertThat(service.get(1L)).isEqualTo(BillingConfigService.DEFAULT);
    }

    @Test
    void clampsOutOfRangeValues() {
        stubRow(99, -5, Boolean.TRUE);

        BillingConfigService.BillingConfig config = service.get(1L);

        assertThat(config.invoiceLeadDays()).isEqualTo(BillingConfigService.MAX_LEAD_DAYS);
        assertThat(config.checkoutGraceDays()).isEqualTo(BillingConfigService.MIN_GRACE_DAYS);
    }

    @Test
    void upsertClampsBeforeWriting() {
        BillingConfigService.BillingConfig saved = service.upsert(1L, 99, 99, false);

        assertThat(saved.invoiceLeadDays()).isEqualTo(BillingConfigService.MAX_LEAD_DAYS);
        assertThat(saved.checkoutGraceDays()).isEqualTo(BillingConfigService.MAX_GRACE_DAYS);
        verify(jdbc).update(contains("INSERT INTO organization_billing_config"),
                eq(1L), eq(BillingConfigService.MAX_LEAD_DAYS), eq(BillingConfigService.MAX_GRACE_DAYS),
                eq(0), any(), any());
    }
}
