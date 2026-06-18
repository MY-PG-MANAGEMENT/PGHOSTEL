package com.pgmanager.facility;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.facility.dto.FacilityDtos.FacilityCreateRequest;
import com.pgmanager.facility.dto.FacilityDtos.FacilityResponse;
import com.pgmanager.facility.dto.FacilityDtos.FacilityTreeResponse;
import com.pgmanager.facility.dto.FacilityDtos.FacilityUpdateRequest;
import com.pgmanager.security.CurrentUser;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class FacilityController {
    private final FacilityService facilityService;
    private final CurrentUser currentUser;

    @GetMapping("/facilities/tree")
    ApiResponse<FacilityTreeResponse> tree() {
        return ApiResponse.ok(facilityService.tree(currentUser.organizationId()));
    }

    @PostMapping("/facilities")
    ApiResponse<FacilityResponse> create(@Valid @RequestBody FacilityCreateRequest request) {
        return ApiResponse.ok("Facility created", facilityService.toResponse(facilityService.createChild(currentUser.organizationId(), request)));
    }

    @PutMapping("/facilities/{facilityId}")
    ApiResponse<FacilityResponse> update(@PathVariable Long facilityId, @Valid @RequestBody FacilityUpdateRequest request) {
        return ApiResponse.ok(facilityService.toResponse(facilityService.update(currentUser.organizationId(), facilityId, request)));
    }

    @GetMapping("/properties/{propertyId}/floors")
    ApiResponse<List<FacilityResponse>> floors(@PathVariable Long propertyId) {
        return ApiResponse.ok(facilityService.children(currentUser.organizationId(), propertyId));
    }

    @GetMapping("/floors/{floorId}/rooms")
    ApiResponse<List<FacilityResponse>> rooms(@PathVariable Long floorId) {
        return ApiResponse.ok(facilityService.children(currentUser.organizationId(), floorId));
    }

    @GetMapping("/rooms/{roomId}/beds")
    ApiResponse<List<FacilityResponse>> beds(@PathVariable Long roomId) {
        return ApiResponse.ok(facilityService.children(currentUser.organizationId(), roomId));
    }
}
