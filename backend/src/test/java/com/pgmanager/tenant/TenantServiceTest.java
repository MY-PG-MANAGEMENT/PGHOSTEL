package com.pgmanager.tenant;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityGroupMemberRepository;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.occupancy.FacilityParty;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.occupancy.OccupancyRole;
import com.pgmanager.party.Party;
import com.pgmanager.party.PartyRepository;
import com.pgmanager.party.Person;
import com.pgmanager.party.PersonRepository;
import com.pgmanager.tenant.dto.TenantDtos.TenantCreateRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantResponse;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * Critical-path unit tests for tenant creation and org-scoped access. Pure
 * Mockito, no Spring context or database.
 */
@ExtendWith(MockitoExtension.class)
class TenantServiceTest {

    private static final long ORG = 1L;
    private static final long USER = 7L;

    @Mock PartyRepository partyRepository;
    @Mock PersonRepository personRepository;
    @Mock FacilityPartyRepository facilityPartyRepository;
    @Mock FacilityRepository facilityRepository;
    @Mock FacilityGroupMemberRepository facilityGroupMemberRepository;
    @Mock AuditService auditService;

    @InjectMocks TenantService service;

    private TenantCreateRequest request(Long propertyId) {
        return new TenantCreateRequest("Asha Rao", "9876543210", null, null, null, null,
                null, null, null, null, null, null, null, null, propertyId);
    }

    private void stubSaves() {
        when(partyRepository.save(any(Party.class))).thenAnswer(inv -> {
            Party p = inv.getArgument(0);
            p.setPartyId(100L);
            return p;
        });
        when(personRepository.save(any(Person.class))).thenAnswer(inv -> inv.getArgument(0));
    }

    @Test
    void createWithoutProperty_persistsPartyPersonAndOrgMembership() {
        stubSaves();
        when(facilityPartyRepository.findOrgMembership(ORG, 100L, OccupancyRole.TENANT))
                .thenReturn(Optional.empty());

        TenantResponse res = service.create(ORG, USER, request(null));

        assertThat(res.fullName()).isEqualTo("Asha Rao");
        verify(partyRepository).save(any(Party.class));
        verify(personRepository).save(any(Person.class));
        // org-level TENANT membership written (facilityId = organizationId)
        verify(facilityPartyRepository).save(argThat(fp ->
                fp.getFacilityId().equals(ORG) && fp.getRoleTypeId().equals(OccupancyRole.TENANT)));
        verify(auditService).log(eq(ORG), eq(USER), eq("TENANT_CREATED"), any(), any(), any());
    }

    @Test
    void createRejectsDuplicateMobileAtSameProperty() {
        when(personRepository.countActiveTenantsByMobileAtProperty("9876543210", ORG, 5L)).thenReturn(1L);

        assertThatThrownBy(() -> service.create(ORG, USER, request(5L)))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("already registered at this property");

        verify(partyRepository, never()).save(any());
    }

    @Test
    void createRejectsPropertyFromAnotherOrganization() {
        stubSaves();
        when(personRepository.countActiveTenantsByMobileAtProperty(any(), eq(ORG), eq(5L))).thenReturn(0L);
        when(facilityPartyRepository.findOrgMembership(ORG, 100L, OccupancyRole.TENANT)).thenReturn(Optional.empty());
        Facility foreign = new Facility();
        foreign.setFacilityId(5L);
        foreign.setOrganizationId(999L); // different org
        when(facilityRepository.findById(5L)).thenReturn(Optional.of(foreign));

        assertThatThrownBy(() -> service.create(ORG, USER, request(5L)))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("not in current organization");
    }

    @Test
    void getRejectsTenantOutsideOrganization() {
        when(facilityPartyRepository.findOrgMembership(ORG, 42L, OccupancyRole.TENANT))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.get(ORG, 42L))
                .isInstanceOf(NotFoundException.class);
    }

    @Test
    void getReturnsTenantWithinOrganization() {
        when(facilityPartyRepository.findOrgMembership(ORG, 42L, OccupancyRole.TENANT))
                .thenReturn(Optional.of(new FacilityParty()));
        Person person = new Person();
        person.setPartyId(42L);
        person.setFullName("Asha Rao");
        when(personRepository.findById(42L)).thenReturn(Optional.of(person));
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
                ORG, 42L, OccupancyRole.OCCUPANT)).thenReturn(Optional.empty());

        TenantResponse res = service.get(ORG, 42L);

        assertThat(res.tenantId()).isEqualTo(42L);
        assertThat(res.hasActiveAdmission()).isFalse();
    }
}
