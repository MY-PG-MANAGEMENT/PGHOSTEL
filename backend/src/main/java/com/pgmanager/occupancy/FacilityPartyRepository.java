package com.pgmanager.occupancy;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface FacilityPartyRepository extends JpaRepository<FacilityParty, Long> {
    Optional<FacilityParty> findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(Long organizationId, Long partyId, String roleTypeId);

    Optional<FacilityParty> findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(Long organizationId, Long facilityId, String roleTypeId);

    List<FacilityParty> findByOrganizationIdAndPartyIdOrderByFromDateDesc(Long organizationId, Long partyId);

    List<FacilityParty> findByOrganizationIdAndPartyIdAndRoleTypeId(Long organizationId, Long partyId, String roleTypeId);

    List<FacilityParty> findByOrganizationIdAndRoleTypeIdAndThruDateIsNull(Long organizationId, String roleTypeId);

    long countByOrganizationIdAndRoleTypeIdAndThruDateIsNull(Long organizationId, String roleTypeId);

    @Query("SELECT fp FROM FacilityParty fp WHERE fp.organizationId = :orgId AND fp.facilityId = :facilityId AND fp.roleTypeId = :roleTypeId AND fp.thruDate IS NULL")
    List<FacilityParty> findTenantsAtFacility(@Param("orgId") Long organizationId, @Param("facilityId") Long facilityId, @Param("roleTypeId") String roleTypeId);

    // Scoped to facilityId = organizationId so there is always at most one row per tenant,
    // even when property-level TENANT rows exist for the same partyId.
    @Query("SELECT fp FROM FacilityParty fp WHERE fp.organizationId = :orgId AND fp.facilityId = :orgId AND fp.partyId = :partyId AND fp.roleTypeId = :roleTypeId AND fp.thruDate IS NULL")
    Optional<FacilityParty> findOrgMembership(@Param("orgId") Long organizationId, @Param("partyId") Long partyId, @Param("roleTypeId") String roleTypeId);

    @Query("SELECT fp FROM FacilityParty fp WHERE fp.organizationId = :orgId AND fp.partyId IN :partyIds AND fp.roleTypeId = :role AND fp.thruDate IS NULL")
    List<FacilityParty> findActiveOccupantsByPartyIds(@Param("orgId") Long orgId, @Param("partyIds") List<Long> partyIds, @Param("role") String role);

    // All rows (active + historical) for a batch of parties in one role — used by the
    // property-scoped tenant list to decide membership without a per-tenant query.
    @Query("SELECT fp FROM FacilityParty fp WHERE fp.organizationId = :orgId AND fp.partyId IN :partyIds AND fp.roleTypeId = :role")
    List<FacilityParty> findByOrganizationIdAndPartyIdInAndRoleTypeId(@Param("orgId") Long orgId, @Param("partyIds") List<Long> partyIds, @Param("role") String role);

    boolean existsByOrganizationIdAndFacilityIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(
            Long organizationId, Long facilityId, Long partyId, String roleTypeId);

    // Batch occupancy lookups for a set of beds — used by facility bed-grid / stats screens
    // to avoid one query per bed. Covered by idx_fp_org_facility_role_thru (V23).
    List<FacilityParty> findByOrganizationIdAndFacilityIdInAndRoleTypeIdInAndThruDateIsNull(
            Long organizationId, List<Long> facilityIds, List<String> roleTypeIds);

    long countByOrganizationIdAndFacilityIdInAndRoleTypeIdAndThruDateIsNull(
            Long organizationId, List<Long> facilityIds, String roleTypeId);

    void deleteAllByFacilityId(Long facilityId);

    void deleteAllByFacilityIdIn(List<Long> facilityIds);
}
