package com.pgmanager.complaint;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface ComplaintRepository extends JpaRepository<Complaint, Long> {
    List<Complaint> findByOrganizationIdOrderByCreatedAtDesc(Long organizationId);

    List<Complaint> findByOrganizationIdAndStatusOrderByCreatedAtDesc(Long organizationId, String status);

    List<Complaint> findByOrganizationIdAndPartyIdOrderByCreatedAtDesc(Long organizationId, Long partyId);

    Optional<Complaint> findByComplaintIdAndOrganizationId(Long complaintId, Long organizationId);

    Optional<Complaint> findByComplaintIdAndOrganizationIdAndPartyId(Long complaintId, Long organizationId, Long partyId);
}
