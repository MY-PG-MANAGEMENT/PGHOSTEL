package com.pgmanager.feature;

import com.pgmanager.common.entity.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
@Entity
@Table(name = "organization_feature")
public class OrganizationFeature extends BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "organization_feature_id")
    private Long organizationFeatureId;

    @Column(name = "organization_id", nullable = false)
    private Long organizationId;

    @Column(name = "feature_id", nullable = false)
    private Long featureId;

    @Column(nullable = false)
    private boolean enabled;
}
