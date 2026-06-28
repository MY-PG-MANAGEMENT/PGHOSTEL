package com.pgmanager.tenant.dto;

import jakarta.validation.constraints.*;

import java.math.BigDecimal;
import java.time.LocalDate;

public final class TenantDtos {
    private TenantDtos() {}

    public record TenantCreateRequest(
            @NotBlank @Size(min = 2, max = 120) String fullName,
            @NotBlank @Pattern(regexp = "^[0-9]{10}$", message = "must be a 10-digit number") String mobileNumber,
            @Email String email,
            @Pattern(regexp = "^(MALE|FEMALE|OTHER)?$", message = "must be MALE, FEMALE or OTHER") String gender,
            LocalDate dateOfBirth,
            @Pattern(regexp = "^([0-9]{12})?$", message = "must be a 12-digit number") String aadhaarNumber,
            String occupation,
            String permanentAddress,
            String emergencyContactName,
            @Pattern(regexp = "^([0-9]{10})?$", message = "must be a 10-digit number") String emergencyContactMobile,
            String emergencyContactRelation,
            String employerName,
            String designation,
            String workAddress,
            Long propertyId
    ) {}

    public record TenantUpdateRequest(
            @NotBlank @Size(min = 2, max = 120) String fullName,
            @NotBlank @Pattern(regexp = "^[0-9]{10}$", message = "must be a 10-digit number") String mobileNumber,
            @Email String email,
            @Pattern(regexp = "^(MALE|FEMALE|OTHER)?$", message = "must be MALE, FEMALE or OTHER") String gender,
            LocalDate dateOfBirth,
            @Pattern(regexp = "^([0-9]{12})?$", message = "must be a 12-digit number") String aadhaarNumber,
            String occupation,
            String permanentAddress,
            String emergencyContactName,
            @Pattern(regexp = "^([0-9]{10})?$", message = "must be a 10-digit number") String emergencyContactMobile,
            String emergencyContactRelation,
            String employerName,
            String designation,
            String workAddress
    ) {}

    public record TenantPatchRequest(
            String emergencyContactName,
            @Pattern(regexp = "^([0-9]{10})?$", message = "must be a 10-digit number") String emergencyContactMobile,
            String emergencyContactRelation,
            String employerName,
            String designation,
            String workAddress
    ) {}

    public record TenantResponse(
            Long tenantId,
            String fullName,
            String mobileNumber,
            String email,
            String gender,
            LocalDate dateOfBirth,
            String aadhaarNumber,
            String permanentAddress,
            String emergencyContactName,
            String emergencyContactMobile,
            String emergencyContactRelation,
            String employerName,
            String designation,
            String workAddress,
            String currentBedName,
            String currentRoomName,
            Long currentPropertyId,
            Long currentBedFacilityId,
            boolean hasActiveAdmission,
            LocalDate moveInDate,
            BigDecimal monthlyRent,
            BigDecimal securityDeposit,
            LocalDate expectedCheckoutDate,
            String currentSharingType,
            boolean inTemporaryStay,
            Long tempBedFacilityId,
            String tempBedName
    ) {}
}
