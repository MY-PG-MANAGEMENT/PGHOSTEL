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

    boolean existsByOrganizationIdAndPartyIdAndStatus(Long organizationId, Long partyId, String status);
}
