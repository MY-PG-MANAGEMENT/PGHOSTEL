package com.pgmanager.tenant.dto;

import jakarta.validation.constraints.*;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

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
            boolean hasVehicle,
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
            String workAddress,
            boolean hasVehicle
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
            boolean hasVehicle,
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
            String tempBedName,
            // true when the temp stay is a Temporary Bed allocation (no expected
            // checkout) — the only case that may be shifted to a permanent bed.
            // false for a day-wise Temporary Stay (which ends via checkout).
            boolean tempIsAllocation,
            // Temporary-stay dates (null when not in a temporary stay): check-in
            // and the planned checkout used by the day-wise Temporary Stay card.
            LocalDate tempFromDate,
            LocalDate tempExpectedCheckoutDate,
            // true when this response came from restoring an archived tenant rather than
            // creating a new one — the Add Tenant form uses it to tell the owner their
            // history was brought back instead of a fresh record being made.
            boolean restoredFromArchive
    ) {}

    /** Bulk "delete" (archive) selection from the Inactive tenant list. */
    public record TenantArchiveRequest(
            @NotEmpty(message = "select at least one tenant") List<@NotNull Long> partyIds
    ) {}
}
