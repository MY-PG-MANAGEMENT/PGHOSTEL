package com.pgmanager.integration;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.LocalDate;
import java.time.LocalDateTime;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end billing payment-collection tests against a real MySQL (Testcontainers
 * + Flyway). Seeds a billing account + invoice via JdbcTemplate for the registered
 * owner's party, then drives the real {@code POST /api/billing/payments} flow and
 * asserts the persisted allocation, status transition and idempotent replay.
 *
 * <p>Requires Docker; auto-skips where Docker is unavailable. Clone this for the
 * remaining DB-backed billing endpoints (refund, write-off, mark-paid, dashboard).
 */
@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest
@AutoConfigureMockMvc
class BillingIntegrationTest {

    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.0").withDatabaseName("pg_manager");

    @DynamicPropertySource
    static void datasourceProps(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
    }

    @Autowired MockMvc mvc;
    @Autowired JdbcTemplate jdbc;
    private final ObjectMapper json = new ObjectMapper();

    private record Owner(String token, long orgId, long partyId) {}

    private Owner registerOwner() throws Exception {
        long n = System.nanoTime();
        String username = "owner_" + Long.toUnsignedString(n);
        String mobile = "9" + String.format("%09d", Math.abs(n % 1_000_000_000L));
        String body = "{\"fullName\":\"Test Owner\",\"mobileNumber\":\"" + mobile + "\"," +
                "\"username\":\"" + username + "\",\"password\":\"secret123\",\"organizationName\":\"Test PG\"}";
        String resp = mvc.perform(post("/api/auth/register-owner")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        JsonNode data = json.readTree(resp).path("data");
        long partyId = jdbc.queryForObject("SELECT party_id FROM user_login WHERE username=?", Long.class, username);
        return new Owner(data.path("accessToken").asText(), data.path("organizationId").asLong(), partyId);
    }

    /** Seeds a PENDING invoice for the owner's own party and returns the invoice id. */
    private long seedInvoice(Owner owner, String total) {
        LocalDateTime now = LocalDateTime.now();
        LocalDate month = LocalDate.now().withDayOfMonth(1);
        jdbc.update("INSERT INTO billing_account(organization_id,party_id,created_at,updated_at) VALUES(?,?,?,?)",
                owner.orgId(), owner.partyId(), now, now);
        long baId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        String invNum = "INV-IT-" + System.nanoTime();
        jdbc.update("INSERT INTO invoice(organization_id,billing_account_id,invoice_number,invoice_month,issue_date,due_date," +
                        "total_amount,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
                owner.orgId(), baId, invNum, month, month, month, new java.math.BigDecimal(total), now, now);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    @Test
    void fullPaymentMarksInvoicePaidAndPersists() throws Exception {
        Owner owner = registerOwner();
        long invoiceId = seedInvoice(owner, "5000");
        String body = "{\"invoiceId\":" + invoiceId + ",\"amount\":5000,\"idempotencyKey\":\"it-key-1\"}";

        mvc.perform(post("/api/billing/payments").header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("PAID"));

        String status = jdbc.queryForObject("SELECT status FROM invoice WHERE invoice_id=?", String.class, invoiceId);
        java.math.BigDecimal paid = jdbc.queryForObject("SELECT paid_amount FROM invoice WHERE invoice_id=?",
                java.math.BigDecimal.class, invoiceId);
        org.assertj.core.api.Assertions.assertThat(status).isEqualTo("PAID");
        org.assertj.core.api.Assertions.assertThat(paid).isEqualByComparingTo("5000");
    }

    @Test
    void partialPaymentMarksInvoicePartial() throws Exception {
        Owner owner = registerOwner();
        long invoiceId = seedInvoice(owner, "5000");
        String body = "{\"invoiceId\":" + invoiceId + ",\"amount\":2000,\"idempotencyKey\":\"it-key-2\"}";

        mvc.perform(post("/api/billing/payments").header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("PARTIAL"));
    }

    @Test
    void overpaymentIsRejected() throws Exception {
        Owner owner = registerOwner();
        long invoiceId = seedInvoice(owner, "5000");
        String body = "{\"invoiceId\":" + invoiceId + ",\"amount\":6000,\"idempotencyKey\":\"it-key-3\"}";

        mvc.perform(post("/api/billing/payments").header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest());
    }

    @Test
    void duplicateIdempotencyKeyDoesNotDoublePay() throws Exception {
        Owner owner = registerOwner();
        long invoiceId = seedInvoice(owner, "5000");
        String body = "{\"invoiceId\":" + invoiceId + ",\"amount\":5000,\"idempotencyKey\":\"it-key-dup\"}";

        mvc.perform(post("/api/billing/payments").header("Authorization", "Bearer " + owner.token())
                .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isOk());
        // Replay with the same key must not create a second payment.
        mvc.perform(post("/api/billing/payments").header("Authorization", "Bearer " + owner.token())
                .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isOk());

        Long payments = jdbc.queryForObject(
                "SELECT COUNT(*) FROM payment WHERE organization_id=? AND idempotency_key=?",
                Long.class, owner.orgId(), "it-key-dup");
        org.assertj.core.api.Assertions.assertThat(payments).isEqualTo(1L);
    }
}
