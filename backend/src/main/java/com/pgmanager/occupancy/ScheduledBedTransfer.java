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

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * A sharing-type bed transfer that takes effect at a future billing-cycle boundary.
 * Created when a tenant moves to a bed of a different sharing type; applied on
 * {@link #effectiveDate} by {@code OccupancyService.applyDueTransfers}.
 */
@Getter
@Setter
@Entity
@Table(name = "scheduled_bed_transfer")
public class ScheduledBedTransfer extends BaseEntity {
    public static final String PENDING = "PENDING";
    public static final String APPLIED = "APPLIED";
    public static final String CANCELLED = "CANCELLED";
    public static final String FAILED = "FAILED";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "scheduled_bed_transfer_id")
    private Long scheduledBedTransferId;

    @Column(name = "organization_id", nullable = false)
    private Long organizationId;

    @Column(name = "party_id", nullable = false)
    private Long partyId;

    @Column(name = "from_bed_facility_id")
    private Long fromBedFacilityId;

    @Column(name = "to_bed_facility_id", nullable = false)
    private Long toBedFacilityId;

    @Column(name = "effective_date", nullable = false)
    private LocalDate effectiveDate;

    @Column(name = "new_monthly_rent", precision = 10, scale = 2)
    private BigDecimal newMonthlyRent;

    @Column(name = "new_security_deposit", precision = 10, scale = 2)
    private BigDecimal newSecurityDeposit;

    @Column(name = "status", nullable = false)
    private String status = PENDING;

    @Column(name = "note")
    private String note;
}
