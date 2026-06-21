package com.pgmanager.facility;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface FacilityGroupMemberRepository extends JpaRepository<FacilityGroupMember, Long> {
    List<FacilityGroupMember> findByParentFacilityIdAndThruDateIsNull(Long parentFacilityId);

    List<FacilityGroupMember> findByChildFacilityIdAndThruDateIsNull(Long childFacilityId);

    void deleteAllByChildFacilityId(Long childFacilityId);
}
