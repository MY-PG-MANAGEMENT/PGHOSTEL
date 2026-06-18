package com.pgmanager.facility;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface FacilityRepository extends JpaRepository<Facility, Long> {
    List<Facility> findByOrganizationIdAndFacilityTypeIdAndStatus(Long organizationId, String facilityTypeId, String status);

    Optional<Facility> findByFacilityIdAndOrganizationId(Long facilityId, Long organizationId);

    long countByOrganizationIdAndFacilityTypeIdAndStatus(Long organizationId, String facilityTypeId, String status);
}
