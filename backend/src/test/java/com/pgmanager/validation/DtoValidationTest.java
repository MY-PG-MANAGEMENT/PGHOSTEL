package com.pgmanager.validation;

import com.pgmanager.auth.dto.AuthDtos.RegisterOwnerRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedAssignRequest;
import com.pgmanager.payment.dto.PaymentDtos.PaymentCreateRequest;
import com.pgmanager.rent.dto.RentDtos.RentCreateRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantCreateRequest;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Pure Jakarta Bean Validation checks on request DTOs. Runs without a Spring
 * context or database, so it stays fast and does not require Testcontainers.
 */
class DtoValidationTest {

    private static ValidatorFactory factory;
    private static Validator validator;

    @BeforeAll
    static void setUp() {
        factory = Validation.buildDefaultValidatorFactory();
        validator = factory.getValidator();
    }

    @AfterAll
    static void tearDown() {
        factory.close();
    }

    @Test
    void paymentAcceptsPositiveAmount() {
        var req = new PaymentCreateRequest(null, 1L, new BigDecimal("100.00"), "CASH", null, null, null);
        assertThat(validator.validate(req)).isEmpty();
    }

    @Test
    void paymentRejectsZeroAmount() {
        var req = new PaymentCreateRequest(null, 1L, BigDecimal.ZERO, "CASH", null, null, null);
        assertThat(validator.validate(req)).isNotEmpty();
    }

    @Test
    void paymentRejectsNegativeAmount() {
        var req = new PaymentCreateRequest(null, 1L, new BigDecimal("-5"), "CASH", null, null, null);
        assertThat(validator.validate(req)).isNotEmpty();
    }

    @Test
    void paymentRejectsBlankMode() {
        var req = new PaymentCreateRequest(null, 1L, new BigDecimal("100"), "  ", null, null, null);
        assertThat(validator.validate(req)).isNotEmpty();
    }

    @Test
    void paymentRejectsMissingParty() {
        var req = new PaymentCreateRequest(null, null, new BigDecimal("100"), "CASH", null, null, null);
        assertThat(validator.validate(req)).isNotEmpty();
    }

    @Test
    void rentAcceptsValidCharges() {
        var req = new RentCreateRequest(1L, 2L, LocalDate.now(), new BigDecimal("5000"),
                new BigDecimal("5000"), BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO);
        assertThat(validator.validate(req)).isEmpty();
    }

    @Test
    void rentAllowsNullOptionalCharges() {
        var req = new RentCreateRequest(1L, 2L, LocalDate.now(), new BigDecimal("5000"),
                null, null, null, null);
        assertThat(validator.validate(req)).isEmpty();
    }

    @Test
    void rentRejectsNegativeDeposit() {
        var req = new RentCreateRequest(1L, 2L, LocalDate.now(), new BigDecimal("5000"),
                new BigDecimal("-1"), null, null, null);
        assertThat(validator.validate(req)).isNotEmpty();
    }

    @Test
    void rentRejectsMissingMonthlyRent() {
        var req = new RentCreateRequest(1L, 2L, LocalDate.now(), null, null, null, null, null);
        assertThat(validator.validate(req)).isNotEmpty();
    }

    // --- Tenant ---

    private TenantCreateRequest tenant(String fullName, String mobile) {
        return new TenantCreateRequest(fullName, mobile, null, null, null, null, null, null,
                null, null, null, null, null, null, null);
    }

    @Test
    void tenantAcceptsMinimalValidBody() {
        assertThat(validator.validate(tenant("Asha Rao", "9876543210"))).isEmpty();
    }

    @Test
    void tenantRejectsBlankName() {
        assertThat(validator.validate(tenant("", "9876543210"))).isNotEmpty();
    }

    @Test
    void tenantRejectsShortName() {
        assertThat(validator.validate(tenant("A", "9876543210"))).isNotEmpty();
    }

    @Test
    void tenantRejectsBadMobile() {
        assertThat(validator.validate(tenant("Asha Rao", "12345"))).isNotEmpty();
    }

    @Test
    void tenantRejectsBadEmail() {
        var req = new TenantCreateRequest("Asha Rao", "9876543210", "not-an-email", null, null, null,
                null, null, null, null, null, null, null, null, null);
        assertThat(validator.validate(req)).isNotEmpty();
    }

    @Test
    void tenantRejectsBadGender() {
        var req = new TenantCreateRequest("Asha Rao", "9876543210", null, "X", null, null,
                null, null, null, null, null, null, null, null, null);
        assertThat(validator.validate(req)).isNotEmpty();
    }

    // --- Owner registration ---

    @Test
    void registerOwnerAcceptsValidBody() {
        var req = new RegisterOwnerRequest("Asha Rao", "9876543210", "asha_rao", "secret123", "Asha PG");
        assertThat(validator.validate(req)).isEmpty();
    }

    @Test
    void registerOwnerRejectsShortPassword() {
        var req = new RegisterOwnerRequest("Asha Rao", "9876543210", "asha_rao", "short", "Asha PG");
        assertThat(validator.validate(req)).isNotEmpty();
    }

    @Test
    void registerOwnerRejectsIllegalUsername() {
        var req = new RegisterOwnerRequest("Asha Rao", "9876543210", "asha rao!", "secret123", "Asha PG");
        assertThat(validator.validate(req)).isNotEmpty();
    }

    // --- Bed assignment ---

    @Test
    void bedAssignAcceptsValidBody() {
        var req = new BedAssignRequest(1L, 2L, null, new BigDecimal("6000"), new BigDecimal("6000"), null);
        assertThat(validator.validate(req)).isEmpty();
    }

    @Test
    void bedAssignRejectsMissingPartyAndBed() {
        var req = new BedAssignRequest(null, null, null, null, null, null);
        assertThat(validator.validate(req)).isNotEmpty();
    }

    @Test
    void bedAssignRejectsNegativeRent() {
        var req = new BedAssignRequest(1L, 2L, null, new BigDecimal("-1"), null, null);
        assertThat(validator.validate(req)).isNotEmpty();
    }
}
