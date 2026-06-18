package com.pgmanager.rent.dto;

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
            @NotNull BigDecimal monthlyRent,
            BigDecimal deposit,
            BigDecimal advance,
            BigDecimal discount,
            BigDecimal penalty
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
