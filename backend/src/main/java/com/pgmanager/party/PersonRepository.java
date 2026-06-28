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
}
