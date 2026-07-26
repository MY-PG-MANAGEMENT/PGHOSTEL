package com.pgmanager.billing;

import com.pgmanager.audit.AuditService;
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

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Money-correctness tests for billing payment collection. The JdbcTemplate is
 * mocked so the allocation math (PAID vs PARTIAL, exceeds-balance, not-found)
 * is exercised without a database.
 */
class BillingControllerTest {

    private MockMvc mvc;
    private JdbcTemplate jdbc;
    private AuditService auditService;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        CurrentUser currentUser = mock(CurrentUser.class);
        lenient().when(currentUser.organizationId()).thenReturn(1L);
        NotificationService notificationService = mock(NotificationService.class);
        InvoiceGenerationService invoiceGenerationService = mock(InvoiceGenerationService.class);
        BillingConfigService billingConfigService = mock(BillingConfigService.class);
        auditService = mock(AuditService.class);
        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();
        mvc = MockMvcBuilders.standaloneSetup(new BillingController(currentUser, jdbc, notificationService,
                        invoiceGenerationService, billingConfigService, auditService))
                .setControllerAdvice(new GlobalExceptionHandler())
                .setValidator(validator)
                .build();
    }

    /** The single-row lookup both delete and restore start from. */
    private void invoiceRow(Map<String, Object> row) {
        when(jdbc.queryForList(anyString(), any(Object.class), any(Object.class)))
                .thenReturn(row == null ? List.of() : List.of(row));
    }

    private Map<String, Object> invoice(String total, String paid) {
        return Map.of(
                "invoice_id", 99L,
                "billing_account_id", 2L,
                "total_amount", new BigDecimal(total),
                "paid_amount", new BigDecimal(paid),
                "party_id", 10L);
    }

    private String body(String amount) {
        return "{\"invoiceId\":99,\"amount\":" + amount + ",\"idempotencyKey\":\"key-1\"}";
    }

    @Test
    void collectRejectsUnknownInvoice() throws Exception {
        when(jdbc.queryForList(anyString(), any(Object.class), any(Object.class))).thenReturn(List.of());

        mvc.perform(post("/api/billing/payments").contentType(MediaType.APPLICATION_JSON).content(body("5000")))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.success").value(false));
    }

    @Test
    void collectRejectsAmountExceedingBalance() throws Exception {
        when(jdbc.queryForList(anyString(), any(Object.class), any(Object.class))).thenReturn(List.of(invoice("5000", "0")));

        mvc.perform(post("/api/billing/payments").contentType(MediaType.APPLICATION_JSON).content(body("6000")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Payment exceeds invoice balance"));
    }

    @Test
    void collectRejectsMissingIdempotencyKey() throws Exception {
        mvc.perform(post("/api/billing/payments").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"invoiceId\":99,\"amount\":5000}"))
                .andExpect(status().isBadRequest());
        verify(jdbc, never()).queryForList(anyString(), any(Object.class), any(Object.class));
    }

    @Test
    void collectRejectsZeroAmount() throws Exception {
        mvc.perform(post("/api/billing/payments").contentType(MediaType.APPLICATION_JSON).content(body("0")))
                .andExpect(status().isBadRequest());
        verify(jdbc, never()).queryForList(anyString(), any(Object.class), any(Object.class));
    }

    @Test
    void collectFullPaymentMarksInvoicePaid() throws Exception {
        when(jdbc.queryForList(anyString(), any(Object.class), any(Object.class))).thenReturn(List.of(invoice("5000", "0")));
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForObject(eq("SELECT LAST_INSERT_ID()"), eq(Long.class))).thenReturn(500L);

        mvc.perform(post("/api/billing/payments").contentType(MediaType.APPLICATION_JSON).content(body("5000")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("PAID"))
                .andExpect(jsonPath("$.data.paymentId").value(500));
    }

    @Test
    void collectPartialPaymentMarksInvoicePartial() throws Exception {
        when(jdbc.queryForList(anyString(), any(Object.class), any(Object.class))).thenReturn(List.of(invoice("5000", "0")));
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForObject(eq("SELECT LAST_INSERT_ID()"), eq(Long.class))).thenReturn(501L);

        mvc.perform(post("/api/billing/payments").contentType(MediaType.APPLICATION_JSON).content(body("2000")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("PARTIAL"));
    }

    // ── Delete (soft-cancel) is pending-only, and restore is its undo ──────────

    @Test
    void deleteCancelsAPendingInvoice() throws Exception {
        invoiceRow(Map.of("paid_amount", BigDecimal.ZERO, "status", "PENDING"));

        mvc.perform(delete("/api/billing/invoices/99"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Invoice deleted"));
        verify(jdbc).update(contains("status='CANCELLED'"), eq(99L), eq(1L));
        verify(auditService).log(eq(1L), any(), eq("INVOICE_CANCELLED"), eq("INVOICE"), eq(99L), anyString());
    }

    @Test
    void deleteRejectsAnOverdueInvoice() throws Exception {
        invoiceRow(Map.of("paid_amount", BigDecimal.ZERO, "status", "OVERDUE"));

        mvc.perform(delete("/api/billing/invoices/99"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.containsString("Only a pending invoice")));
        verify(jdbc, never()).update(contains("status='CANCELLED'"), any(Object[].class));
    }

    @Test
    void deleteRejectsAPartPaidInvoice() throws Exception {
        invoiceRow(Map.of("paid_amount", new BigDecimal("500"), "status", "PARTIAL"));

        mvc.perform(delete("/api/billing/invoices/99"))
                .andExpect(status().isBadRequest());
        verify(jdbc, never()).update(contains("status='CANCELLED'"), any(Object[].class));
    }

    @Test
    void deleteIsIdempotentOnAnAlreadyCancelledInvoice() throws Exception {
        invoiceRow(Map.of("paid_amount", BigDecimal.ZERO, "status", "CANCELLED"));

        mvc.perform(delete("/api/billing/invoices/99"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Invoice already cancelled"));
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }

    @Test
    void restoreReturnsACancelledInvoiceToPending() throws Exception {
        invoiceRow(Map.of("status", "CANCELLED"));

        mvc.perform(post("/api/billing/invoices/99/restore"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("PENDING"));
        verify(jdbc).update(contains("status='PENDING'"), eq(99L), eq(1L));
        verify(auditService).log(eq(1L), any(), eq("INVOICE_RESTORED"), eq("INVOICE"), eq(99L), anyString());
    }

    @Test
    void restoreRejectsAPaidInvoice() throws Exception {
        invoiceRow(Map.of("status", "PAID"));

        mvc.perform(post("/api/billing/invoices/99/restore"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.containsString("Only a deleted invoice")));
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }

    @Test
    void restoreOnAnActiveInvoiceIsANoOp() throws Exception {
        invoiceRow(Map.of("status", "PENDING"));

        mvc.perform(post("/api/billing/invoices/99/restore"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Invoice already active"));
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }

    @Test
    void restoreRejectsAnUnknownInvoice() throws Exception {
        invoiceRow(null);

        mvc.perform(post("/api/billing/invoices/99/restore"))
                .andExpect(status().isNotFound());
    }
}
