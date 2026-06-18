package com.pgmanager.payment.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.time.LocalDate;

public final class PaymentDtos {
    private PaymentDtos() {
    }

    public record PaymentCreateRequest(
            Long rentId,
            @NotNull Long partyId,
            @NotNull BigDecimal amount,
            @NotBlank String paymentMode,
            LocalDate paymentDate,
            String referenceNumber,
            String notes
    ) {
    }

    public record PaymentResponse(
            Long paymentId,
            Long rentId,
            Long partyId,
            BigDecimal amount,
            String paymentMode,
            LocalDate paymentDate,
            String referenceNumber,
            String notes
    ) {
    }
}
