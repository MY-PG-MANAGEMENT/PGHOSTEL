package com.pgmanager.billing;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.GlobalExceptionHandler;
import com.pgmanager.notification.NotificationService;
import com.pgmanager.security.CurrentUser;
import org.junit.jupiter.api.BeforeEach;
import com.pgmanager.security.PropertyAccessGuard;
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
                        invoiceGenerationService, billingConfigService, auditService, passThroughGuard()))
                .setControllerAdvice(new GlobalExceptionHandler())
                .setValidator(validator)
                .build();
    }

    /** The single-row lookup both delete and restore start from. */
    private void invoiceRow(Map<String, Object> row) {
        when(jdbc.queryForList(anyString(), any(Object.class), any(Object.class)))
                .thenReturn(row == null ? List.of() : List.of(row));
    }

    /**
     * Stubs both {@code queryForList} calls {@code collectPayment} makes, discriminated
     * by SQL: the idempotency replay lookup (stubbed to "no prior payment") and the
     * invoice row.
     *
     * <p>They must be told apart. Both take two bind parameters, so a single
     * {@code anyString()} stub matches either and would hand the invoice row to the
     * replay check — making every payment look like a duplicate and returning
     * "Payment already recorded" instead of collecting anything.
     *
     * @param row the invoice, or {@code null} for a not-found invoice
     */
    private void collectStubs(Map<String, Object> row) {
        when(jdbc.queryForList(contains("FROM payment"), any(Object.class), any(Object.class)))
                .thenReturn(List.of());
        when(jdbc.queryForList(contains("FROM invoice"), any(Object.class), any(Object.class)))
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
        collectStubs(null);

        mvc.perform(post("/api/billing/payments").contentType(MediaType.APPLICATION_JSON).content(body("5000")))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.success").value(false));
    }

    @Test
    void collectRejectsAmountExceedingBalance() throws Exception {
        collectStubs(invoice("5000", "0"));

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
        collectStubs(invoice("5000", "0"));
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        // The payment id comes back from RETURNING on the INSERT itself.
        when(jdbc.queryForObject(contains("INSERT INTO payment"), eq(Long.class), any(Object[].class))).thenReturn(500L);

        mvc.perform(post("/api/billing/payments").contentType(MediaType.APPLICATION_JSON).content(body("5000")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("PAID"))
                .andExpect(jsonPath("$.data.paymentId").value(500));
    }

    @Test
    void collectPartialPaymentMarksInvoicePartial() throws Exception {
        collectStubs(invoice("5000", "0"));
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForObject(contains("INSERT INTO payment"), eq(Long.class), any(Object[].class))).thenReturn(501L);

        mvc.perform(post("/api/billing/payments").contentType(MediaType.APPLICATION_JSON).content(body("2000")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("PARTIAL"));
    }

    /**
     * A retried payment returns the original receipt instead of an error.
     *
     * <p>Regression test. The replay lookup used to sit *after* the exceeds-balance
     * guard, so retrying a payment that had settled the invoice in full saw balance = 0
     * and came back 400 "Payment exceeds invoice balance" — the opposite of what an
     * idempotency key is for. It escaped notice because the only coverage was
     * {@code BillingIntegrationTest}, which needs Docker and auto-skips locally, so this
     * assertion is deliberately here in the unit tests where it always runs.
     */
    @Test
    void replayedIdempotencyKeyReturnsTheOriginalPaymentInsteadOfExceedingBalance() throws Exception {
        // The invoice is already fully paid, so the balance guard would reject any amount.
        when(jdbc.queryForList(contains("FROM invoice"), any(Object.class), any(Object.class)))
                .thenReturn(List.of(invoice("5000", "5000")));
        when(jdbc.queryForList(contains("FROM payment"), any(Object.class), any(Object.class)))
                .thenReturn(List.of(Map.of("payment_id", 500L, "amount", new BigDecimal("5000"), "status", "RECEIVED")));

        mvc.perform(post("/api/billing/payments").contentType(MediaType.APPLICATION_JSON).content(body("5000")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Payment already recorded"))
                .andExpect(jsonPath("$.data.payment_id").value(500));

        // No second payment row, and no invoice re-statement.
        verify(jdbc, never()).queryForObject(contains("INSERT INTO payment"), eq(Long.class), any(Object[].class));
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

    /**
     * Pass-through guard: these tests exercise owner behaviour, and an owner is unrestricted, so
     * the guard must return the propertyId it was handed. A bare mock would return null and
     * silently turn every scoped request into an org-wide one, quietly changing what is asserted.
     */
    private static PropertyAccessGuard passThroughGuard() {
        PropertyAccessGuard guard = mock(PropertyAccessGuard.class);
        lenient().when(guard.resolvePropertyId(any())).thenAnswer(inv -> inv.getArgument(0));
        lenient().when(guard.unrestricted()).thenReturn(true);
        return guard;
    }
}
