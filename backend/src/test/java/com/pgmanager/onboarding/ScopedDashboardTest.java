package com.pgmanager.onboarding;

import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityService;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.dashboard.DashboardResponse;
import com.pgmanager.dashboard.DashboardService;
import com.pgmanager.payment.PaymentRepository;
import com.pgmanager.rent.RentRepository;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.security.PropertyAccessGuard;
import com.pgmanager.security.PropertyScope;
import com.pgmanager.facility.dto.FacilityDtos.FacilityResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The two places a property-scoped login was still shown the whole organization: the property list
 * behind the Properties screen / property switcher, and the home dashboard's headline numbers.
 *
 * <p>Scoping {@code FacilityService.tree()} had not been enough — the app reads its property list
 * from {@code GET /api/owner/properties}, so an unassigned property still appeared and could be
 * tapped, producing a 403 on every panel instead of simply not being there.
 */
class ScopedDashboardTest {

    private FacilityRepository facilityRepository;
    private FacilityPartyRepository facilityPartyRepository;
    private RentRepository rentRepository;
    private PaymentRepository paymentRepository;
    private PropertyAccessGuard guard;
    private JdbcTemplate jdbc;
    private DashboardService dashboardService;
    private OwnerController ownerController;

    @BeforeEach
    void setUp() {
        facilityRepository = mock(FacilityRepository.class);
        facilityPartyRepository = mock(FacilityPartyRepository.class);
        rentRepository = mock(RentRepository.class);
        paymentRepository = mock(PaymentRepository.class);
        guard = mock(PropertyAccessGuard.class);
        jdbc = mock(JdbcTemplate.class);

        dashboardService = new DashboardService(facilityRepository, facilityPartyRepository,
                rentRepository, paymentRepository, guard, jdbc);

        FacilityService facilityService = mock(FacilityService.class);
        lenient().when(facilityService.toResponse(any())).thenAnswer(inv -> {
            Facility f = inv.getArgument(0);
            return new FacilityResponse(f.getFacilityId(), null, FacilityType.PROPERTY,
                    f.getFacilityName(), null, null, null, null, null, null, null, null, null, null,
                    null, null, null, false, false);
        });
        CurrentUser currentUser = mock(CurrentUser.class);
        lenient().when(currentUser.organizationId()).thenReturn(1L);

        ownerController = new OwnerController(mock(OnboardingService.class), dashboardService,
                facilityRepository, facilityService, currentUser, guard);
    }

    private Facility property(long id, String name) {
        Facility f = new Facility();
        f.setFacilityId(id);
        f.setFacilityName(name);
        f.setFacilityTypeId(FacilityType.PROPERTY);
        return f;
    }

    private void stubProperties() {
        when(facilityRepository.findByOrganizationIdAndFacilityTypeIdAndStatus(1L, FacilityType.PROPERTY, "ACTIVE"))
                .thenReturn(List.of(property(7L, "Sunrise PG"), property(8L, "Metro Stays")));
    }

    // ── The reported bug: the unassigned property must not be listed at all ──

    @Test
    void aScopedLoginOnlySeesItsAssignedProperties() {
        stubProperties();
        when(guard.scope()).thenReturn(PropertyScope.restrictedTo(Set.of(7L)));

        var properties = ownerController.properties().data();

        // Previously both came back, so the manager saw a property whose every panel 403'd.
        assertThat(properties).hasSize(1);
        assertThat(properties.get(0).facilityName()).isEqualTo("Sunrise PG");
    }

    @Test
    void anOwnerStillSeesEveryProperty() {
        stubProperties();
        when(guard.scope()).thenReturn(PropertyScope.unrestrictedScope());

        assertThat(ownerController.properties().data()).hasSize(2);
    }

    @Test
    void aLoginWithNoAssignmentsSeesNoProperties() {
        stubProperties();
        when(guard.scope()).thenReturn(PropertyScope.restrictedTo(Set.of()));

        assertThat(ownerController.properties().data()).isEmpty();
    }

    // ── Dashboard numbers ───────────────────────────────────────────────────

    @Test
    void ownerDashboardKeepsTheOriginalOrgWideCounts() {
        when(guard.scope()).thenReturn(PropertyScope.unrestrictedScope());
        when(facilityRepository.countByOrganizationIdAndFacilityTypeIdAndStatus(1L, FacilityType.BED, "ACTIVE"))
                .thenReturn(40L);
        when(facilityPartyRepository.countByOrganizationIdAndRoleTypeIdAndThruDateIsNull(eq(1L), anyString()))
                .thenReturn(25L);
        when(rentRepository.findByOrganizationId(1L)).thenReturn(List.of());
        when(paymentRepository.sumAmountByOrganizationId(1L)).thenReturn(new BigDecimal("5000"));

        DashboardResponse response = dashboardService.ownerDashboard(1L);

        assertThat(response.totalBeds()).isEqualTo(40);
        assertThat(response.occupiedBeds()).isEqualTo(25);
        assertThat(response.vacantBeds()).isEqualTo(15);
        assertThat(response.revenue()).isEqualByComparingTo("5000");
        // The owner path must not have been rerouted through the scoped SQL.
        verify(jdbc, never()).queryForObject(anyString(), eq(Long.class), any(Object[].class));
    }

    @Test
    void scopedDashboardCountsOnlyTheAssignedProperties() {
        when(guard.scope()).thenReturn(PropertyScope.restrictedTo(Set.of(7L)));
        when(jdbc.queryForObject(anyString(), eq(Long.class), any(Object[].class)))
                .thenReturn(10L, 6L, 6L);
        when(jdbc.queryForObject(anyString(), eq(BigDecimal.class), any(Object[].class)))
                .thenReturn(new BigDecimal("1200"), new BigDecimal("900"));

        DashboardResponse response = dashboardService.ownerDashboard(1L);

        assertThat(response.totalBeds()).isEqualTo(10);
        assertThat(response.occupiedBeds()).isEqualTo(6);
        assertThat(response.vacantBeds()).isEqualTo(4);
        assertThat(response.totalTenants()).isEqualTo(6);
        assertThat(response.pendingRent()).isEqualByComparingTo("1200");
        assertThat(response.revenue()).isEqualByComparingTo("900");
        // Never the org-wide JPA counts - those are what leaked the organization's size.
        verify(facilityRepository, never())
                .countByOrganizationIdAndFacilityTypeIdAndStatus(anyLong(), anyString(), anyString());
        verify(paymentRepository, never()).sumAmountByOrganizationId(anyLong());
    }

    @Test
    void anUnassignedLoginGetsZeroesNotOrgTotals() {
        when(guard.scope()).thenReturn(PropertyScope.restrictedTo(Set.of()));

        DashboardResponse response = dashboardService.ownerDashboard(1L);

        assertThat(response.totalBeds()).isZero();
        assertThat(response.occupiedBeds()).isZero();
        assertThat(response.vacantBeds()).isZero();
        assertThat(response.totalTenants()).isZero();
        assertThat(response.pendingRent()).isEqualByComparingTo("0");
        assertThat(response.revenue()).isEqualByComparingTo("0");
        // Fails closed with no query at all - an empty IN (...) would have been a SQL error, and
        // dropping the predicate would have reported the whole organization.
        verify(jdbc, never()).queryForObject(anyString(), eq(Long.class), any(Object[].class));
    }
}
