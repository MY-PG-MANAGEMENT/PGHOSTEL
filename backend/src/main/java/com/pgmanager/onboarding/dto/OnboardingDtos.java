package com.pgmanager.onboarding.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;

import java.util.List;

public final class OnboardingDtos {
    private OnboardingDtos() {
    }

    public record OnboardingWizardRequest(
            boolean multipleProperties,
            @Min(1) int numberOfProperties,
            @Min(1) int numberOfFloors,
            @Min(1) int numberOfRooms,
            @Min(1) int bedsPerRoom,
            @NotBlank String sharingType,
            List<String> enabledFeatureCodes
    ) {
    }

    public record OnboardingWizardResponse(Long organizationId, int propertiesCreated, int floorsCreated, int roomsCreated, int bedsCreated) {
    }
}
