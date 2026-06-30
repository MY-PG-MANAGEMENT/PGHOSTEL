package com.pgmanager.facility;

import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.dto.FacilityDtos.*;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.occupancy.OccupancyRole;
import com.pgmanager.party.Person;
import com.pgmanager.party.PersonRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.*;

@Service
@RequiredArgsConstructor
public class FacilityService {
    private final FacilityRepository facilityRepository;
    private final FacilityGroupMemberRepository groupMemberRepository;
    private final FacilityPartyRepository facilityPartyRepository;
    private final PersonRepository personRepository;

    @Transactional
    public Facility createChild(Long organizationId, FacilityCreateRequest request) {
        Facility parent = facilityRepository.findById(request.parentFacilityId())
                .orElseThrow(() -> new NotFoundException("Parent facility not found"));
        if (!parent.getFacilityId().equals(organizationId) && !organizationId.equals(parent.getOrganizationId())) {
            throw new BadRequestException("Parent facility is outside current organization");
        }

        Facility facility = new Facility();
        facility.setOrganizationId(organizationId);
        facility.setFacilityTypeId(request.facilityTypeId());
        facility.setFacilityName(request.facilityName());
        facility.setDescription(request.description());
        facility.setRoomNumber(request.roomNumber());
        facility.setFloorNumber(request.floorNumber());
        facility.setSharingType(request.sharingType());
        facility.setCapacity(request.capacity());
        facility.setMonthlyRent(request.monthlyRent());
        facility.setSecurityDeposit(request.securityDeposit());
        facility.setSizeSqFt(request.sizeSqFt());
        facility.setAc(Boolean.TRUE.equals(request.isAc()));
        facility = facilityRepository.save(facility);
        facility.setFacilityCode(generateCode(facility));
        facility = facilityRepository.save(facility);

        link(parent.getFacilityId(), facility.getFacilityId());
        return facility;
    }

    @Transactional
    public Facility update(Long organizationId, Long facilityId, FacilityUpdateRequest request) {
        Facility facility = facilityRepository.findByFacilityIdAndOrganizationId(facilityId, organizationId)
                .orElseThrow(() -> new NotFoundException("Facility not found"));
        facility.setFacilityName(request.facilityName());
        facility.setDescription(request.description());
        facility.setRoomNumber(request.roomNumber());
        facility.setFloorNumber(request.floorNumber());
        facility.setSharingType(request.sharingType());
        facility.setCapacity(request.capacity());
        facility.setMonthlyRent(request.monthlyRent());
        facility.setSecurityDeposit(request.securityDeposit());
        facility.setSizeSqFt(request.sizeSqFt());
        facility.setAvailableFrom(request.availableFrom());
        if (request.isAc() != null) {
            facility.setAc(request.isAc());
        }
        if (request.status() != null && !request.status().isBlank()) {
            facility.setStatus(request.status());
        }
        return facility;
    }

    @Transactional
    public void deleteBed(Long organizationId, Long facilityId) {
        Facility facility = facilityRepository.findByFacilityIdAndOrganizationId(facilityId, organizationId)
                .orElseThrow(() -> new NotFoundException("Bed not found"));
        if (!"BED".equals(facility.getFacilityTypeId())) {
            throw new BadRequestException("Only beds can be deleted");
        }
        boolean isOccupied = facilityPartyRepository
                .findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                        organizationId, facilityId, OccupancyRole.OCCUPANT)
                .isPresent();
        if (isOccupied) {
            throw new BadRequestException("Cannot delete an occupied bed");
        }
        facilityPartyRepository.deleteAllByFacilityId(facilityId);
        groupMemberRepository.deleteAllByChildFacilityId(facilityId);
        facilityRepository.delete(facility);
    }

    @Transactional(readOnly = true)
    public FacilityTreeResponse tree(Long organizationId) {
        Facility org = facilityRepository.findById(organizationId)
                .orElseThrow(() -> new NotFoundException("Organization not found"));
        return toTree(org);
    }

    @Transactional(readOnly = true)
    public List<FacilityResponse> children(Long organizationId, Long parentFacilityId) {
        Facility parent = facilityRepository.findById(parentFacilityId)
                .orElseThrow(() -> new NotFoundException("Parent facility not found"));
        if (!parent.getFacilityId().equals(organizationId) && !organizationId.equals(parent.getOrganizationId())) {
            throw new BadRequestException("Parent facility is outside current organization");
        }
        return groupMemberRepository.findByParentFacilityIdAndThruDateIsNull(parentFacilityId).stream()
                .map(member -> facilityRepository.findById(member.getChildFacilityId()).orElseThrow())
                .map(this::toResponse)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<FacilityResponse> bedsWithOccupancy(Long organizationId, Long roomId) {
        Facility room = facilityRepository.findById(roomId)
                .orElseThrow(() -> new NotFoundException("Room not found"));
        if (!organizationId.equals(room.getOrganizationId())) {
            throw new BadRequestException("Room not in current organization");
        }
        return groupMemberRepository.findByParentFacilityIdAndThruDateIsNull(roomId).stream()
                .map(member -> facilityRepository.findById(member.getChildFacilityId()).orElseThrow())
                .map(bed -> {
                    var occupancy = facilityPartyRepository
                            .findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                                    organizationId, bed.getFacilityId(), OccupancyRole.OCCUPANT);
                    // No permanent occupant? Surface a temporary stay so the bed still
                    // shows as occupied (distinctly coloured in the UI).
                    boolean temporaryStay = false;
                    if (occupancy.isEmpty()) {
                        occupancy = facilityPartyRepository
                                .findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                                        organizationId, bed.getFacilityId(), OccupancyRole.TEMP_OCCUPANT);
                        temporaryStay = occupancy.isPresent();
                    }
                    String occupantName = occupancy
                            .flatMap(fp -> personRepository.findById(fp.getPartyId()))
                            .map(Person::getFullName)
                            .orElse(null);
                    Long occupantPartyId = occupancy.map(fp -> fp.getPartyId()).orElse(null);
                    final boolean temp = temporaryStay;
                    return new FacilityResponse(
                            bed.getFacilityId(),
                            bed.getFacilityCode(),
                            bed.getFacilityTypeId(),
                            bed.getFacilityName(),
                            bed.getDescription(),
                            bed.getRoomNumber(),
                            bed.getFloorNumber(),
                            bed.getStatus(),
                            bed.getSharingType(),
                            bed.getCapacity(),
                            bed.getMonthlyRent(),
                            bed.getSecurityDeposit(),
                            bed.getSizeSqFt(),
                            bed.getAvailableFrom(),
                            bed.getPhotosCount(),
                            occupantName,
                            occupantPartyId,
                            temp,
                            false
                    );
                })
                .toList();
    }

    @Transactional(readOnly = true)
    public PropertyStatsResponse propertyStats(Long organizationId, Long propertyId) {
        Facility property = facilityRepository.findById(propertyId)
                .orElseThrow(() -> new NotFoundException("Property not found"));
        if (!organizationId.equals(property.getOrganizationId())) {
            throw new BadRequestException("Property not in current organization");
        }
        List<Long> floorIds = groupMemberRepository
                .findByParentFacilityIdAndThruDateIsNull(propertyId).stream()
                .map(FacilityGroupMember::getChildFacilityId).toList();
        List<Long> roomIds = floorIds.stream()
                .flatMap(fId -> groupMemberRepository
                        .findByParentFacilityIdAndThruDateIsNull(fId).stream())
                .map(FacilityGroupMember::getChildFacilityId).toList();
        List<Long> bedIds = roomIds.stream()
                .flatMap(rId -> groupMemberRepository
                        .findByParentFacilityIdAndThruDateIsNull(rId).stream())
                .map(FacilityGroupMember::getChildFacilityId).toList();
        int occupiedBeds = (int) bedIds.stream()
                .filter(bedId -> facilityPartyRepository
                        .findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(
                                organizationId, bedId, OccupancyRole.OCCUPANT)
                        .isPresent())
                .count();
        return new PropertyStatsResponse(
                floorIds.size(), roomIds.size(), bedIds.size(),
                occupiedBeds, bedIds.size() - occupiedBeds, occupiedBeds);
    }

    @Transactional(readOnly = true)
    public List<RoomSharingSummary> getRoomSummary(Long organizationId, Long propertyId) {
        Facility property = facilityRepository.findById(propertyId)
                .orElseThrow(() -> new NotFoundException("Property not found"));
        if (!organizationId.equals(property.getOrganizationId())) {
            throw new BadRequestException("Property not in current organization");
        }

        List<Long> floorIds = groupMemberRepository
                .findByParentFacilityIdAndThruDateIsNull(propertyId).stream()
                .map(FacilityGroupMember::getChildFacilityId)
                .toList();

        Map<String, int[]> summary = new LinkedHashMap<>();
        for (Long floorId : floorIds) {
            groupMemberRepository.findByParentFacilityIdAndThruDateIsNull(floorId).stream()
                    .map(m -> facilityRepository.findById(m.getChildFacilityId()).orElse(null))
                    .filter(f -> f != null && "ROOM".equals(f.getFacilityTypeId()))
                    .forEach(room -> {
                        String key = room.getSharingType() != null ? room.getSharingType() : "OTHER";
                        summary.computeIfAbsent(key, k -> new int[]{0, 0});
                        summary.get(key)[0]++;
                        summary.get(key)[1] += room.getCapacity() != null ? room.getCapacity() : 0;
                    });
        }
        return summary.entrySet().stream()
                .sorted(Map.Entry.comparingByKey())
                .map(e -> new RoomSharingSummary(e.getKey(), e.getValue()[0], e.getValue()[1]))
                .toList();
    }

    public void link(Long parentFacilityId, Long childFacilityId) {
        FacilityGroupMember member = new FacilityGroupMember();
        member.setParentFacilityId(parentFacilityId);
        member.setChildFacilityId(childFacilityId);
        member.setFromDate(LocalDate.now());
        groupMemberRepository.save(member);
    }

    public FacilityResponse toResponse(Facility facility) {
        return new FacilityResponse(
                facility.getFacilityId(),
                facility.getFacilityCode(),
                facility.getFacilityTypeId(),
                facility.getFacilityName(),
                facility.getDescription(),
                facility.getRoomNumber(),
                facility.getFloorNumber(),
                facility.getStatus(),
                facility.getSharingType(),
                facility.getCapacity(),
                facility.getMonthlyRent(),
                facility.getSecurityDeposit(),
                facility.getSizeSqFt(),
                facility.getAvailableFrom(),
                facility.getPhotosCount(),
                null,
                null,
                false,
                facility.isAc()
        );
    }

    private FacilityTreeResponse toTree(Facility facility) {
        List<FacilityTreeResponse> children = groupMemberRepository
                .findByParentFacilityIdAndThruDateIsNull(facility.getFacilityId()).stream()
                .map(member -> facilityRepository.findById(member.getChildFacilityId()).orElseThrow())
                .map(this::toTree)
                .toList();
        return new FacilityTreeResponse(
                facility.getFacilityId(),
                facility.getFacilityCode(),
                facility.getFacilityTypeId(),
                facility.getFacilityName(),
                facility.getDescription(),
                facility.getRoomNumber(),
                facility.getFloorNumber(),
                facility.getStatus(),
                facility.getSharingType(),
                facility.getCapacity(),
                facility.getMonthlyRent(),
                facility.getSecurityDeposit(),
                children
        );
    }

    private static String generateCode(Facility facility) {
        String prefix = switch (facility.getFacilityTypeId()) {
            case "ORGANIZATION" -> "ORG";
            case "PROPERTY"     -> "PROP";
            case "FLOOR"        -> "FLR";
            case "ROOM"         -> "ROOM";
            case "BED"          -> "BED";
            default             -> "FAC";
        };
        return prefix + "_" + facility.getFacilityId();
    }
}
