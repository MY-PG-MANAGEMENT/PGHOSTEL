package com.pgmanager.facility;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface FacilityGroupMemberRepository extends JpaRepository<FacilityGroupMember, Long> {
    List<FacilityGroupMember> findByParentFacilityIdAndThruDateIsNull(Long parentFacilityId);

    List<FacilityGroupMember> findByChildFacilityIdAndThruDateIsNull(Long childFacilityId);

    List<FacilityGroupMember> findByChildFacilityIdInAndThruDateIsNull(List<Long> childFacilityIds);

    void deleteAllByChildFacilityId(Long childFacilityId);
}
