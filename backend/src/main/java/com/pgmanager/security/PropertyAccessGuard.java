package com.pgmanager.security;

import com.pgmanager.common.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * The single gate for "may this login touch this property?".
 *
 * <p>Before this existed, {@code propertyId} was a client-supplied filter and nothing more: every
 * non-tenant role could pass any id and read any property in the organization. Roles like
 * PROPERTY_MANAGER were labels on a login, not a scope. This class turns them into a scope.
 *
 * <p><b>The rule.</b> OWNER (and SUPER_ADMIN, which belongs to no org) is unrestricted. Every other
 * non-tenant role is confined to the properties assigned to it — stored as
 * {@code facility_party} rows with {@code role_type_id = 'PROPERTY_MANAGER'} and a null
 * {@code thru_date}, the same dated-membership pattern tenants already use. No new table.
 *
 * <p><b>Assignments are read from the database, not the JWT.</b> A property claim would be baked
 * into a token that lives for {@code app.security.access-token-minutes} (30), so revoking a
 * property would not take effect for half an hour — the same staleness trap already documented for
 * {@link OrganizationStatusGuard}. Instead the set is resolved per request and memoised on the
 * request itself, so a reassignment is effective on the caller's very next call at the cost of one
 * indexed query (covered by {@code idx_fp_org_party_role_thru}, added in V23).
 *
 * <p>Memoisation uses a request attribute rather than a ThreadLocal for the reason spelled out in
 * {@code ApiLogContext}: a ThreadLocal survives on a pooled container thread and would leak one
 * login's property set into the next request — a cross-tenant authorization bug.
 */
@Service
@RequiredArgsConstructor
public class PropertyAccessGuard {

    private static final String SCOPE_ATTRIBUTE = PropertyAccessGuard.class.getName() + ".scope";

    /** The role that carries a property assignment. */
    public static final String ASSIGNMENT_ROLE = RoleType.PROPERTY_MANAGER;

    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;

    /** The current login's scope. Cheap to call repeatedly — resolved once per request. */
    public PropertyScope scope() {
        RequestAttributes attributes = RequestContextHolder.getRequestAttributes();
        if (attributes != null) {
            Object cached = attributes.getAttribute(SCOPE_ATTRIBUTE, RequestAttributes.SCOPE_REQUEST);
            if (cached instanceof PropertyScope scope) return scope;
        }
        PropertyScope resolved = resolveScope();
        if (attributes != null) {
            attributes.setAttribute(SCOPE_ATTRIBUTE, resolved, RequestAttributes.SCOPE_REQUEST);
        }
        return resolved;
    }

    private PropertyScope resolveScope() {
        AppUserPrincipal principal = authenticatedPrincipal();
        if (principal == null) {
            // No authenticated principal means a system context, not a user: the @Scheduled jobs
            // (rent reminders, invoice auto-generation, bed transfers) and the public self check-in
            // endpoints all run here. Those act for the whole organization by definition, and
            // restricting them would silently stop invoices generating. Safe because every
            // user-facing route under /api/** is authenticated by the security chain long before a
            // controller is reached, so a real caller can never arrive with an empty context.
            return PropertyScope.unrestrictedScope();
        }
        String role = principal.roleTypeId();
        // Owners run the organization; super admins are cross-org and never property-scoped.
        if (RoleType.OWNER.equals(role) || RoleType.SUPER_ADMIN.equals(role)) {
            return PropertyScope.unrestrictedScope();
        }
        Long organizationId = principal.organizationId();
        Long partyId = principal.partyId();
        if (organizationId == null || partyId == null) {
            // No org or no party to resolve assignments against - allow nothing.
            return PropertyScope.restrictedTo(Set.of());
        }
        List<Long> assigned = jdbc.queryForList(
                "SELECT fp.facility_id FROM facility_party fp " +
                "JOIN facility f ON f.facility_id = fp.facility_id AND f.facility_type_id = 'PROPERTY' " +
                "WHERE fp.organization_id = ? AND fp.party_id = ? AND fp.role_type_id = ? " +
                "  AND fp.thru_date IS NULL",
                Long.class, organizationId, partyId, ASSIGNMENT_ROLE);
        return PropertyScope.restrictedTo(new LinkedHashSet<>(assigned));
    }

    /**
     * The principal, or null in a system context. Reads {@code SecurityContextHolder} directly
     * rather than going through {@link CurrentUser#principal()}, which throws when unauthenticated —
     * here "nobody is logged in" is a normal, expected state that needs a value, not an exception.
     */
    private AppUserPrincipal authenticatedPrincipal() {
        var authentication = org.springframework.security.core.context.SecurityContextHolder
                .getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) return null;
        return authentication.getPrincipal() instanceof AppUserPrincipal principal ? principal : null;
    }

    public boolean unrestricted() {
        return scope().unrestricted();
    }

    /**
     * Throws 403 unless the caller may touch {@code propertyId}. A null id is accepted here — it
     * means "no specific property", which {@link #resolvePropertyId} handles.
     */
    public void assertCanAccess(Long propertyId) {
        if (propertyId == null) return;
        if (!scope().allows(propertyId)) {
            // Deliberately does not say whether the property exists: a manager probing ids should
            // not be able to enumerate the organization's properties from the error text.
            throw new AccessDeniedException("You do not have access to this property");
        }
    }

    /**
     * The property id an endpoint should actually use, given what the client asked for. This is the
     * workhorse: it makes an endpoint that already accepted an optional {@code propertyId} correctly
     * scoped with a one-line change.
     * <ul>
     *   <li>Owner → returned unchanged (null stays null, so org-wide reads work exactly as before).</li>
     *   <li>Manager who asked for a property → returned after an access check (403 if not theirs).</li>
     *   <li>Manager who asked for nothing, holding exactly one property → <b>substituted</b> with
     *       theirs, so the response is scoped instead of org-wide. This is the common case and it
     *       needs no change to the query.</li>
     *   <li>Manager holding several properties and asking for nothing → <b>400</b>, not an org-wide
     *       answer.</li>
     *   <li>Manager with no assignments → 403.</li>
     * </ul>
     *
     * <p>That fourth rule is the deliberate one. The alternative — quietly widening the query to an
     * {@code IN (...)} over their set — would mean rewriting the SQL of roughly twenty aggregate
     * endpoints (billing, expenses, transactions, reports) and getting every one right; a single
     * missed predicate silently returns the whole organization, and the API would look scoped while
     * leaking. Requiring an explicit property cannot leak. In practice it never fires: a scoped
     * login's property picker only lists their own properties, so the app always sends one.
     */
    public Long resolvePropertyId(Long requestedPropertyId) {
        assertCanAccess(requestedPropertyId);
        if (requestedPropertyId != null) return requestedPropertyId;

        PropertyScope scope = scope();
        if (scope.unrestricted()) return null;
        if (scope.isEmpty()) {
            throw new AccessDeniedException("No properties are assigned to this login");
        }
        Long sole = scope.soleProperty();
        if (sole != null) return sole;
        throw new BadRequestException("Select a property - this login is limited to specific properties");
    }

    /**
     * Asserts the caller may reach the property that {@code facilityId} sits under, for any node of
     * the tree (PROPERTY, FLOOR, ROOM or BED).
     *
     * <p>Needed because most write endpoints identify a bed or room, never a property — an
     * unguarded {@code POST /occupancy/assign} would let a manager put a tenant into a bed in
     * somebody else's property. Walks {@code facility_group_member} upwards, which is the same path
     * {@code OccupancyService.resolvePropertyId} takes.
     */
    public void assertFacilityInScope(Long facilityId) {
        if (facilityId == null || unrestricted()) return;
        Long propertyId = propertyOfFacility(facilityId);
        if (propertyId == null || !scope().allows(propertyId)) {
            throw new AccessDeniedException("You do not have access to this property");
        }
    }

    /** The PROPERTY ancestor of any facility node, or the node itself when it is a property. */
    public Long propertyOfFacility(Long facilityId) {
        List<String> types = jdbc.queryForList(
                "SELECT facility_type_id FROM facility WHERE facility_id = ?", String.class, facilityId);
        if (types.isEmpty()) return null;
        if (FACILITY_TYPE_PROPERTY.equals(types.get(0))) return facilityId;

        // Climb at most three links (BED -> ROOM -> FLOOR -> PROPERTY); the bound also stops a
        // cycle in the group table from spinning forever.
        Long current = facilityId;
        for (int depth = 0; depth < 4 && current != null; depth++) {
            List<Map<String, Object>> parents = jdbc.queryForList(
                    "SELECT f.facility_id, f.facility_type_id FROM facility_group_member gm " +
                    "JOIN facility f ON f.facility_id = gm.parent_facility_id " +
                    "WHERE gm.child_facility_id = ? AND gm.thru_date IS NULL LIMIT 1", current);
            if (parents.isEmpty()) return null;
            Map<String, Object> parent = parents.get(0);
            if (FACILITY_TYPE_PROPERTY.equals(parent.get("facility_type_id"))) {
                return ((Number) parent.get("facility_id")).longValue();
            }
            current = ((Number) parent.get("facility_id")).longValue();
        }
        return null;
    }

    /**
     * Asserts the caller may reach the tenant identified by {@code partyId}.
     *
     * <p>A tenant's property is their property-scoped {@code TENANT} membership row (tenants get one
     * org-level and one property-level row on create). A tenant with no property row at all — added
     * before a property existed, or via the org-level self check-in link — is visible only to the
     * owner, which is the safe reading: nobody has been given responsibility for them yet.
     */
    public void assertTenantInScope(Long partyId) {
        if (partyId == null || unrestricted()) return;
        Long organizationId = currentUser.organizationId();
        List<Long> properties = jdbc.queryForList(
                "SELECT fp.facility_id FROM facility_party fp " +
                "JOIN facility f ON f.facility_id = fp.facility_id AND f.facility_type_id = 'PROPERTY' " +
                "WHERE fp.organization_id = ? AND fp.party_id = ? AND fp.role_type_id = 'TENANT'",
                Long.class, organizationId, partyId);
        for (Long propertyId : properties) {
            if (scope().allows(propertyId)) return;
        }
        throw new AccessDeniedException("You do not have access to this tenant");
    }

    private static final String FACILITY_TYPE_PROPERTY = "PROPERTY";

    /**
     * A SQL fragment restricting {@code column} to the caller's properties, for the org-wide reads
     * that have no {@code propertyId} of their own.
     *
     * <p>Returns an empty fragment for an owner, so their queries are byte-for-byte what they were.
     * For a restricted caller with no assignments it returns a predicate that matches nothing
     * ({@code AND 1=0}) rather than an empty string — an unassigned login must see nothing, and
     * silently dropping the filter is exactly the bug this class exists to prevent.
     */
    public PropertyFilter propertyFilter(String column) {
        PropertyScope scope = scope();
        if (scope.unrestricted()) return new PropertyFilter("", List.of());
        if (scope.propertyIds().isEmpty()) return new PropertyFilter(" AND 1=0", List.of());
        String placeholders = String.join(",", scope.propertyIds().stream().map(id -> "?").toList());
        return new PropertyFilter(" AND " + column + " IN (" + placeholders + ")",
                List.copyOf(scope.propertyIds()));
    }

    /** SQL fragment plus its bind arguments, in order. */
    public record PropertyFilter(String sql, List<Object> args) {
        public boolean isEmpty() {
            return sql.isEmpty();
        }
    }
}
