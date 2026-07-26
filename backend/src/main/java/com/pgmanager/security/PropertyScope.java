package com.pgmanager.security;

import java.util.Collections;
import java.util.Set;

/**
 * Which properties the current request is allowed to touch.
 *
 * <p>Two shapes only, and the distinction matters at every call site:
 * <ul>
 *   <li>{@link #unrestricted()} — an OWNER. Queries run org-wide exactly as before, so nothing
 *       about the owner experience changes.</li>
 *   <li>{@link #restrictedTo(Set)} — a PROPERTY_MANAGER (or any non-owner staff login). Every read
 *       and write must be confined to this set.</li>
 * </ul>
 *
 * <p>An <b>empty</b> restricted set is meaningful and deliberately <b>not</b> the same as
 * unrestricted: a staff login with no assignments yet sees nothing. Failing closed is the only
 * safe default — the opposite mistake hands a brand-new login the whole organization.
 */
public record PropertyScope(boolean unrestricted, Set<Long> propertyIds) {

    private static final PropertyScope UNRESTRICTED = new PropertyScope(true, Set.of());

    public static PropertyScope unrestrictedScope() {
        return UNRESTRICTED;
    }

    public static PropertyScope restrictedTo(Set<Long> propertyIds) {
        return new PropertyScope(false, Collections.unmodifiableSet(propertyIds));
    }

    /** True when this scope permits nothing at all — a staff login with no assignment. */
    public boolean isEmpty() {
        return !unrestricted && propertyIds.isEmpty();
    }

    public boolean allows(Long propertyId) {
        return unrestricted || (propertyId != null && propertyIds.contains(propertyId));
    }

    /**
     * The single property to fall back to when a restricted caller supplies no {@code propertyId}.
     *
     * <p>This is what lets the whole existing API surface work unchanged for the common case — one
     * manager, one property: an endpoint that took an optional {@code propertyId} simply receives
     * theirs. Null when unrestricted (no substitution wanted) or when the caller holds several
     * properties, in which case the query has to filter on the full set instead.
     */
    public Long soleProperty() {
        if (unrestricted || propertyIds.size() != 1) return null;
        return propertyIds.iterator().next();
    }
}
