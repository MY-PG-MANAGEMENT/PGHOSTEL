package com.pgmanager.facility;

import com.pgmanager.common.cache.CacheConfig;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.dto.FacilityDtos.*;
import com.pgmanager.occupancy.FacilityParty;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.occupancy.OccupancyRole;
import com.pgmanager.party.Person;
import com.pgmanager.party.PersonRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class FacilityService {
    private final FacilityRepository facilityRepository;
    private final FacilityGroupMemberRepository groupMemberRepository;
    private final FacilityPartyRepository facilityPartyRepository;
    private final PersonRepository personRepository;

    // A structural change (new/updated/deleted node, or a re-parenting link) invalidates
    // the tree and every occupancy read model derived from it. Evict wholesale — cheap
    // (these writes are rare) and immune to key-mismatch bugs.
    @CacheEvict(cacheNames = {CacheConfig.FACILITY_TREE, CacheConfig.ROOM_SUMMARY,
            CacheConfig.PROPERTY_STATS, CacheConfig.VACANT_BEDS, CacheConfig.TEMP_STAYS},
            allEntries = true)
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

    @CacheEvict(cacheNames = {CacheConfig.FACILITY_TREE, CacheConfig.ROOM_SUMMARY,
            CacheConfig.PROPERTY_STATS, CacheConfig.VACANT_BEDS, CacheConfig.TEMP_STAYS},
            allEntries = true)
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

    @CacheEvict(cacheNames = {CacheConfig.FACILITY_TREE, CacheConfig.ROOM_SUMMARY,
            CacheConfig.PROPERTY_STATS, CacheConfig.VACANT_BEDS, CacheConfig.TEMP_STAYS},
            allEntries = true)
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

    // Structure (rarely changes); evicted by the structural writers above + BulkUpload.
    @Cacheable(cacheNames = CacheConfig.FACILITY_TREE, key = "#organizationId")
    @Transactional(readOnly = true)
    public FacilityTreeResponse tree(Long organizationId) {
        Facility org = facilityRepository.findById(organizationId)
                .orElseThrow(() -> new NotFoundException("Organization not found"));

        // Preload the whole subtree by level (one group-member query per depth, ~5 for
        // ORG→PROPERTY→FLOOR→ROOM→BED) instead of two queries per node, then assemble
        // in memory. A visited guard makes the BFS safe against any stray cyclic link.
        Map<Long, List<Long>> childrenByParent = new HashMap<>();
        Set<Long> allChildIds = new HashSet<>();
        Set<Long> visited = new HashSet<>();
        visited.add(org.getFacilityId());
        List<Long> frontier = List.of(org.getFacilityId());
        while (!frontier.isEmpty()) {
            List<Long> next = new ArrayList<>();
            for (FacilityGroupMember m : groupMemberRepository.findByParentFacilityIdInAndThruDateIsNull(frontier)) {
                childrenByParent.computeIfAbsent(m.getParentFacilityId(), k -> new ArrayList<>())
                        .add(m.getChildFacilityId());
                if (visited.add(m.getChildFacilityId())) {
                    next.add(m.getChildFacilityId());
                    allChildIds.add(m.getChildFacilityId());
                }
            }
            frontier = next;
        }

        Map<Long, Facility> facilityMap = new HashMap<>();
        facilityMap.put(org.getFacilityId(), org);
        if (!allChildIds.isEmpty()) {
            facilityRepository.findAllById(allChildIds)
                    .forEach(f -> facilityMap.put(f.getFacilityId(), f));
        }
        return buildTree(org.getFacilityId(), facilityMap, childrenByParent);
    }

    @Transactional(readOnly = true)
    public List<FacilityResponse> children(Long organizationId, Long parentFacilityId) {
        Facility parent = facilityRepository.findById(parentFacilityId)
                .orElseThrow(() -> new NotFoundException("Parent facility not found"));
        if (!parent.getFacilityId().equals(organizationId) && !organizationId.equals(parent.getOrganizationId())) {
            throw new BadRequestException("Parent facility is outside current organization");
        }
        List<Long> childIds = groupMemberRepository.findByParentFacilityIdAndThruDateIsNull(parentFacilityId).stream()
                .map(FacilityGroupMember::getChildFacilityId).toList();
        Map<Long, Facility> byId = childIds.isEmpty() ? Map.of()
                : facilityRepository.findAllById(childIds).stream()
                        .collect(Collectors.toMap(Facility::getFacilityId, f -> f));
        return childIds.stream()
                .map(byId::get)
                .filter(Objects::nonNull)
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
        List<Long> bedIds = groupMemberRepository.findByParentFacilityIdAndThruDateIsNull(roomId).stream()
                .map(FacilityGroupMember::getChildFacilityId).toList();
        if (bedIds.isEmpty()) return List.of();

        Map<Long, Facility> bedMap = facilityRepository.findAllById(bedIds).stream()
                .collect(Collectors.toMap(Facility::getFacilityId, f -> f));

        // One query for all active occupancy rows (permanent + temporary) on these beds.
        List<FacilityParty> active = facilityPartyRepository
                .findByOrganizationIdAndFacilityIdInAndRoleTypeIdInAndThruDateIsNull(
                        organizationId, bedIds, List.of(OccupancyRole.OCCUPANT, OccupancyRole.TEMP_OCCUPANT));
        // Prefer a permanent occupant over a temporary stay when a bed has both.
        Map<Long, FacilityParty> occByBed = new HashMap<>();
        for (FacilityParty fp : active) {
            occByBed.merge(fp.getFacilityId(), fp,
                    (a, b) -> OccupancyRole.OCCUPANT.equals(a.getRoleTypeId()) ? a : b);
        }
        List<Long> occupantPartyIds = active.stream().map(FacilityParty::getPartyId).distinct().toList();
        Map<Long, Person> personMap = occupantPartyIds.isEmpty() ? Map.of()
                : personRepository.findAllById(occupantPartyIds).stream()
                        .collect(Collectors.toMap(Person::getPartyId, p -> p));

        return bedIds.stream()
                .map(bedMap::get)
                .filter(Objects::nonNull)
                .map(bed -> {
                    FacilityParty occ = occByBed.get(bed.getFacilityId());
                    // A temporary stay still shows the bed as occupied (distinctly coloured in the UI).
                    boolean temp = occ != null && OccupancyRole.TEMP_OCCUPANT.equals(occ.getRoleTypeId());
                    String occupantName = occ == null ? null
                            : Optional.ofNullable(personMap.get(occ.getPartyId()))
                                    .map(Person::getFullName).orElse(null);
                    Long occupantPartyId = occ != null ? occ.getPartyId() : null;
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

    // Reflects occupancy (occupied bed count) → evicted on occupancy writes (see
    // OccupancyService / TenantService.create / setExpectedCheckout) + structural writes.
    @Cacheable(cacheNames = CacheConfig.PROPERTY_STATS, key = "#organizationId + ':' + #propertyId")
    @Transactional(readOnly = true)
    public PropertyStatsResponse propertyStats(Long organizationId, Long propertyId) {
        Facility property = facilityRepository.findById(propertyId)
                .orElseThrow(() -> new NotFoundException("Property not found"));
        if (!organizationId.equals(property.getOrganizationId())) {
            throw new BadRequestException("Property not in current organization");
        }
        // Walk the tree one level at a time with batched IN queries (3 queries total,
        // independent of floor/room/bed count) instead of one query per node.
        List<Long> floorIds = childIdsOf(List.of(propertyId));
        List<Long> roomIds = childIdsOf(floorIds);
        List<Long> bedIds = childIdsOf(roomIds);
        int occupiedBeds = bedIds.isEmpty() ? 0
                : (int) facilityPartyRepository.countByOrganizationIdAndFacilityIdInAndRoleTypeIdAndThruDateIsNull(
                        organizationId, bedIds, OccupancyRole.OCCUPANT);
        return new PropertyStatsResponse(
                floorIds.size(), roomIds.size(), bedIds.size(),
                occupiedBeds, bedIds.size() - occupiedBeds, occupiedBeds);
    }

    /** Active child-facility ids for a set of parents, in one batched query (empty-safe). */
    private List<Long> childIdsOf(List<Long> parentIds) {
        if (parentIds.isEmpty()) return List.of();
        return groupMemberRepository.findByParentFacilityIdInAndThruDateIsNull(parentIds).stream()
                .map(FacilityGroupMember::getChildFacilityId).toList();
    }

    // Reflects occupancy → same eviction as propertyStats.
    @Cacheable(cacheNames = CacheConfig.ROOM_SUMMARY, key = "#organizationId + ':' + #propertyId")
    @Transactional(readOnly = true)
    public List<RoomSharingSummary> getRoomSummary(Long organizationId, Long propertyId) {
        Facility property = facilityRepository.findById(propertyId)
                .orElseThrow(() -> new NotFoundException("Property not found"));
        if (!organizationId.equals(property.getOrganizationId())) {
            throw new BadRequestException("Property not in current organization");
        }

        List<Long> floorIds = childIdsOf(List.of(propertyId));
        List<Long> roomIds = childIdsOf(floorIds);
        Map<String, int[]> summary = new LinkedHashMap<>();
        if (!roomIds.isEmpty()) {
            facilityRepository.findAllById(roomIds).stream()
                    .filter(f -> "ROOM".equals(f.getFacilityTypeId()))
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

    // Re-parenting/attaching a node changes the tree; no org param here, so evict wholesale.
    @CacheEvict(cacheNames = {CacheConfig.FACILITY_TREE, CacheConfig.ROOM_SUMMARY,
            CacheConfig.PROPERTY_STATS, CacheConfig.VACANT_BEDS, CacheConfig.TEMP_STAYS},
            allEntries = true)
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

    private FacilityTreeResponse buildTree(Long facilityId, Map<Long, Facility> facilityMap,
                                           Map<Long, List<Long>> childrenByParent) {
        Facility facility = facilityMap.get(facilityId);
        if (facility == null) return null;
        List<FacilityTreeResponse> children = childrenByParent.getOrDefault(facilityId, List.of()).stream()
                .map(childId -> buildTree(childId, facilityMap, childrenByParent))
                .filter(Objects::nonNull)
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
