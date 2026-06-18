package com.pgmanager.onboarding;

import com.pgmanager.audit.AuditService;
import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityService;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.feature.FeatureMasterRepository;
import com.pgmanager.feature.OrganizationFeature;
import com.pgmanager.feature.OrganizationFeatureRepository;
import com.pgmanager.onboarding.dto.OnboardingDtos.OnboardingWizardRequest;
import com.pgmanager.onboarding.dto.OnboardingDtos.OnboardingWizardResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
public class OnboardingService {
    private final FacilityRepository facilityRepository;
    private final FacilityService facilityService;
    private final FeatureMasterRepository featureMasterRepository;
    private final OrganizationFeatureRepository organizationFeatureRepository;
    private final AuditService auditService;

    @Transactional
    public OnboardingWizardResponse run(Long organizationId, Long userLoginId, OnboardingWizardRequest request) {
        int floors = 0;
        int rooms = 0;
        int beds = 0;
        int propertyCount = request.multipleProperties() ? request.numberOfProperties() : 1;

        for (int p = 1; p <= propertyCount; p++) {
            Facility property = createFacility(organizationId, FacilityType.PROPERTY, "Property " + p, null, null);
            facilityService.link(organizationId, property.getFacilityId());

            for (int f = 1; f <= request.numberOfFloors(); f++) {
                Facility floor = createFacility(organizationId, FacilityType.FLOOR, "Floor " + f, null, null);
                facilityService.link(property.getFacilityId(), floor.getFacilityId());
                floors++;

                for (int r = 1; r <= request.numberOfRooms(); r++) {
                    Facility room = createFacility(organizationId, FacilityType.ROOM, "Room " + f + "-" + r, request.sharingType(), request.bedsPerRoom());
                    facilityService.link(floor.getFacilityId(), room.getFacilityId());
                    rooms++;

                    for (int b = 1; b <= request.bedsPerRoom(); b++) {
                        Facility bed = createFacility(organizationId, FacilityType.BED, "Bed " + f + "-" + r + "-" + b, request.sharingType(), 1);
                        facilityService.link(room.getFacilityId(), bed.getFacilityId());
                        beds++;
                    }
                }
            }
        }

        enableFeatures(organizationId, request.enabledFeatureCodes());
        auditService.log(organizationId, userLoginId, "ONBOARDING_COMPLETED", "FACILITY", organizationId, "Owner onboarding wizard completed");
        return new OnboardingWizardResponse(organizationId, propertyCount, floors, rooms, beds);
    }

    private Facility createFacility(Long organizationId, String type, String name, String sharingType, Integer capacity) {
        Facility facility = new Facility();
        facility.setOrganizationId(organizationId);
        facility.setFacilityTypeId(type);
        facility.setFacilityName(name);
        facility.setSharingType(sharingType);
        facility.setCapacity(capacity);
        return facilityRepository.save(facility);
    }

    private void enableFeatures(Long organizationId, List<String> featureCodes) {
        if (featureCodes == null || featureCodes.isEmpty()) {
            return;
        }
        featureCodes.forEach(code -> featureMasterRepository.findByFeatureCode(code).ifPresent(feature -> {
            if (organizationFeatureRepository.existsByOrganizationIdAndFeatureId(organizationId, feature.getFeatureId())) {
                return;
            }
            OrganizationFeature organizationFeature = new OrganizationFeature();
            organizationFeature.setOrganizationId(organizationId);
            organizationFeature.setFeatureId(feature.getFeatureId());
            organizationFeature.setEnabled(true);
            organizationFeatureRepository.save(organizationFeature);
        }));
    }
}
