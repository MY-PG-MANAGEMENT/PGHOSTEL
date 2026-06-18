package com.pgmanager.payment;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.payment.dto.PaymentDtos.PaymentCreateRequest;
import com.pgmanager.payment.dto.PaymentDtos.PaymentResponse;
import com.pgmanager.rent.Rent;
import com.pgmanager.rent.RentRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Service
@RequiredArgsConstructor
public class PaymentService {
    private final PaymentRepository paymentRepository;
    private final RentRepository rentRepository;
    private final AuditService auditService;

    @Transactional
    public PaymentResponse create(Long organizationId, Long userLoginId, PaymentCreateRequest request) {
        Rent rent = null;
        if (request.rentId() != null) {
            rent = rentRepository.findByRentIdAndOrganizationId(request.rentId(), organizationId)
                    .orElseThrow(() -> new NotFoundException("Rent not found"));
        }

        Payment payment = new Payment();
        payment.setOrganizationId(organizationId);
        payment.setRentId(request.rentId());
        payment.setPartyId(request.partyId());
        payment.setAmount(request.amount());
        payment.setPaymentMode(request.paymentMode());
        payment.setPaymentDate(request.paymentDate() == null ? LocalDate.now() : request.paymentDate());
        payment.setReferenceNumber(request.referenceNumber());
        payment.setNotes(request.notes());
        payment = paymentRepository.save(payment);

        if (rent != null) {
            rent.setPaidAmount(rent.getPaidAmount().add(request.amount()));
            BigDecimal pending = rent.totalDue().subtract(rent.getPaidAmount());
            rent.setStatus(pending.compareTo(BigDecimal.ZERO) <= 0 ? "PAID" : "PARTIAL");
        }

        auditService.log(organizationId, userLoginId, "PAYMENT_RECORDED", "PAYMENT", payment.getPaymentId(), "Payment recorded");
        return toResponse(payment);
    }

    @Transactional(readOnly = true)
    public List<PaymentResponse> list(Long organizationId) {
        return paymentRepository.findByOrganizationIdOrderByPaymentDateDesc(organizationId).stream()
                .map(this::toResponse)
                .toList();
    }

    private PaymentResponse toResponse(Payment payment) {
        return new PaymentResponse(
                payment.getPaymentId(),
                payment.getRentId(),
                payment.getPartyId(),
                payment.getAmount(),
                payment.getPaymentMode(),
                payment.getPaymentDate(),
                payment.getReferenceNumber(),
                payment.getNotes()
        );
    }
}
