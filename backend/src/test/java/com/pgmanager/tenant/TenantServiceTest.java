package com.pgmanager.tenant;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityGroupMember;
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

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
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
    @Mock com.pgmanager.notification.NotificationService notificationService;
    @Mock TenantLoginService tenantLoginService;

    @InjectMocks TenantService service;

    private TenantCreateRequest request(Long propertyId) {
        return new TenantCreateRequest("Asha Rao", "9876543210", null, null, null, null,
                null, null, null, null, null, null, null, null, false, propertyId);
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

    /**
     * listByProperty must, in a fixed number of batch queries (no per-tenant lookups):
     *  - include a tenant with an explicit property-level row (A, active bed in the property),
     *  - include an org-level tenant via the union because a (historical/checked-out) OCCUPANT
     *    bed of theirs lives in this property (B),
     *  - exclude an org-level tenant whose only OCCUPANT bed is in a different property (C).
     */
    @Test
    void listByProperty_batchesAndUnionsWithoutPerTenantQueries() {
        long property = 500L;
        // Facility tree: bed -> room -> floor -> property.
        Map<Long, Long> parents = new HashMap<>();
        parents.put(10L, 20L); parents.put(11L, 21L); parents.put(12L, 22L); // bed -> room
        parents.put(20L, 30L); parents.put(21L, 31L); parents.put(22L, 32L); // room -> floor
        parents.put(30L, 500L); parents.put(31L, 500L); parents.put(32L, 600L); // floor -> property

        when(facilityPartyRepository.findTenantsAtFacility(ORG, property, OccupancyRole.TENANT))
                .thenReturn(List.of(tenantRow(100L, property)));
        when(facilityPartyRepository.findTenantsAtFacility(ORG, ORG, OccupancyRole.TENANT))
                .thenReturn(List.of(tenantRow(100L, ORG), tenantRow(101L, ORG), tenantRow(102L, ORG)));
        // All OCCUPANT rows (active + historical) for the org's tenants.
        when(facilityPartyRepository.findByOrganizationIdAndPartyIdInAndRoleTypeId(
                eq(ORG), anyList(), eq(OccupancyRole.OCCUPANT)))
                .thenReturn(List.of(occupant(100L, 10L), occupant(101L, 11L), occupant(102L, 12L)));

        // bed->room->floor->property resolution, order-independent.
        when(facilityGroupMemberRepository.findByChildFacilityIdInAndThruDateIsNull(anyList()))
                .thenAnswer(inv -> {
                    List<Long> ids = inv.getArgument(0);
                    return ids.stream().filter(parents::containsKey)
                            .map(id -> groupMember(id, parents.get(id))).toList();
                });

        // buildTenantResponses batch loads: only A (100) has an ACTIVE bed; B (101) is checked out.
        when(personRepository.findAllById(anyList()))
                .thenReturn(List.of(person(100L, "Asha Rao"), person(101L, "Ravi Kumar")));
        when(facilityPartyRepository.findActiveOccupantsByPartyIds(eq(ORG), anyList(), eq(OccupancyRole.OCCUPANT)))
                .thenReturn(List.of(occupant(100L, 10L)));
        when(facilityPartyRepository.findActiveOccupantsByPartyIds(eq(ORG), anyList(), eq(OccupancyRole.TEMP_OCCUPANT)))
                .thenReturn(List.of());
        when(facilityRepository.findAllById(anyList())).thenAnswer(inv -> {
            List<Long> ids = inv.getArgument(0);
            return ids.stream().map(id -> facility(id, "F-" + id)).toList();
        });

        List<TenantResponse> result = service.listByProperty(ORG, property);

        // A (explicit + in property) and B (union) present; C (other property) absent.
        assertThat(result).extracting(TenantResponse::tenantId).containsExactlyInAnyOrder(100L, 101L);
        TenantResponse a = result.stream().filter(r -> r.tenantId() == 100L).findFirst().orElseThrow();
        assertThat(a.hasActiveAdmission()).isTrue();
        assertThat(a.currentBedName()).isEqualTo("F-10");
        TenantResponse b = result.stream().filter(r -> r.tenantId() == 101L).findFirst().orElseThrow();
        assertThat(b.hasActiveAdmission()).isFalse(); // checked out — no active bed

        // No per-tenant fallbacks: the single-party occupant/child lookups are never used.
        verify(facilityPartyRepository, never())
                .findByOrganizationIdAndPartyIdAndRoleTypeId(anyLong(), anyLong(), any());
        verify(facilityGroupMemberRepository, never()).findByChildFacilityIdAndThruDateIsNull(anyLong());
    }

    private FacilityParty tenantRow(long partyId, long facilityId) {
        FacilityParty fp = new FacilityParty();
        fp.setOrganizationId(ORG);
        fp.setPartyId(partyId);
        fp.setFacilityId(facilityId);
        fp.setRoleTypeId(OccupancyRole.TENANT);
        return fp;
    }

    private FacilityParty occupant(long partyId, long bedId) {
        FacilityParty fp = new FacilityParty();
        fp.setOrganizationId(ORG);
        fp.setPartyId(partyId);
        fp.setFacilityId(bedId);
        fp.setRoleTypeId(OccupancyRole.OCCUPANT);
        return fp;
    }

    private FacilityGroupMember groupMember(long childId, long parentId) {
        FacilityGroupMember m = new FacilityGroupMember();
        m.setChildFacilityId(childId);
        m.setParentFacilityId(parentId);
        return m;
    }

    private Person person(long partyId, String name) {
        Person p = new Person();
        p.setPartyId(partyId);
        p.setFullName(name);
        return p;
    }

    private Facility facility(long id, String name) {
        Facility f = new Facility();
        f.setFacilityId(id);
        f.setFacilityName(name);
        return f;
    }
}
