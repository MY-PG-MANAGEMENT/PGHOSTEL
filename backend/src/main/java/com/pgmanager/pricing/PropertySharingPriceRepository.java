package com.pgmanager.pricing;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface PropertySharingPriceRepository extends JpaRepository<PropertySharingPrice, Long> {

    List<PropertySharingPrice> findByOrganizationIdAndPropertyFacilityId(Long orgId, Long propertyId);

    Optional<PropertySharingPrice> findByOrganizationIdAndPropertyFacilityIdAndSharingType(
            Long orgId, Long propertyId, String sharingType);
}
