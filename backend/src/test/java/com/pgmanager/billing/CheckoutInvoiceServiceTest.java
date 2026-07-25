package com.pgmanager.billing;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
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
 * The checkout drop must hard-delete (row + line items), never soft-cancel, and it must
 * only reach back as far as the org's grace window: an invoice due on the 26th is dropped
 * for a checkout on the 28th (grace 2) but survives a checkout on the 29th.
 */
class CheckoutInvoiceServiceTest {

    private JdbcTemplate jdbc;
    private CheckoutInvoiceService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        BillingConfigService config = mock(BillingConfigService.class);
        when(config.get(1L)).thenReturn(new BillingConfigService.BillingConfig(1, 2, true));
        service = new CheckoutInvoiceService(jdbc, config);
    }

    private void stubFound(boolean found) {
        Map<String, Object> row = new HashMap<>();
        row.put("invoice_id", 99L);
        row.put("invoice_number", "INV-1-2-202607");
        row.put("due_date", java.sql.Date.valueOf(LocalDate.of(2026, 7, 26)));
        row.put("total_amount", new BigDecimal("8000"));
        when(jdbc.queryForList(anyString(), any(Object[].class)))
                .thenReturn(found ? List.of(row) : List.of());
    }

    /** The SQL cut-off must be checkoutDate - graceDays, so checkout <= dueDate + grace matches. */
    @Test
    void looksBackExactlyTheGraceWindow() {
        stubFound(false);

        service.dropUnconsumedInvoices(1L, 10L, LocalDate.of(2026, 7, 28));

        ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).queryForList(anyString(), args.capture());
        // grace 2 → an invoice due on the 26th is still in range for a checkout on the 28th.
        assertThat(args.getValue()).containsExactly(1L, 10L, LocalDate.of(2026, 7, 26));
    }

    @Test
    void hardDeletesTheInvoiceAndItsItems() {
        stubFound(true);

        List<CheckoutInvoiceService.DroppedInvoice> dropped =
                service.dropUnconsumedInvoices(1L, 10L, LocalDate.of(2026, 7, 28));

        assertThat(dropped).hasSize(1);
        assertThat(dropped.getFirst().invoiceNumber()).isEqualTo("INV-1-2-202607");
        verify(jdbc).update("DELETE FROM invoice_item WHERE invoice_id=?", 99L);
        verify(jdbc).update("DELETE FROM invoice WHERE invoice_id=? AND organization_id=?", 99L, 1L);
        // Never a soft cancel — the invoice must leave no trace.
        verify(jdbc, never()).update(contains("CANCELLED"), any(Object[].class));
    }

    @Test
    void deletesNothingWhenNoInvoiceIsInTheWindow() {
        stubFound(false);

        assertThat(service.dropUnconsumedInvoices(1L, 10L, LocalDate.of(2026, 7, 29))).isEmpty();
        verify(jdbc, never()).update(anyString(), any(Object[].class));
        verify(jdbc, never()).update(anyString(), any(Object.class), any(Object.class));
    }

    @Test
    void previewNeitherLocksNorDeletes() {
        stubFound(true);

        assertThat(service.previewUnconsumedInvoices(1L, 10L, LocalDate.of(2026, 7, 28))).hasSize(1);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).queryForList(sql.capture(), any(Object[].class));
        assertThat(sql.getValue()).doesNotContain("FOR UPDATE");
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }
}
