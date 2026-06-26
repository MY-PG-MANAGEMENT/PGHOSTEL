package com.pgmanager.tenant;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityGroupMemberRepository;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.occupancy.FacilityParty;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.occupancy.OccupancyRole;
import com.pgmanager.party.Party;
import com.pgmanager.party.PartyRepository;
import com.pgmanager.party.PartyType;
import com.pgmanager.party.Person;
import com.pgmanager.party.PersonRepository;
import com.pgmanager.tenant.dto.TenantDtos.TenantCreateRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantPatchRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantResponse;
import com.pgmanager.tenant.dto.TenantDtos.TenantUpdateRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class TenantService {
    private final PartyRepository partyRepository;
    private final PersonRepository personRepository;
    private final FacilityPartyRepository facilityPartyRepository;
    private final FacilityRepository facilityRepository;
    private final FacilityGroupMemberRepository facilityGroupMemberRepository;
    private final AuditService auditService;

    @Transactional
    public TenantResponse create(Long organizationId, Long userLoginId, TenantCreateRequest request) {
        Party party = new Party();
        party.setPartyTypeId(PartyType.PERSON);
        party = partyRepository.save(party);

        Person person = new Person();
        person.setPartyId(party.getPartyId());
        applyFields(person, request);
        personRepository.save(person);

        FacilityParty orgMembership = new FacilityParty();
        orgMembership.setOrganizationId(organizationId);
        orgMembership.setFacilityId(organizationId);
        orgMembership.setPartyId(party.getPartyId());
        orgMembership.setRoleTypeId(OccupancyRole.TENANT);
        orgMembership.setFromDate(LocalDate.now());
        facilityPartyRepository.save(orgMembership);

        if (request.propertyId() != null) {
            Facility property = facilityRepository.findById(request.propertyId())
                    .orElseThrow(() -> new com.pgmanager.common.exception.BadRequestException("Property not found"));
            if (!organizationId.equals(property.getOrganizationId())) {
                throw new com.pgmanager.common.exception.BadRequestException("Property not in current organization");
            }
            FacilityParty propertyMembership = new FacilityParty();
            propertyMembership.setOrganizationId(organizationId);
            propertyMembership.setFacilityId(request.propertyId());
            propertyMembership.setPartyId(party.getPartyId());
            propertyMembership.setRoleTypeId(OccupancyRole.TENANT);
            propertyMembership.setFromDate(LocalDate.now());
            facilityPartyRepository.save(propertyMembership);
        }

        auditService.log(organizationId, userLoginId, "TENANT_CREATED", "PARTY", party.getPartyId(), "Tenant created");
        return toResponse(person, null, null, false, null, null, null, null);
    }

    @Transactional(readOnly = true)
    public List<TenantResponse> list(Long organizationId) {
        // Query only org-level TENANT rows (facilityId = organizationId) so that
        // property-scoped TENANT rows don't produce duplicate entries.
        List<FacilityParty> tenantRows = facilityPartyRepository
                .findTenantsAtFacility(organizationId, organizationId, OccupancyRole.TENANT);
        if (tenantRows.isEmpty()) return List.of();

        List<Long> partyIds = tenantRows.stream().map(FacilityParty::getPartyId).toList();

        // Batch-load all required data in 5 queries instead of 4 per tenant
        Map<Long, Person> personMap = personRepository.findAllById(partyIds).stream()
                .collect(Collectors.toMap(Person::getPartyId, p -> p));

        Map<Long, FacilityParty> occupantMap = facilityPartyRepository
                .findActiveOccupantsByPartyIds(organizationId, partyIds, OccupancyRole.OCCUPANT).stream()
                .collect(Collectors.toMap(FacilityParty::getPartyId, fp -> fp));

        List<Long> bedIds = occupantMap.values().stream()
                .map(FacilityParty::getFacilityId).distinct().toList();

        Map<Long, Facility> bedMap = bedIds.isEmpty() ? Map.of()
                : facilityRepository.findAllById(bedIds).stream()
                        .collect(Collectors.toMap(Facility::getFacilityId, f -> f));

        Map<Long, Long> bedToRoomId = bedIds.isEmpty() ? Map.of()
                : facilityGroupMemberRepository.findByChildFacilityIdInAndThruDateIsNull(bedIds).stream()
                        .collect(Collectors.toMap(
                                fgm -> fgm.getChildFacilityId(), fgm -> fgm.getParentFacilityId(), (a, b) -> a));

        List<Long> roomIds = bedToRoomId.values().stream().distinct().toList();
        Map<Long, Facility> roomMap = roomIds.isEmpty() ? Map.of()
                : facilityRepository.findAllById(roomIds).stream()
                        .collect(Collectors.toMap(Facility::getFacilityId, f -> f));

        return tenantRows.stream()
                .map(fp -> {
                    Person person = personMap.get(fp.getPartyId());
                    if (person == null) return null;
                    FacilityParty occupant = occupantMap.get(fp.getPartyId());
                    String bedName = null, roomName = null;
                    boolean hasAdmission = false;
                    LocalDate moveInDate = null;
                    BigDecimal monthlyRent = null, securityDeposit = null;
                    LocalDate expectedCheckoutDate = null;
                    if (occupant != null) {
                        hasAdmission = true;
                        Long bedId = occupant.getFacilityId();
                        moveInDate = occupant.getFromDate();
                        monthlyRent = occupant.getMonthlyRent();
                        securityDeposit = occupant.getSecurityDeposit();
                        expectedCheckoutDate = occupant.getExpectedCheckoutDate();
                        Facility bed = bedMap.get(bedId);
                        bedName = bed != null ? bed.getFacilityName() : null;
                        Long roomId = bedToRoomId.get(bedId);
                        Facility room = roomId != null ? roomMap.get(roomId) : null;
                        roomName = room != null ? room.getFacilityName() : null;
                    }
                    return toResponse(person, bedName, roomName, hasAdmission, moveInDate, monthlyRent, securityDeposit, expectedCheckoutDate);
                })
                .filter(r -> r != null)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<TenantResponse> listByProperty(Long organizationId, Long propertyId) {
        // Primary: tenants with an explicit property-level TENANT row.
        // Union: tenants who have an active OCCUPANT row for a bed in this property
        // (covers tenants created globally and assigned via the bed-assign flow).
        java.util.Set<Long> seenPartyIds = new java.util.HashSet<>();
        java.util.List<FacilityParty> rows = new java.util.ArrayList<>(
                facilityPartyRepository.findTenantsAtFacility(organizationId, propertyId, OccupancyRole.TENANT));
        // Also include tenants whose org-level row exists but no property-level row was written —
        // this covers (a) globally-created tenants never assigned to this property's beds, and
        // (b) tenants who are now checked out (thruDate set), so the active-only query misses them.
        // We scan all historical OCCUPANT rows for the party and check if any belong to this property.
        rows.addAll(facilityPartyRepository.findTenantsAtFacility(organizationId, organizationId, OccupancyRole.TENANT)
                .stream()
                .filter(fp -> facilityPartyRepository
                        .findByOrganizationIdAndPartyIdAndRoleTypeId(
                                organizationId, fp.getPartyId(), OccupancyRole.OCCUPANT)
                        .stream()
                        .anyMatch(occ -> isInProperty(occ.getFacilityId(), propertyId)))
                .toList());
        return rows.stream()
                .filter(fp -> seenPartyIds.add(fp.getPartyId()))
                .map(fp -> {
                    Person person = personRepository.findById(fp.getPartyId()).orElse(null);
                    if (person == null) return null;
                    String bedName = null;
                    String roomName = null;
                    boolean hasAdmission = false;
                    Optional<FacilityParty> bedAssignment = facilityPartyRepository
                            .findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                                    organizationId, fp.getPartyId(), OccupancyRole.OCCUPANT);
                    LocalDate moveInDate = null;
                    BigDecimal monthlyRent = null;
                    BigDecimal securityDeposit = null;
                    LocalDate expectedCheckoutDate = null;
                    if (bedAssignment.isPresent()) {
                        hasAdmission = true;
                        Long bedId = bedAssignment.get().getFacilityId();
                        moveInDate = bedAssignment.get().getFromDate();
                        monthlyRent = bedAssignment.get().getMonthlyRent();
                        securityDeposit = bedAssignment.get().getSecurityDeposit();
                        expectedCheckoutDate = bedAssignment.get().getExpectedCheckoutDate();
                        bedName = facilityRepository.findById(bedId)
                                .map(Facility::getFacilityName).orElse(null);
                        roomName = facilityGroupMemberRepository
                                .findByChildFacilityIdAndThruDateIsNull(bedId)
                                .stream().findFirst()
                                .flatMap(m -> facilityRepository.findById(m.getParentFacilityId()))
                                .map(Facility::getFacilityName).orElse(null);
                    }
                    return toResponse(person, bedName, roomName, hasAdmission, moveInDate, monthlyRent, securityDeposit, expectedCheckoutDate);
                })
                .filter(r -> r != null)
                .toList();
    }

    @Transactional(readOnly = true)
    public TenantResponse get(Long organizationId, Long partyId) {
        assertTenantInOrganization(organizationId, partyId);
        Person person = personRepository.findById(partyId)
                .orElseThrow(() -> new NotFoundException("Tenant not found"));
        String bedName = null;
        String roomName = null;
        boolean hasAdmission = false;
        Optional<FacilityParty> bedAssignment = facilityPartyRepository
                .findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                        organizationId, partyId, OccupancyRole.OCCUPANT);
        LocalDate moveInDate = null;
        BigDecimal monthlyRent = null;
        BigDecimal securityDeposit = null;
        LocalDate expectedCheckoutDate = null;
        if (bedAssignment.isPresent()) {
            hasAdmission = true;
            Long bedId = bedAssignment.get().getFacilityId();
            moveInDate = bedAssignment.get().getFromDate();
            monthlyRent = bedAssignment.get().getMonthlyRent();
            securityDeposit = bedAssignment.get().getSecurityDeposit();
            expectedCheckoutDate = bedAssignment.get().getExpectedCheckoutDate();
            bedName = facilityRepository.findById(bedId).map(Facility::getFacilityName).orElse(null);
            roomName = facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(bedId)
                    .stream().findFirst()
                    .flatMap(fgm -> facilityRepository.findById(fgm.getParentFacilityId()))
                    .map(Facility::getFacilityName).orElse(null);
        }
        return toResponse(person, bedName, roomName, hasAdmission, moveInDate, monthlyRent, securityDeposit, expectedCheckoutDate);
    }

    @Transactional
    public TenantResponse update(Long organizationId, Long partyId, TenantUpdateRequest request) {
        assertTenantInOrganization(organizationId, partyId);
        Person person = personRepository.findById(partyId)
                .orElseThrow(() -> new NotFoundException("Tenant not found"));
        applyFields(person, request);
        return toResponse(person, null, null, false, null, null, null, null);
    }

    @Transactional
    public TenantResponse patch(Long organizationId, Long partyId, TenantPatchRequest request) {
        assertTenantInOrganization(organizationId, partyId);
        Person person = personRepository.findById(partyId)
                .orElseThrow(() -> new NotFoundException("Tenant not found"));
        if (request.emergencyContactName() != null) person.setEmergencyContactName(request.emergencyContactName());
        if (request.emergencyContactMobile() != null) person.setEmergencyContactMobile(request.emergencyContactMobile());
        if (request.emergencyContactRelation() != null) person.setEmergencyContactRelation(request.emergencyContactRelation());
        if (request.employerName() != null) person.setEmployerName(request.employerName());
        if (request.designation() != null) person.setDesignation(request.designation());
        if (request.workAddress() != null) person.setWorkAddress(request.workAddress());
        return toResponse(person, null, null, false, null, null, null, null);
    }

    // Walks bed → room → floor → property to check if a bed belongs to a property.
    private boolean isInProperty(Long bedId, Long propertyId) {
        return facilityGroupMemberRepository.findByChildFacilityIdAndThruDateIsNull(bedId)
                .stream().findFirst()
                .flatMap(rgm -> facilityGroupMemberRepository
                        .findByChildFacilityIdAndThruDateIsNull(rgm.getParentFacilityId())
                        .stream().findFirst())
                .flatMap(fgm -> facilityGroupMemberRepository
                        .findByChildFacilityIdAndThruDateIsNull(fgm.getParentFacilityId())
                        .stream().findFirst())
                .map(pgm -> propertyId.equals(pgm.getParentFacilityId()))
                .orElse(false);
    }

    private void assertTenantInOrganization(Long organizationId, Long partyId) {
        facilityPartyRepository.findOrgMembership(organizationId, partyId, OccupancyRole.TENANT)
                .orElseThrow(() -> new NotFoundException("Tenant not found in current organization"));
    }

    private void applyFields(Person person, TenantCreateRequest r) {
        person.setFullName(r.fullName());
        person.setMobileNumber(r.mobileNumber());
        person.setEmail(r.email());
        person.setGender(r.gender());
        person.setDateOfBirth(r.dateOfBirth());
        person.setAadhaarNumber(r.aadhaarNumber());
        person.setOccupation(r.occupation());
        person.setPermanentAddress(r.permanentAddress());
        person.setEmergencyContactName(r.emergencyContactName());
        person.setEmergencyContactMobile(r.emergencyContactMobile());
        person.setEmergencyContactRelation(r.emergencyContactRelation());
        person.setEmployerName(r.employerName());
        person.setDesignation(r.designation());
        person.setWorkAddress(r.workAddress());
    }

    private void applyFields(Person person, TenantUpdateRequest r) {
        person.setFullName(r.fullName());
        person.setMobileNumber(r.mobileNumber());
        person.setEmail(r.email());
        person.setGender(r.gender());
        person.setDateOfBirth(r.dateOfBirth());
        person.setAadhaarNumber(r.aadhaarNumber());
        person.setOccupation(r.occupation());
        person.setPermanentAddress(r.permanentAddress());
        person.setEmergencyContactName(r.emergencyContactName());
        person.setEmergencyContactMobile(r.emergencyContactMobile());
        person.setEmergencyContactRelation(r.emergencyContactRelation());
        person.setEmployerName(r.employerName());
        person.setDesignation(r.designation());
        person.setWorkAddress(r.workAddress());
    }

    public TenantResponse toResponse(Person person, String currentBedName, String currentRoomName,
            boolean hasActiveAdmission, LocalDate moveInDate, BigDecimal monthlyRent, BigDecimal securityDeposit,
            LocalDate expectedCheckoutDate) {
        return new TenantResponse(
                person.getPartyId(),
                person.getFullName(),
                person.getMobileNumber(),
                person.getEmail(),
                person.getGender(),
                person.getDateOfBirth(),
                person.getAadhaarNumber(),
                person.getPermanentAddress(),
                person.getEmergencyContactName(),
                person.getEmergencyContactMobile(),
                person.getEmergencyContactRelation(),
                person.getEmployerName(),
                person.getDesignation(),
                person.getWorkAddress(),
                currentBedName,
                currentRoomName,
                hasActiveAdmission,
                moveInDate,
                monthlyRent,
                securityDeposit,
                expectedCheckoutDate
        );
    }
}
