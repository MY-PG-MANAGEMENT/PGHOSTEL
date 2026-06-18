package com.pgmanager.occupancy;

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
@Table(name = "facility_party")
public class FacilityParty extends BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "facility_party_id")
    private Long facilityPartyId;

    @Column(name = "organization_id", nullable = false)
    private Long organizationId;

    @Column(name = "facility_id", nullable = false)
    private Long facilityId;

    @Column(name = "party_id", nullable = false)
    private Long partyId;

    @Column(name = "role_type_id", nullable = false)
    private String roleTypeId;

    @Column(name = "from_date", nullable = false)
    private LocalDate fromDate;

    @Column(name = "thru_date")
    private LocalDate thruDate;
}
