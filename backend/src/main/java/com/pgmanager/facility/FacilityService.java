package com.pgmanager.facility;

import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.dto.FacilityDtos.FacilityCreateRequest;
import com.pgmanager.facility.dto.FacilityDtos.FacilityResponse;
import com.pgmanager.facility.dto.FacilityDtos.FacilityTreeResponse;
import com.pgmanager.facility.dto.FacilityDtos.FacilityUpdateRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;

@Service
@RequiredArgsConstructor
public class FacilityService {
    private final FacilityRepository facilityRepository;
    private final FacilityGroupMemberRepository groupMemberRepository;

    @Transactional
    public Facility createChild(Long organizationId, FacilityCreateRequest request) {
        Facility parent = facilityRepository.findById(request.parentFacilityId())
                .orElseThrow(() -> new NotFoundException("Parent facility not found"));
        if (!parent.getFacilityId().equals(organizationId) && !organizationId.equals(parent.getOrganizationId())) {
            throw new BadRequestException("Parent facility is outside current organization");
        }

        Facility facility = new Facility();
        facility.setOrganizationId(organizationId);
        facility.setFacilityTypeId(request.facilityTypeId());
        facility.setFacilityName(request.facilityName());
        facility.setSharingType(request.sharingType());
        facility.setCapacity(request.capacity());
        facility = facilityRepository.save(facility);

        link(parent.getFacilityId(), facility.getFacilityId());
        return facility;
    }

    @Transactional
    public Facility update(Long organizationId, Long facilityId, FacilityUpdateRequest request) {
        Facility facility = facilityRepository.findByFacilityIdAndOrganizationId(facilityId, organizationId)
                .orElseThrow(() -> new NotFoundException("Facility not found"));
        facility.setFacilityName(request.facilityName());
        facility.setSharingType(request.sharingType());
        facility.setCapacity(request.capacity());
        if (request.status() != null) {
            facility.setStatus(request.status());
        }
        return facility;
    }

    @Transactional(readOnly = true)
    public FacilityTreeResponse tree(Long organizationId) {
        Facility org = facilityRepository.findById(organizationId)
                .orElseThrow(() -> new NotFoundException("Organization not found"));
        return toTree(org);
    }

    @Transactional(readOnly = true)
    public List<FacilityResponse> children(Long organizationId, Long parentFacilityId) {
        Facility parent = facilityRepository.findById(parentFacilityId)
                .orElseThrow(() -> new NotFoundException("Parent facility not found"));
        if (!parent.getFacilityId().equals(organizationId) && !organizationId.equals(parent.getOrganizationId())) {
            throw new BadRequestException("Parent facility is outside current organization");
        }
        return groupMemberRepository.findByParentFacilityIdAndThruDateIsNull(parentFacilityId).stream()
                .map(member -> facilityRepository.findById(member.getChildFacilityId()).orElseThrow())
                .map(this::toResponse)
                .toList();
    }

    public void link(Long parentFacilityId, Long childFacilityId) {
        FacilityGroupMember member = new FacilityGroupMember();
        member.setParentFacilityId(parentFacilityId);
        member.setChildFacilityId(childFacilityId);
        member.setFromDate(LocalDate.now());
        groupMemberRepository.save(member);
    }

    public FacilityResponse toResponse(Facility facility) {
        return new FacilityResponse(
                facility.getFacilityId(),
                facility.getOrganizationId(),
                facility.getFacilityTypeId(),
                facility.getFacilityName(),
                facility.getStatus(),
                facility.getSharingType(),
                facility.getCapacity()
        );
    }

    private FacilityTreeResponse toTree(Facility facility) {
        List<FacilityTreeResponse> children = groupMemberRepository.findByParentFacilityIdAndThruDateIsNull(facility.getFacilityId()).stream()
                .map(member -> facilityRepository.findById(member.getChildFacilityId()).orElseThrow())
                .map(this::toTree)
                .toList();
        return new FacilityTreeResponse(
                facility.getFacilityId(),
                facility.getFacilityTypeId(),
                facility.getFacilityName(),
                facility.getStatus(),
                facility.getSharingType(),
                facility.getCapacity(),
                children
        );
    }
}
