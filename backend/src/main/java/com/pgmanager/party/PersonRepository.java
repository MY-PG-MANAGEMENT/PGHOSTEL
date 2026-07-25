package com.pgmanager.party;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface PersonRepository extends JpaRepository<Person, Long> {
    @Query(value = "SELECT COUNT(*) FROM person p " +
            "JOIN facility_party fp ON p.party_id = fp.party_id " +
            "WHERE p.mobile_number = :mobile " +
            "AND fp.organization_id = :orgId " +
            "AND fp.facility_id = :propertyId " +
            "AND fp.role_type_id = 'TENANT' " +
            "AND fp.thru_date IS NULL", nativeQuery = true)
    long countActiveTenantsByMobileAtProperty(
            @Param("mobile") String mobile,
            @Param("orgId") Long orgId,
            @Param("propertyId") Long propertyId);

    /**
     * Whether some <em>other</em> party with this mobile is currently holding a bed in the org
     * (permanent occupancy or an active temporary stay).
     *
     * <p>Used only on the rejoin path: restoring an archived tenant is normally the right
     * answer for a repeat mobile, but not while a different tenant with that same number is
     * actually living here — that is a genuine live duplicate, not someone coming back.
     * Unlike {@link #countActiveTenantsByMobileAtProperty} this looks at real bed occupancy,
     * not the TENANT membership row (which is never end-dated).
     */
    @Query(value = "SELECT COUNT(*) FROM person p " +
            "JOIN facility_party fp ON p.party_id = fp.party_id " +
            "WHERE p.mobile_number = :mobile " +
            "AND fp.organization_id = :orgId " +
            "AND fp.party_id <> :excludePartyId " +
            "AND fp.role_type_id IN ('OCCUPANT', 'TEMP_OCCUPANT') " +
            "AND fp.thru_date IS NULL", nativeQuery = true)
    long countOccupyingTenantsByMobileExcluding(
            @Param("mobile") String mobile,
            @Param("orgId") Long orgId,
            @Param("excludePartyId") Long excludePartyId);
}
