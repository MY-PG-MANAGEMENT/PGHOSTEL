package com.pgmanager.pricing.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.util.List;

public final class SharingPriceDtos {
    private SharingPriceDtos() {}

    public record SharingPriceUpsertRequest(@NotNull List<SharingPriceItem> prices) {}

    public record SharingPriceItem(
            @NotBlank String sharingType,
            @NotNull @DecimalMin("0") BigDecimal monthlyRent,
            @DecimalMin("0") BigDecimal securityDeposit,
            @DecimalMin("0") BigDecimal acCharges
    ) {}

    public record SharingPriceResponse(
            String sharingType,
            BigDecimal monthlyRent,
            BigDecimal securityDeposit,
            BigDecimal acCharges
    ) {}
}
