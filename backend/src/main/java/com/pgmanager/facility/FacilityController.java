package com.pgmanager.facility;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.dto.FacilityDtos.FacilityCreateRequest;
import com.pgmanager.facility.dto.FacilityDtos.FacilityResponse;
import com.pgmanager.facility.dto.FacilityDtos.FacilityTreeResponse;
import com.pgmanager.facility.dto.FacilityDtos.FacilityUpdateRequest;
import com.pgmanager.facility.dto.FacilityDtos.PropertyStatsResponse;
import com.pgmanager.facility.dto.FacilityDtos.RoomSharingSummary;
import com.pgmanager.pricing.PropertySharingPriceService;
import com.pgmanager.pricing.dto.SharingPriceDtos.SharingPriceResponse;
import com.pgmanager.pricing.dto.SharingPriceDtos.SharingPriceUpsertRequest;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.tenant.TenantService;
import com.pgmanager.tenant.dto.TenantDtos.TenantResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class FacilityController {
    private final FacilityService facilityService;
    private final TenantService tenantService;
    private final PropertySharingPriceService sharingPriceService;
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;

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

    @DeleteMapping("/facilities/{facilityId}")
    ApiResponse<Void> deleteBed(@PathVariable Long facilityId) {
        facilityService.deleteBed(currentUser.organizationId(), facilityId);
        return ApiResponse.ok("Bed deleted", null);
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
        return ApiResponse.ok(facilityService.bedsWithOccupancy(currentUser.organizationId(), roomId));
    }

    @GetMapping("/properties/{propertyId}/vacant-beds")
    ApiResponse<List<Map<String, Object>>> vacantBeds(@PathVariable Long propertyId) {
        Long org = currentUser.organizationId();
        String base =
                "bed.facility_id bed_id,bed.facility_name bed_name,bed.facility_code bed_code," +
                "bed.monthly_rent monthly_rent," +
                "room.facility_id room_id,room.facility_name room_name,room.room_number room_number,room.sharing_type sharing_type," +
                "floor.facility_id floor_id,floor.facility_name floor_name,floor.floor_number floor_number ";
        String joins =
                "FROM facility bed " +
                "JOIN facility_group_member bgm ON bgm.child_facility_id=bed.facility_id AND bgm.thru_date IS NULL " +
                "JOIN facility room ON room.facility_id=bgm.parent_facility_id AND room.facility_type_id='ROOM' " +
                "JOIN facility_group_member rgm ON rgm.child_facility_id=room.facility_id AND rgm.thru_date IS NULL " +
                "JOIN facility floor ON floor.facility_id=rgm.parent_facility_id AND floor.facility_type_id='FLOOR' " +
                "JOIN facility_group_member fgm ON fgm.child_facility_id=floor.facility_id AND fgm.thru_date IS NULL ";
        List<Map<String, Object>> beds = jdbc.queryForList(
                "SELECT " + base + ",CAST(NULL AS DATE) expected_checkout_date,'VACANT' bed_status " +
                joins +
                "WHERE fgm.parent_facility_id=? AND bed.facility_type_id='BED' AND bed.organization_id=? " +
                "AND NOT EXISTS (SELECT 1 FROM facility_party fp WHERE fp.facility_id=bed.facility_id " +
                "  AND fp.role_type_id='OCCUPANT' AND fp.thru_date IS NULL) " +
                "UNION ALL " +
                "SELECT " + base + ",fp.expected_checkout_date,'UPCOMING' bed_status " +
                joins +
                "JOIN facility_party fp ON fp.facility_id=bed.facility_id AND fp.role_type_id='OCCUPANT' AND fp.thru_date IS NULL " +
                "WHERE fgm.parent_facility_id=? AND bed.facility_type_id='BED' AND bed.organization_id=? " +
                "AND fp.expected_checkout_date IS NOT NULL AND fp.expected_checkout_date>=CURDATE() " +
                "ORDER BY bed_status,floor_number,room_number,bed_id",
                propertyId, org, propertyId, org);
        return ApiResponse.ok(beds);
    }

    @GetMapping("/properties/{propertyId}/room-summary")
    ApiResponse<List<RoomSharingSummary>> roomSummary(@PathVariable Long propertyId) {
        return ApiResponse.ok(facilityService.getRoomSummary(currentUser.organizationId(), propertyId));
    }

    @GetMapping("/properties/{propertyId}/stats")
    ApiResponse<PropertyStatsResponse> propertyStats(@PathVariable Long propertyId) {
        return ApiResponse.ok(facilityService.propertyStats(currentUser.organizationId(), propertyId));
    }

    @GetMapping("/properties/{propertyId}/tenants")
    ApiResponse<List<TenantResponse>> tenantsByProperty(@PathVariable Long propertyId) {
        return ApiResponse.ok(tenantService.listByProperty(currentUser.organizationId(), propertyId));
    }

    @GetMapping("/properties/{propertyId}/sharing-prices")
    ApiResponse<List<SharingPriceResponse>> sharingPrices(@PathVariable Long propertyId) {
        return ApiResponse.ok(sharingPriceService.list(currentUser.organizationId(), propertyId));
    }

    @PutMapping("/properties/{propertyId}/sharing-prices")
    ApiResponse<List<SharingPriceResponse>> updateSharingPrices(
            @PathVariable Long propertyId,
            @Valid @RequestBody SharingPriceUpsertRequest req) {
        return ApiResponse.ok(sharingPriceService.upsert(currentUser.organizationId(), propertyId, req));
    }

    @GetMapping("/properties/{propertyId}/sharing-prices/{sharingType}")
    ApiResponse<SharingPriceResponse> sharingPriceByType(
            @PathVariable Long propertyId,
            @PathVariable String sharingType) {
        return ApiResponse.ok(sharingPriceService.getByType(currentUser.organizationId(), propertyId, sharingType)
                .orElseThrow(() -> new NotFoundException("No price configured for this sharing type")));
    }
}
