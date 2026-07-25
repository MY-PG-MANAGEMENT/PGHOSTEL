package com.pgmanager.occupancy;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface ScheduledBedTransferRepository extends JpaRepository<ScheduledBedTransfer, Long> {

    List<ScheduledBedTransfer> findByStatusAndEffectiveDateLessThanEqual(String status, LocalDate date);

    List<ScheduledBedTransfer> findByOrganizationIdAndPartyIdAndStatus(Long organizationId, Long partyId, String status);

    Optional<ScheduledBedTransfer> findByScheduledBedTransferIdAndOrganizationId(Long id, Long organizationId);

    boolean existsByToBedFacilityIdAndStatus(Long toBedFacilityId, String status);

    // Batch variant — used before deleting a floor/room to reject the delete when a
    // scheduled transfer still points at one of its beds.
    long countByToBedFacilityIdInAndStatus(List<Long> toBedFacilityIds, String status);

    boolean existsByOrganizationIdAndPartyIdAndStatus(Long organizationId, Long partyId, String status);
}
