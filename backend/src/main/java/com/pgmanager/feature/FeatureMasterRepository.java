package com.pgmanager.feature;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface FeatureMasterRepository extends JpaRepository<FeatureMaster, Long> {
    Optional<FeatureMaster> findByFeatureCode(String featureCode);
}
