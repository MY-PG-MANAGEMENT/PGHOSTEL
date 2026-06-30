package com.pgmanager.facility;

import com.pgmanager.common.entity.BaseEntity;
import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDate;

@Getter
@Setter
@Entity
@Table(name = "facility")
public class Facility extends BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "facility_id")
    private Long facilityId;

    @Column(name = "facility_code", unique = true)
    private String facilityCode;

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

    @Column(name = "description", columnDefinition = "VARCHAR(1000)")
    private String description;

    @Column(name = "room_number")
    private String roomNumber;

    @Column(name = "floor_number")
    private Integer floorNumber;

    @Column(name = "monthly_rent", precision = 12, scale = 2)
    private BigDecimal monthlyRent;

    @Column(name = "security_deposit", precision = 12, scale = 2)
    private BigDecimal securityDeposit;

    @Column(name = "size_sq_ft", precision = 10, scale = 2)
    private BigDecimal sizeSqFt;

    @Column(name = "available_from")
    private LocalDate availableFrom;

    @Version
    @Column(nullable = false)
    private Long version = 0L;

    @Column(name = "photos_count")
    private Integer photosCount = 0;

    @Column(name = "is_ac", nullable = false)
    private boolean isAc = false;
}
