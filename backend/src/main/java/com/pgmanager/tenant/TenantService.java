package com.pgmanager.tenant;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.occupancy.FacilityParty;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.occupancy.OccupancyRole;
import com.pgmanager.party.Party;
import com.pgmanager.party.PartyRepository;
import com.pgmanager.party.PartyType;
import com.pgmanager.party.Person;
import com.pgmanager.party.PersonRepository;
import com.pgmanager.tenant.dto.TenantDtos.TenantCreateRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantResponse;
import com.pgmanager.tenant.dto.TenantDtos.TenantUpdateRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;

@Service
@RequiredArgsConstructor
public class TenantService {
    private final PartyRepository partyRepository;
    private final PersonRepository personRepository;
    private final FacilityPartyRepository facilityPartyRepository;
    private final AuditService auditService;

    @Transactional
    public TenantResponse create(Long organizationId, Long userLoginId, TenantCreateRequest request) {
        Party party = new Party();
        party.setPartyTypeId(PartyType.PERSON);
        party = partyRepository.save(party);

        Person person = new Person();
        person.setPartyId(party.getPartyId());
        apply(person, request.fullName(), request.mobileNumber(), request.gender(), request.dateOfBirth(), request.aadhaarNumber(),
                request.occupation(), request.companyName(), request.guardianName(), request.guardianMobileNumber(), request.address());
        personRepository.save(person);

        FacilityParty tenantMembership = new FacilityParty();
        tenantMembership.setOrganizationId(organizationId);
        tenantMembership.setFacilityId(organizationId);
        tenantMembership.setPartyId(party.getPartyId());
        tenantMembership.setRoleTypeId(OccupancyRole.TENANT);
        tenantMembership.setFromDate(LocalDate.now());
        facilityPartyRepository.save(tenantMembership);

        auditService.log(organizationId, userLoginId, "TENANT_CREATED", "PARTY", party.getPartyId(), "Tenant created");
        return toResponse(person);
    }

    @Transactional(readOnly = true)
    public List<TenantResponse> list(Long organizationId) {
        return facilityPartyRepository.findByOrganizationIdAndRoleTypeIdAndThruDateIsNull(organizationId, OccupancyRole.TENANT).stream()
                .map(fp -> personRepository.findById(fp.getPartyId()).orElseThrow())
                .map(this::toResponse)
                .toList();
    }

    @Transactional(readOnly = true)
    public TenantResponse get(Long organizationId, Long partyId) {
        assertTenantInOrganization(organizationId, partyId);
        return personRepository.findById(partyId).map(this::toResponse)
                .orElseThrow(() -> new NotFoundException("Tenant not found"));
    }

    @Transactional
    public TenantResponse update(Long organizationId, Long partyId, TenantUpdateRequest request) {
        assertTenantInOrganization(organizationId, partyId);
        Person person = personRepository.findById(partyId)
                .orElseThrow(() -> new NotFoundException("Tenant not found"));
        apply(person, request.fullName(), request.mobileNumber(), request.gender(), request.dateOfBirth(), request.aadhaarNumber(),
                request.occupation(), request.companyName(), request.guardianName(), request.guardianMobileNumber(), request.address());
        return toResponse(person);
    }

    private void assertTenantInOrganization(Long organizationId, Long partyId) {
        facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                organizationId,
                partyId,
                OccupancyRole.TENANT
        ).orElseThrow(() -> new NotFoundException("Tenant not found in current organization"));
    }

    private void apply(Person person, String fullName, String mobileNumber, String gender, LocalDate dateOfBirth, String aadhaarNumber,
                       String occupation, String companyName, String guardianName, String guardianMobileNumber, String address) {
        person.setFullName(fullName);
        person.setMobileNumber(mobileNumber);
        person.setGender(gender);
        person.setDateOfBirth(dateOfBirth);
        person.setAadhaarNumber(aadhaarNumber);
        person.setOccupation(occupation);
        person.setCompanyName(companyName);
        person.setGuardianName(guardianName);
        person.setGuardianMobileNumber(guardianMobileNumber);
        person.setAddress(address);
    }

    private TenantResponse toResponse(Person person) {
        return new TenantResponse(
                person.getPartyId(),
                person.getFullName(),
                person.getMobileNumber(),
                person.getGender(),
                person.getDateOfBirth(),
                person.getAadhaarNumber(),
                person.getOccupation(),
                person.getCompanyName(),
                person.getGuardianName(),
                person.getGuardianMobileNumber(),
                person.getAddress()
        );
    }
}
