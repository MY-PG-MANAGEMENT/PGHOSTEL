package com.pgmanager.facility;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.security.CurrentUser;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/inventory")
@RequiredArgsConstructor
public class InventoryController {
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;

    @GetMapping("/properties/{propertyId}")
    ApiResponse<Map<String, Object>> property(@PathVariable Long propertyId) {
        Map<String, Object> property = facility(propertyId, "PROPERTY");
        Map<String, Object> result = new LinkedHashMap<>(property);
        result.put("counts", jdbc.queryForMap("SELECT " +
                        "COUNT(DISTINCT CASE WHEN f.facility_type_id='ROOM' THEN f.facility_id END) total_rooms," +
                        "COUNT(DISTINCT CASE WHEN f.facility_type_id='BED' THEN f.facility_id END) total_beds," +
                        "COUNT(DISTINCT CASE WHEN f.facility_type_id='BED' AND fp.facility_party_id IS NOT NULL THEN f.facility_id END) occupied_beds " +
                        "FROM facility_group_member floors JOIN facility_group_member descendants ON descendants.parent_facility_id=floors.child_facility_id " +
                        "LEFT JOIN facility_group_member bed_links ON bed_links.parent_facility_id=descendants.child_facility_id " +
                        "JOIN facility f ON f.facility_id IN (descendants.child_facility_id,bed_links.child_facility_id) " +
                        "LEFT JOIN facility_party fp ON fp.facility_id=f.facility_id AND fp.role_type_id='OCCUPANT' AND fp.thru_date IS NULL " +
                        "WHERE floors.parent_facility_id=? AND floors.thru_date IS NULL", propertyId));
        result.put("amenities", amenities(propertyId).data());
        result.put("media", Map.of("storageEnabled", false, "items", List.of()));
        return ApiResponse.ok(result);
    }

    @GetMapping("/rooms/{roomId}")
    ApiResponse<Map<String, Object>> room(@PathVariable Long roomId) {
        Map<String, Object> room = facility(roomId, "ROOM");
        Map<String, Object> result = new LinkedHashMap<>(room);
        result.put("beds", jdbc.queryForList("SELECT b.facility_id,b.facility_name,b.status,b.monthly_rent,b.security_deposit," +
                        "p.party_id,p.full_name,CASE WHEN fp.facility_party_id IS NULL THEN 'VACANT' ELSE 'OCCUPIED' END occupancy_status " +
                        "FROM facility_group_member gm JOIN facility b ON b.facility_id=gm.child_facility_id " +
                        "LEFT JOIN facility_party fp ON fp.facility_id=b.facility_id AND fp.role_type_id='OCCUPANT' AND fp.thru_date IS NULL " +
                        "LEFT JOIN person p ON p.party_id=fp.party_id WHERE gm.parent_facility_id=? AND gm.thru_date IS NULL ORDER BY b.facility_name", roomId));
        result.put("media", Map.of("storageEnabled", false, "items", List.of()));
        return ApiResponse.ok(result);
    }

    @GetMapping("/beds/available")
    ApiResponse<List<Map<String, Object>>> availableBeds() {
        return ApiResponse.ok(jdbc.queryForList("SELECT b.facility_id,b.facility_name,b.monthly_rent,b.security_deposit,r.facility_name room_name " +
                        "FROM facility b JOIN facility_group_member gm ON gm.child_facility_id=b.facility_id AND gm.thru_date IS NULL " +
                        "JOIN facility r ON r.facility_id=gm.parent_facility_id LEFT JOIN facility_party fp ON fp.facility_id=b.facility_id " +
                        "AND fp.role_type_id='OCCUPANT' AND fp.thru_date IS NULL WHERE b.organization_id=? AND b.facility_type_id='BED' " +
                        "AND b.status='ACTIVE' AND fp.facility_party_id IS NULL ORDER BY r.facility_name,b.facility_name", currentUser.organizationId()));
    }

    @GetMapping("/facilities/{facilityId}/amenities")
    ApiResponse<List<Map<String, Object>>> amenities(@PathVariable Long facilityId) {
        assertFacility(facilityId);
        return ApiResponse.ok(jdbc.queryForList("SELECT a.amenity_type_id,a.name,a.icon_code,COALESCE(fa.available,FALSE) available,fa.details " +
                "FROM amenity_type a LEFT JOIN facility_amenity fa ON fa.amenity_type_id=a.amenity_type_id AND fa.facility_id=? " +
                "WHERE a.active=TRUE ORDER BY a.name", facilityId));
    }

    @PutMapping("/facilities/{facilityId}/amenities")
    ApiResponse<List<Map<String, Object>>> updateAmenities(@PathVariable Long facilityId, @RequestBody Map<String, Boolean> values) {
        assertFacility(facilityId);
        values.forEach((type, available) -> jdbc.update("INSERT INTO facility_amenity(facility_id,amenity_type_id,available) VALUES(?,?,?) " +
                "ON DUPLICATE KEY UPDATE available=VALUES(available)", facilityId, type, available));
        return amenities(facilityId);
    }

    private Map<String, Object> facility(Long facilityId, String type) {
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT facility_id,facility_type_id,facility_name,status,description,room_number,floor_number," +
                        "sharing_type,capacity,monthly_rent,security_deposit,size_sq_ft,available_from FROM facility " +
                        "WHERE facility_id=? AND organization_id=? AND facility_type_id=?", facilityId, currentUser.organizationId(), type);
        if (rows.isEmpty()) throw new NotFoundException(type + " not found");
        return rows.getFirst();
    }

    private void assertFacility(Long facilityId) {
        Long count = jdbc.queryForObject("SELECT COUNT(*) FROM facility WHERE facility_id=? AND organization_id=?", Long.class,
                facilityId, currentUser.organizationId());
        if (count == null || count == 0) throw new NotFoundException("Facility not found");
    }
}

