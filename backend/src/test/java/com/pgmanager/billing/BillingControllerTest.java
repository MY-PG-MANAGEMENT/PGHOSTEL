package com.pgmanager.billing;

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

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        CurrentUser currentUser = mock(CurrentUser.class);
        lenient().when(currentUser.organizationId()).thenReturn(1L);
        NotificationService notificationService = mock(NotificationService.class);
        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();
        mvc = MockMvcBuilders.standaloneSetup(new BillingController(currentUser, jdbc, notificationService))
                .setControllerAdvice(new GlobalExceptionHandler())
                .setValidator(validator)
                .build();
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
}
