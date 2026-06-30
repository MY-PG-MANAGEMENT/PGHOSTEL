package com.pgmanager.facility.dto;

import jakarta.validation.constraints.*;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public final class FacilityDtos {
    private FacilityDtos() {}

    public record FacilityCreateRequest(
            @NotNull Long parentFacilityId,
            @NotBlank @Pattern(regexp = "^(PROPERTY|FLOOR|ROOM|BED)$", message = "must be PROPERTY, FLOOR, ROOM or BED")
            String facilityTypeId,
            @NotBlank @Size(max = 120) String facilityName,
            String description,
            String roomNumber,
            Integer floorNumber,
            @Pattern(regexp = "^[1-6]?$", message = "must be a number between 1 and 6")
            String sharingType,
            @Min(1) Integer capacity,
            @DecimalMin("0") BigDecimal monthlyRent,
            @DecimalMin("0") BigDecimal securityDeposit,
            @DecimalMin("0") BigDecimal sizeSqFt,
            Boolean isAc
    ) {}

    public record FacilityUpdateRequest(
            @NotBlank @Size(max = 120) String facilityName,
            String description,
            String roomNumber,
            Integer floorNumber,
            @Pattern(regexp = "^[1-6]?$", message = "must be a number between 1 and 6")
            String sharingType,
            @Min(1) Integer capacity,
            @DecimalMin("0") BigDecimal monthlyRent,
            @DecimalMin("0") BigDecimal securityDeposit,
            @DecimalMin("0") BigDecimal sizeSqFt,
            LocalDate availableFrom,
            String status,
            Boolean isAc
    ) {}

    public record PropertyStatsResponse(
            int totalFloors,
            int totalRooms,
            int totalBeds,
            int occupiedBeds,
            int vacantBeds,
            int totalTenants
    ) {}

    public record FacilityResponse(
            Long facilityId,
            String facilityCode,
            String facilityTypeId,
            String facilityName,
            String description,
            String roomNumber,
            Integer floorNumber,
            String status,
            String sharingType,
            Integer capacity,
            BigDecimal monthlyRent,
            BigDecimal securityDeposit,
            BigDecimal sizeSqFt,
            LocalDate availableFrom,
            Integer photosCount,
            String occupantName,
            Long occupantPartyId,
            boolean temporaryStay,
            boolean isAc
    ) {}

    public record FacilityTreeResponse(
            Long facilityId,
            String facilityCode,
            String facilityTypeId,
            String facilityName,
            String description,
            String roomNumber,
            Integer floorNumber,
            String status,
            String sharingType,
            Integer capacity,
            BigDecimal monthlyRent,
            BigDecimal securityDeposit,
            List<FacilityTreeResponse> children
    ) {}

    public record RoomSharingSummary(
            String sharingType,
            int roomCount,
            int bedCount
    ) {}
}
