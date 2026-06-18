package com.pgmanager.feature;

import org.springframework.data.jpa.repository.JpaRepository;

public interface OrganizationFeatureRepository extends JpaRepository<OrganizationFeature, Long> {
    boolean existsByOrganizationIdAndFeatureId(Long organizationId, Long featureId);
}
