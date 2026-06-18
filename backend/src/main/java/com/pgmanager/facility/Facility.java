package com.pgmanager.facility;


import lombok.Getter;
import lombok.Setter;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import lombok.Builder;
import javax.annotation.processing.Generated;

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
@Table(name = "facility")
public class Facility extends BaseEntity {
 
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "facility_id")
    private Long facilityId;

    @Column(name = "organization_id")
    private Long organizationId;

    @Column(name = "facility_type_id", nullable = false)
    private String facilityTypeId;

    @Column(name = "facility_name", nullable = false)
    private String facilityName;

    @Column(nullable = false)
    private String status = "ACTIVE";

    @Column(name = "sharing_type")
    private String sharingType;

    private Integer capacity;
}
