package com.pgmanager.rent;

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

@Getter
@Setter
@Entity
@Table(name = "rent")
public class Rent extends BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "rent_id")
    private Long rentId;

    @Column(name = "organization_id", nullable = false)
    private Long organizationId;

    @Column(name = "party_id", nullable = false)
    private Long partyId;

    @Column(name = "facility_id")
    private Long facilityId;

    @Column(name = "rent_month", nullable = false)
    private LocalDate rentMonth;

    @Column(name = "monthly_rent", nullable = false)
    private BigDecimal monthlyRent = BigDecimal.ZERO;

    @Column(nullable = false)
    private BigDecimal deposit = BigDecimal.ZERO;

    @Column(nullable = false)
    private BigDecimal advance = BigDecimal.ZERO;

    @Column(nullable = false)
    private BigDecimal discount = BigDecimal.ZERO;

    @Column(nullable = false)
    private BigDecimal penalty = BigDecimal.ZERO;

    @Column(name = "paid_amount", nullable = false)
    private BigDecimal paidAmount = BigDecimal.ZERO;

    @Column(nullable = false)
    private String status = "PENDING";

    public BigDecimal totalDue() {
        return monthlyRent.add(deposit).add(advance).add(penalty).subtract(discount);
    }
}
