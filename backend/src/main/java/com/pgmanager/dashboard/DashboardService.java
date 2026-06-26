package com.pgmanager.dashboard;

import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.occupancy.OccupancyRole;
import com.pgmanager.payment.PaymentRepository;
import com.pgmanager.rent.RentRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;

@Service
@RequiredArgsConstructor
public class DashboardService {
    private final FacilityRepository facilityRepository;
    private final FacilityPartyRepository facilityPartyRepository;
    private final RentRepository rentRepository;
    private final PaymentRepository paymentRepository;

    public DashboardResponse ownerDashboard(Long organizationId) {
        long totalBeds = facilityRepository.countByOrganizationIdAndFacilityTypeIdAndStatus(organizationId, FacilityType.BED, "ACTIVE");
        long occupiedBeds = facilityPartyRepository.countByOrganizationIdAndRoleTypeIdAndThruDateIsNull(organizationId, OccupancyRole.OCCUPANT);
        long totalTenants = facilityPartyRepository.countByOrganizationIdAndRoleTypeIdAndThruDateIsNull(organizationId, OccupancyRole.TENANT);
        return new DashboardResponse(
                totalBeds,
                occupiedBeds,
                Math.max(totalBeds - occupiedBeds, 0),
                totalTenants,
                pendingRent(organizationId),
                revenue(organizationId)
        );
    }

    private BigDecimal pendingRent(Long organizationId) {
        return rentRepository.findByOrganizationId(organizationId).stream()
                .map(rent -> rent.totalDue().subtract(rent.getPaidAmount()).max(BigDecimal.ZERO))
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    private BigDecimal revenue(Long organizationId) {
        BigDecimal total = paymentRepository.sumAmountByOrganizationId(organizationId);
        return total == null ? BigDecimal.ZERO : total;
    }
}
