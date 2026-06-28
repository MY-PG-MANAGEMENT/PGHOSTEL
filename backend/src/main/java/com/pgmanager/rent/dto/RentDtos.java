package com.pgmanager.rent.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.time.LocalDate;

public final class RentDtos {
    private RentDtos() {
    }

    public record RentCreateRequest(
            @NotNull Long partyId,
            Long facilityId,
            @NotNull LocalDate rentMonth,
            @NotNull @DecimalMin(value = "0", message = "monthlyRent cannot be negative") BigDecimal monthlyRent,
            @DecimalMin(value = "0", message = "deposit cannot be negative") BigDecimal deposit,
            @DecimalMin(value = "0", message = "advance cannot be negative") BigDecimal advance,
            @DecimalMin(value = "0", message = "discount cannot be negative") BigDecimal discount,
            @DecimalMin(value = "0", message = "penalty cannot be negative") BigDecimal penalty
    ) {
    }

    public record RentResponse(
            Long rentId,
            Long partyId,
            Long facilityId,
            LocalDate rentMonth,
            BigDecimal monthlyRent,
            BigDecimal deposit,
            BigDecimal advance,
            BigDecimal discount,
            BigDecimal penalty,
            BigDecimal paidAmount,
            BigDecimal pendingAmount,
            String status
    ) {
    }
}
