package com.pgmanager.complaint;

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
@Table(name = "complaint")
public class Complaint extends BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "complaint_id")
    private Long complaintId;

    @Column(name = "organization_id", nullable = false)
    private Long organizationId;

    /** The tenant (party) who raised the complaint. */
    @Column(name = "party_id", nullable = false)
    private Long partyId;

    /** Resolved from the tenant's active bed at creation time; may be null. */
    @Column(name = "property_facility_id")
    private Long propertyFacilityId;

    @Column(nullable = false)
    private String category;

    @Column(nullable = false)
    private String title;

    @Column(nullable = false)
    private String description;

    @Column(nullable = false)
    private String priority = ComplaintStatus.PRIORITY_MEDIUM;

    @Column(nullable = false)
    private String status = ComplaintStatus.OPEN;
}
