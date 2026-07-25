package com.pgmanager.facility;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface FacilityGroupMemberRepository extends JpaRepository<FacilityGroupMember, Long> {
    List<FacilityGroupMember> findByParentFacilityIdAndThruDateIsNull(Long parentFacilityId);

    // Batch variant: all active child links for a set of parents in one query — lets the
    // facility tree/stats walks resolve a whole level at once instead of per-parent.
    List<FacilityGroupMember> findByParentFacilityIdInAndThruDateIsNull(List<Long> parentFacilityIds);

    List<FacilityGroupMember> findByChildFacilityIdAndThruDateIsNull(Long childFacilityId);

    List<FacilityGroupMember> findByChildFacilityIdInAndThruDateIsNull(List<Long> childFacilityIds);

    void deleteAllByChildFacilityId(Long childFacilityId);

    void deleteAllByChildFacilityIdIn(List<Long> childFacilityIds);

    void deleteAllByParentFacilityIdIn(List<Long> parentFacilityIds);
}
