package com.pgmanager.security;

import com.pgmanager.common.exception.BadRequestException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import org.springframework.mock.web.MockHttpServletRequest;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The authorization core. Everything else in the property-scoping feature trusts this class, so its
 * two failure directions are both pinned: an owner must never be narrowed, and a scoped login must
 * never widen.
 */
class PropertyAccessGuardTest {

    private JdbcTemplate jdbc;
    private CurrentUser currentUser;
    private PropertyAccessGuard guard;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        currentUser = mock(CurrentUser.class);
        lenient().when(currentUser.organizationId()).thenReturn(1L);
        guard = new PropertyAccessGuard(currentUser, jdbc);
        // A real request context, so the per-request memoisation path is what gets exercised.
        RequestContextHolder.setRequestAttributes(
                new ServletRequestAttributes(new MockHttpServletRequest()));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
        RequestContextHolder.resetRequestAttributes();
    }

    private void authenticateAs(String role, Long partyId) {
        AppUserPrincipal principal = new AppUserPrincipal(
                10L, partyId, 1L, "user@pg.com", "hash", role, "ACTIVE", "Test User");
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(principal, null, principal.getAuthorities()));
        lenient().when(currentUser.principal()).thenReturn(principal);
    }

    private void assignedProperties(Long... propertyIds) {
        when(jdbc.queryForList(anyString(), eq(Long.class), any(), any(), any()))
                .thenReturn(List.of(propertyIds));
    }

    // ── Owner: never narrowed ────────────────────────────────────────────────

    @Test
    void ownerIsUnrestrictedAndKeepsTheOrgWideView() {
        authenticateAs(RoleType.OWNER, 99L);

        assertThat(guard.unrestricted()).isTrue();
        // Null in, null out: org-wide reads must behave exactly as they did before scoping existed.
        assertThat(guard.resolvePropertyId(null)).isNull();
        assertThat(guard.resolvePropertyId(77L)).isEqualTo(77L);
    }

    @Test
    void ownerNeverTriggersAnAssignmentLookup() {
        authenticateAs(RoleType.OWNER, 99L);

        guard.resolvePropertyId(5L);
        guard.assertCanAccess(6L);

        // Owners short-circuit before any query - scoping must cost them nothing.
        verify(jdbc, times(0)).queryForList(anyString(), eq(Long.class), any(), any(), any());
    }

    @Test
    void ownerPropertyFilterIsEmptySoQueriesAreUnchanged() {
        authenticateAs(RoleType.OWNER, 99L);

        assertThat(guard.propertyFilter("property_facility_id").isEmpty()).isTrue();
    }

    // ── Manager: never widened ───────────────────────────────────────────────

    @Test
    void managerMayAccessAnAssignedProperty() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties(7L, 8L);

        assertThat(guard.unrestricted()).isFalse();
        assertThat(guard.resolvePropertyId(7L)).isEqualTo(7L);
    }

    @Test
    void managerIsDeniedAnUnassignedProperty() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties(7L);

        assertThatThrownBy(() -> guard.resolvePropertyId(9L))
                .isInstanceOf(AccessDeniedException.class);
    }

    @Test
    void aSingleAssignmentIsSubstitutedWhenNoPropertyIsRequested() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties(7L);

        // This is what lets every existing optional-propertyId endpoint become scoped with a
        // one-line change: the manager's own property is filled in for them.
        assertThat(guard.resolvePropertyId(null)).isEqualTo(7L);
    }

    @Test
    void severalAssignmentsWithNoRequestedPropertyIsRejectedRatherThanWidened() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties(7L, 8L);

        // The whole point: never silently answer org-wide. A 400 asking for a property is safe;
        // guessing is not.
        assertThatThrownBy(() -> guard.resolvePropertyId(null))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("Select a property");
    }

    @Test
    void aManagerWithNoAssignmentsSeesNothing() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties();

        // Fails closed. The opposite mistake hands a brand-new login the whole organization.
        assertThatThrownBy(() -> guard.resolvePropertyId(null))
                .isInstanceOf(AccessDeniedException.class);
        assertThatThrownBy(() -> guard.resolvePropertyId(7L))
                .isInstanceOf(AccessDeniedException.class);
    }

    @Test
    void anUnassignedManagerGetsAFilterThatMatchesNothing() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties();

        // Not an empty string - dropping the predicate would return the whole organization.
        PropertyAccessGuard.PropertyFilter filter = guard.propertyFilter("property_facility_id");
        assertThat(filter.isEmpty()).isFalse();
        assertThat(filter.sql()).isEqualTo(" AND 1=0");
    }

    @Test
    void managerPropertyFilterBindsEveryAssignedProperty() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties(7L, 8L);

        PropertyAccessGuard.PropertyFilter filter = guard.propertyFilter("property_facility_id");
        assertThat(filter.sql()).isEqualTo(" AND property_facility_id IN (?,?)");
        assertThat(filter.args()).containsExactly(7L, 8L);
    }

    @Test
    void otherStaffRolesAreScopedToo() {
        // Only OWNER is unrestricted; MANAGER/ACCOUNTANT/VIEWER all follow their assignments, so a
        // future role added to SecurityConfig cannot accidentally arrive org-wide.
        authenticateAs(RoleType.ACCOUNTANT, 55L);
        assignedProperties(7L);

        assertThat(guard.unrestricted()).isFalse();
        assertThat(guard.resolvePropertyId(null)).isEqualTo(7L);
    }

    @Test
    void theAssignmentSetIsResolvedOncePerRequest() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties(7L);

        guard.resolvePropertyId(null);
        guard.resolvePropertyId(7L);
        guard.assertCanAccess(7L);
        guard.propertyFilter("x");

        // Memoised on the request, so a controller calling the guard several times costs one query.
        verify(jdbc, times(1)).queryForList(anyString(), eq(Long.class), any(), any(), any());
    }

    // ── System context ──────────────────────────────────────────────────────

    @Test
    void anUnauthenticatedSystemContextIsUnrestricted() {
        // No authentication at all: the @Scheduled jobs and public self check-in run here. Scoping
        // them would stop invoice generation dead.
        assertThat(guard.unrestricted()).isTrue();
        assertThat(guard.resolvePropertyId(null)).isNull();
    }

    @Test
    void superAdminIsUnrestricted() {
        authenticateAs(RoleType.SUPER_ADMIN, null);

        assertThat(guard.unrestricted()).isTrue();
    }

    // ── Tenant scoping ──────────────────────────────────────────────────────

    @Test
    void managerMayReachATenantOfTheirOwnProperty() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties(7L);
        when(jdbc.queryForList(anyString(), eq(Long.class), any(), any())).thenReturn(List.of(7L));

        guard.assertTenantInScope(500L);   // does not throw
    }

    @Test
    void managerIsDeniedATenantOfAnotherProperty() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties(7L);
        when(jdbc.queryForList(anyString(), eq(Long.class), any(), any())).thenReturn(List.of(9L));

        assertThatThrownBy(() -> guard.assertTenantInScope(500L))
                .isInstanceOf(AccessDeniedException.class);
    }

    @Test
    void aTenantWithNoPropertyIsOwnerOnly() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties(7L);
        // Org-level only (added before any property existed, or via the org-level check-in link).
        when(jdbc.queryForList(anyString(), eq(Long.class), any(), any())).thenReturn(List.of());

        assertThatThrownBy(() -> guard.assertTenantInScope(500L))
                .isInstanceOf(AccessDeniedException.class);
    }

    @Test
    void tenantScopeCheckIsSkippedEntirelyForAnOwner() {
        authenticateAs(RoleType.OWNER, 99L);

        guard.assertTenantInScope(500L);

        // No tenant-property lookup for an owner.
        verify(jdbc, times(0)).queryForList(anyString(), eq(Long.class), any(), any());
    }

    @Test
    void assertCanAccessTreatsNullAsNoSpecificProperty() {
        authenticateAs(RoleType.PROPERTY_MANAGER, 55L);
        assignedProperties(7L);

        // Null is "no property named", handled by resolvePropertyId - not an implicit allow-all.
        guard.assertCanAccess(null);
        assertThat(guard.scope().allows(null)).isFalse();
    }

    @Test
    void facilityScopeCheckIsSkippedForAnOwner() {
        authenticateAs(RoleType.OWNER, 99L);

        guard.assertFacilityInScope(1234L);

        verify(jdbc, times(0)).queryForList(anyString(), eq(String.class), anyLong());
    }
}
