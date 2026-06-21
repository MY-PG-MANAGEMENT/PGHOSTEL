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
import java.util.Optional;

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
        // property-scoped TENANT rows (written at creation time for the workspace flow)
        // don't produce a duplicate entry per tenant.
        return facilityPartyRepository
                .findTenantsAtFacility(organizationId, organizationId, OccupancyRole.TENANT)
                .stream()
                .map(fp -> {
                    Person person = personRepository.findById(fp.getPartyId()).orElseThrow();
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
                                .flatMap(fgm -> facilityRepository.findById(fgm.getParentFacilityId()))
                                .map(Facility::getFacilityName).orElse(null);
                    }
                    return toResponse(person, bedName, roomName, hasAdmission, moveInDate, monthlyRent, securityDeposit, expectedCheckoutDate);
                })
                .toList();
    }

    @Transactional(readOnly = true)
    public List<TenantResponse> listByProperty(Long organizationId, Long propertyId) {
        return facilityPartyRepository
                .findTenantsAtFacility(organizationId, propertyId, OccupancyRole.TENANT)
                .stream()
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
