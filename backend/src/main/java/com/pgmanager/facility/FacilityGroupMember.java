package com.pgmanager.facility;

import com.pgmanager.common.entity.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDate;

@Getter
@Setter
@Entity
@Table(name = "facility_group_member")
public class FacilityGroupMember extends BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "facility_group_member_id")
    private Long facilityGroupMemberId;

    @Column(name = "parent_facility_id", nullable = false)
    private Long parentFacilityId;

    @Column(name = "child_facility_id", nullable = false)
    private Long childFacilityId;

    @Column(name = "from_date", nullable = false)
    private LocalDate fromDate;

    @Column(name = "thru_date")
    private LocalDate thruDate;
}
