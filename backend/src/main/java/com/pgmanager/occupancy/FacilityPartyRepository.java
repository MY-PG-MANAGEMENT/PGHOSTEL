package com.pgmanager.occupancy;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface FacilityPartyRepository extends JpaRepository<FacilityParty, Long> {
    Optional<FacilityParty> findByOrganizationIdAndPartyIdAndRoleTypeIdAndThruDateIsNull(Long organizationId, Long partyId, String roleTypeId);

    Optional<FacilityParty> findByOrganizationIdAndFacilityIdAndRoleTypeIdAndThruDateIsNull(Long organizationId, Long facilityId, String roleTypeId);

    List<FacilityParty> findByOrganizationIdAndPartyIdOrderByFromDateDesc(Long organizationId, Long partyId);

    List<FacilityParty> findByOrganizationIdAndRoleTypeIdAndThruDateIsNull(Long organizationId, String roleTypeId);

    long countByOrganizationIdAndRoleTypeIdAndThruDateIsNull(Long organizationId, String roleTypeId);
}
