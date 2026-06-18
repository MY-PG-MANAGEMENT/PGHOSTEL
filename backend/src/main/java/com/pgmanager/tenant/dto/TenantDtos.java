package com.pgmanager.tenant.dto;

import jakarta.validation.constraints.NotBlank;

import java.time.LocalDate;

public final class TenantDtos {
    private TenantDtos() {
    }

    public record TenantCreateRequest(
            @NotBlank String fullName,
            @NotBlank String mobileNumber,
            String gender,
            LocalDate dateOfBirth,
            String aadhaarNumber,
            String occupation,
            String companyName,
            String guardianName,
            String guardianMobileNumber,
            String address
    ) {
    }

    public record TenantUpdateRequest(
            @NotBlank String fullName,
            @NotBlank String mobileNumber,
            String gender,
            LocalDate dateOfBirth,
            String aadhaarNumber,
            String occupation,
            String companyName,
            String guardianName,
            String guardianMobileNumber,
            String address
    ) {
    }

    public record TenantResponse(
            Long partyId,
            String fullName,
            String mobileNumber,
            String gender,
            LocalDate dateOfBirth,
            String aadhaarNumber,
            String occupation,
            String companyName,
            String guardianName,
            String guardianMobileNumber,
            String address
    ) {
    }
}
