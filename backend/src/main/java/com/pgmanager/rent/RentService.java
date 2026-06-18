package com.pgmanager.rent;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.occupancy.OccupancyRole;
import com.pgmanager.rent.dto.RentDtos.RentCreateRequest;
import com.pgmanager.rent.dto.RentDtos.RentResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;

@Service
@RequiredArgsConstructor
public class RentService {
    private final RentRepository rentRepository;
    private final FacilityPartyRepository facilityPartyRepository;
    private final AuditService auditService;

    @Transactional
    public RentResponse create(Long organizationId, Long userLoginId, RentCreateRequest request) {
        facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                request.partyId(),
                OccupancyRole.TENANT
        ).orElseThrow(() -> new NotFoundException("Tenant not found in current organization"));

        Rent rent = new Rent();
        rent.setOrganizationId(organizationId);
        rent.setPartyId(request.partyId());
        rent.setFacilityId(request.facilityId());
        rent.setRentMonth(request.rentMonth());
        rent.setMonthlyRent(orZero(request.monthlyRent()));
        rent.setDeposit(orZero(request.deposit()));
        rent.setAdvance(orZero(request.advance()));
        rent.setDiscount(orZero(request.discount()));
        rent.setPenalty(orZero(request.penalty()));
        rent = rentRepository.save(rent);
        auditService.log(organizationId, userLoginId, "RENT_CREATED", "RENT", rent.getRentId(), "Rent created");
        return toResponse(rent);
    }

    @Transactional(readOnly = true)
    public List<RentResponse> list(Long organizationId) {
        return rentRepository.findByOrganizationIdOrderByRentMonthDesc(organizationId).stream()
                .map(this::toResponse)
                .toList();
    }

    public RentResponse toResponse(Rent rent) {
        BigDecimal pending = rent.totalDue().subtract(rent.getPaidAmount());
        return new RentResponse(
                rent.getRentId(),
                rent.getPartyId(),
                rent.getFacilityId(),
                rent.getRentMonth(),
                rent.getMonthlyRent(),
                rent.getDeposit(),
                rent.getAdvance(),
                rent.getDiscount(),
                rent.getPenalty(),
                rent.getPaidAmount(),
                pending.max(BigDecimal.ZERO),
                rent.getStatus()
        );
    }

    private BigDecimal orZero(BigDecimal value) {
        return value == null ? BigDecimal.ZERO : value;
    }
}
