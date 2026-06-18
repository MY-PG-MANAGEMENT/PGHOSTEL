package com.pgmanager.facility.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.util.List;

public final class FacilityDtos {
    private FacilityDtos() {
    }

    public record FacilityCreateRequest(
            @NotNull Long parentFacilityId,
            @NotBlank String facilityTypeId,
            @NotBlank String facilityName,
            String sharingType,
            Integer capacity
    ) {
    }

    public record FacilityUpdateRequest(
            @NotBlank String facilityName,
            String sharingType,
            Integer capacity,
            String status
    ) {
    }

    public record FacilityResponse(
            Long facilityId,
            Long organizationId,
            String facilityTypeId,
            String facilityName,
            String status,
            String sharingType,
            Integer capacity
    ) {
    }

    public record FacilityTreeResponse(
            Long facilityId,
            String facilityTypeId,
            String facilityName,
            String status,
            String sharingType,
            Integer capacity,
            List<FacilityTreeResponse> children
    ) {
    }
}
