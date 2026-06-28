package com.pgmanager.payment.dto;

import jakarta.validation.constraints.DecimalMin;
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
            @NotNull @DecimalMin(value = "0.01", message = "amount must be greater than zero") BigDecimal amount,
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
