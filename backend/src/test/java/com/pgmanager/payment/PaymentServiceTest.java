package com.pgmanager.payment;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.payment.dto.PaymentDtos.PaymentCreateRequest;
import com.pgmanager.payment.dto.PaymentDtos.PaymentResponse;
import com.pgmanager.rent.Rent;
import com.pgmanager.rent.RentRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/**
 * Critical-path unit tests for payment recording and rent settlement math.
 */
@ExtendWith(MockitoExtension.class)
class PaymentServiceTest {

    private static final long ORG = 1L;
    private static final long USER = 7L;

    @Mock PaymentRepository paymentRepository;
    @Mock RentRepository rentRepository;
    @Mock AuditService auditService;

    @InjectMocks PaymentService service;

    private void stubPaymentSave() {
        when(paymentRepository.save(any(Payment.class))).thenAnswer(inv -> {
            Payment p = inv.getArgument(0);
            p.setPaymentId(500L);
            return p;
        });
    }

    private Rent rent(String monthlyRent) {
        Rent r = new Rent();
        r.setRentId(9L);
        r.setOrganizationId(ORG);
        r.setMonthlyRent(new BigDecimal(monthlyRent));
        r.setPaidAmount(BigDecimal.ZERO);
        return r;
    }

    @Test
    void createWithoutRent_recordsPayment() {
        stubPaymentSave();
        var req = new PaymentCreateRequest(null, 10L, new BigDecimal("1500"), "CASH", null, null, null);

        PaymentResponse res = service.create(ORG, USER, req);

        assertThat(res.amount()).isEqualByComparingTo("1500");
        assertThat(res.partyId()).isEqualTo(10L);
    }

    @Test
    void createWithRent_fullPaymentMarksRentPaid() {
        stubPaymentSave();
        Rent rent = rent("5000");
        when(rentRepository.findByRentIdAndOrganizationId(9L, ORG)).thenReturn(Optional.of(rent));
        var req = new PaymentCreateRequest(9L, 10L, new BigDecimal("5000"), "CASH", null, null, null);

        service.create(ORG, USER, req);

        assertThat(rent.getPaidAmount()).isEqualByComparingTo("5000");
        assertThat(rent.getStatus()).isEqualTo("PAID");
    }

    @Test
    void createWithRent_partialPaymentMarksRentPartial() {
        stubPaymentSave();
        Rent rent = rent("5000");
        when(rentRepository.findByRentIdAndOrganizationId(9L, ORG)).thenReturn(Optional.of(rent));
        var req = new PaymentCreateRequest(9L, 10L, new BigDecimal("2000"), "CASH", null, null, null);

        service.create(ORG, USER, req);

        assertThat(rent.getPaidAmount()).isEqualByComparingTo("2000");
        assertThat(rent.getStatus()).isEqualTo("PARTIAL");
    }

    @Test
    void createRejectsUnknownRent() {
        when(rentRepository.findByRentIdAndOrganizationId(9L, ORG)).thenReturn(Optional.empty());
        var req = new PaymentCreateRequest(9L, 10L, new BigDecimal("2000"), "CASH", null, null, null);

        assertThatThrownBy(() -> service.create(ORG, USER, req))
                .isInstanceOf(NotFoundException.class)
                .hasMessageContaining("Rent not found");
    }
}
