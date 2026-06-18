package com.pgmanager.occupancy;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedAssignRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedTransferRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.CheckoutRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.OccupancyResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;

@Service
@RequiredArgsConstructor
public class OccupancyService {
    private final FacilityPartyRepository facilityPartyRepository;
    private final FacilityRepository facilityRepository;
    private final AuditService auditService;

    @Transactional
    public OccupancyResponse assign(Long organizationId, Long userLoginId, BedAssignRequest request) {
        LocalDate fromDate = request.fromDate() == null ? LocalDate.now() : request.fromDate();
        validateTenant(organizationId, request.partyId());
        validateBed(organizationId, request.bedFacilityId());
        facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                request.partyId(),
                OccupancyRole.OCCUPANT
        ).ifPresent(active -> {
            throw new BadRequestException("Tenant already has an active bed");
        });
        facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                request.bedFacilityId(),
                OccupancyRole.OCCUPANT
        ).ifPresent(active -> {
            throw new BadRequestException("Bed is already occupied");
        });

        FacilityParty occupancy = new FacilityParty();
        occupancy.setOrganizationId(organizationId);
        occupancy.setFacilityId(request.bedFacilityId());
        occupancy.setPartyId(request.partyId());
        occupancy.setRoleTypeId(OccupancyRole.OCCUPANT);
        occupancy.setFromDate(fromDate);
        occupancy = facilityPartyRepository.save(occupancy);
        auditService.log(organizationId, userLoginId, "BED_ASSIGNED", "FACILITY_PARTY", occupancy.getFacilityPartyId(), "Bed assigned");
        return toResponse(occupancy);
    }

    @Transactional
    public OccupancyResponse transfer(Long organizationId, Long userLoginId, BedTransferRequest request) {
        LocalDate transferDate = request.transferDate() == null ? LocalDate.now() : request.transferDate();
        validateBed(organizationId, request.newBedFacilityId());
        FacilityParty active = facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                request.partyId(),
                OccupancyRole.OCCUPANT
        ).orElseThrow(() -> new NotFoundException("Active occupancy not found"));
        facilityPartyRepository.findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                request.newBedFacilityId(),
                OccupancyRole.OCCUPANT
        ).ifPresent(existing -> {
            throw new BadRequestException("New bed is already occupied");
        });
        active.setThruDate(transferDate.minusDays(1));

        FacilityParty next = new FacilityParty();
        next.setOrganizationId(organizationId);
        next.setFacilityId(request.newBedFacilityId());
        next.setPartyId(request.partyId());
        next.setRoleTypeId(OccupancyRole.OCCUPANT);
        next.setFromDate(transferDate);
        next = facilityPartyRepository.save(next);
        auditService.log(organizationId, userLoginId, "BED_TRANSFERRED", "FACILITY_PARTY", next.getFacilityPartyId(), "Bed transferred");
        return toResponse(next);
    }

    @Transactional
    public OccupancyResponse checkout(Long organizationId, Long userLoginId, CheckoutRequest request) {
        LocalDate checkoutDate = request.checkoutDate() == null ? LocalDate.now() : request.checkoutDate();
        FacilityParty active = facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                request.partyId(),
                OccupancyRole.OCCUPANT
        ).orElseThrow(() -> new NotFoundException("Active occupancy not found"));
        active.setThruDate(checkoutDate);
        auditService.log(organizationId, userLoginId, "CHECKOUT", "FACILITY_PARTY", active.getFacilityPartyId(), "Tenant checked out");
        return toResponse(active);
    }

    @Transactional(readOnly = true)
    public List<OccupancyResponse> history(Long organizationId, Long partyId) {
        return facilityPartyRepository.findByOrganizationIdAndPartyIdOrderByFromDateDesc(organizationId, partyId).stream()
                .map(this::toResponse)
                .toList();
    }

    private void validateTenant(Long organizationId, Long partyId) {
        facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                partyId,
                OccupancyRole.TENANT
        ).orElseThrow(() -> new NotFoundException("Tenant not found in current organization"));
    }

    private void validateBed(Long organizationId, Long bedFacilityId) {
        Facility bed = facilityRepository.findByFacilityIdAndOrganizationId(bedFacilityId, organizationId)
                .orElseThrow(() -> new NotFoundException("Bed not found"));
        if (!FacilityType.BED.equals(bed.getFacilityTypeId())) {
            throw new BadRequestException("Selected facility is not a bed");
        }
    }

    private OccupancyResponse toResponse(FacilityParty facilityParty) {
        return new OccupancyResponse(
                facilityParty.getFacilityPartyId(),
                facilityParty.getPartyId(),
                facilityParty.getFacilityId(),
                facilityParty.getRoleTypeId(),
                facilityParty.getFromDate(),
                facilityParty.getThruDate()
        );
    }
}
