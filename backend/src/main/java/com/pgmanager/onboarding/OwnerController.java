package com.pgmanager.onboarding;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.dashboard.DashboardResponse;
import com.pgmanager.dashboard.DashboardService;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityService;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.facility.dto.FacilityDtos.FacilityResponse;
import com.pgmanager.onboarding.dto.OnboardingDtos.OnboardingWizardRequest;
import com.pgmanager.onboarding.dto.OnboardingDtos.OnboardingWizardResponse;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.security.PropertyAccessGuard;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/owner")
@RequiredArgsConstructor
public class OwnerController {
    private final OnboardingService onboardingService;
    private final DashboardService dashboardService;
    private final FacilityRepository facilityRepository;
    private final FacilityService facilityService;
    private final CurrentUser currentUser;
    private final PropertyAccessGuard propertyAccessGuard;

    @PostMapping("/onboarding-wizard")
    ApiResponse<OnboardingWizardResponse> onboarding(@Valid @RequestBody OnboardingWizardRequest request) {
        return ApiResponse.ok("Onboarding completed", onboardingService.run(currentUser.organizationId(), currentUser.userLoginId(), request));
    }

    @GetMapping("/dashboard")
    ApiResponse<DashboardResponse> dashboard() {
        return ApiResponse.ok(dashboardService.ownerDashboard(currentUser.organizationId()));
    }

    /**
     * The property list behind the Properties screen and the app's property switcher.
     *
     * <p>This is the list a property-scoped login must not see in full. Scoping
     * {@code FacilityService.tree()} was not enough: the app reads its property list from here, so a
     * manager was still shown — and could tap — properties they had no access to, getting a 403 on
     * every panel instead of simply not seeing them.
     */
    @GetMapping("/properties")
    ApiResponse<List<FacilityResponse>> properties() {
        var scope = propertyAccessGuard.scope();
        return ApiResponse.ok(facilityRepository.findByOrganizationIdAndFacilityTypeIdAndStatus(
                currentUser.organizationId(),
                FacilityType.PROPERTY,
                "ACTIVE"
        ).stream()
                .filter(property -> scope.unrestricted() || scope.allows(property.getFacilityId()))
                .map(facilityService::toResponse)
                .toList());
    }
}
