package com.pgmanager.admin;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityGroupMember;
import com.pgmanager.facility.FacilityGroupMemberRepository;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.occupancy.OccupancyService;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedAssignRequest;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.tenant.TenantService;
import com.pgmanager.tenant.dto.TenantDtos.TenantCreateRequest;
import lombok.RequiredArgsConstructor;
import org.apache.commons.csv.CSVFormat;
import org.apache.commons.csv.CSVParser;
import org.apache.commons.csv.CSVRecord;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;

@RestController
@RequestMapping("/api/super-admin/upload")
@RequiredArgsConstructor
public class BulkUploadController {

    private final FacilityRepository facilityRepository;
    private final FacilityGroupMemberRepository groupMemberRepository;
    private final FacilityPartyRepository facilityPartyRepository;
    private final OccupancyService occupancyService;
    private final TenantService tenantService;
    private final AuditService auditService;
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;

    // ─── CSV Templates ───────────────────────────────────────────────────────────

    @GetMapping(value = "/template/facilities", produces = "text/csv")
    ResponseEntity<String> facilitiesTemplate() {
        String csv = "property_name,floor_name,floor_number,room_name,room_number,sharing_type,monthly_rent,bed_name\n" +
                "My PG Property,Ground Floor,0,Room G01,G01,DOUBLE,5000,Bed A\n" +
                "My PG Property,Ground Floor,0,Room G01,G01,DOUBLE,5000,Bed B\n" +
                "My PG Property,First Floor,1,Room 101,101,SINGLE,7000,Bed 1\n";
        return ResponseEntity.ok()
                .header("Content-Disposition", "attachment; filename=\"facilities_template.csv\"")
                .body(csv);
    }

    @GetMapping(value = "/template/tenants", produces = "text/csv")
    ResponseEntity<String> tenantsTemplate() {
        String csv = "full_name,mobile_number,email,gender,date_of_birth,aadhaar_number,occupation," +
                "permanent_address,emergency_contact_name,emergency_contact_mobile,emergency_contact_relation," +
                "property_name,floor_name,room_name,bed_name,move_in_date,monthly_rent,security_deposit\n" +
                "Ravi Kumar,9876543210,ravi@example.com,MALE,1998-05-20,123456789012,Software Engineer," +
                "Hyderabad,Suresh Kumar,9876543211,Father,My PG Property,Ground Floor,Room G01,Bed A,2024-01-15,5000,10000\n" +
                "Priya Sharma,9887654321,,,,,,Chennai,,,,,,,,2024-02-01,,\n";
        return ResponseEntity.ok()
                .header("Content-Disposition", "attachment; filename=\"tenants_template.csv\"")
                .body(csv);
    }

    // ─── Facilities Upload ───────────────────────────────────────────────────────

    @PostMapping("/facilities/{organizationId}")
    ApiResponse<UploadResult> uploadFacilities(@PathVariable Long organizationId,
                                               @RequestParam("file") MultipartFile file) throws IOException {
        int row = 0, created = 0, updated = 0, failed = 0;
        List<RowError> errors = new ArrayList<>();

        try (CSVParser parser = CSVParser.parse(file.getInputStream(), StandardCharsets.UTF_8,
                CSVFormat.DEFAULT.builder()
                        .setHeader().setSkipHeaderRecord(true)
                        .setIgnoreEmptyLines(true).setTrim(true).build())) {

            for (CSVRecord record : parser) {
                row++;
                try {
                    String propertyName = col(record, "property_name");
                    String floorName    = col(record, "floor_name");
                    String roomName     = col(record, "room_name");
                    String bedName      = col(record, "bed_name");

                    if (propertyName.isEmpty()) {
                        errors.add(new RowError(row, "property_name", "Required"));
                        failed++;
                        continue;
                    }

                    Long propertyId = findFacilityByName(organizationId, FacilityType.PROPERTY, propertyName);
                    if (propertyId == null) {
                        errors.add(new RowError(row, "property_name", "Property not found: " + propertyName));
                        failed++;
                        continue;
                    }

                    Integer floorNum    = parseIntOrNull(col(record, "floor_number"));
                    String sharingType  = col(record, "sharing_type");
                    BigDecimal rent     = parseBdOrNull(col(record, "monthly_rent"));
                    String roomNumber   = col(record, "room_number");

                    Long floorId = floorName.isEmpty() ? propertyId
                            : findOrCreateChild(organizationId, propertyId, FacilityType.FLOOR, floorName,
                                    f -> f.setFloorNumber(floorNum));

                    Long roomId = roomName.isEmpty() ? floorId
                            : findOrCreateChild(organizationId, floorId, FacilityType.ROOM, roomName, r -> {
                                if (!sharingType.isEmpty()) r.setSharingType(sharingType);
                                if (rent != null) r.setMonthlyRent(rent);
                                if (!roomNumber.isEmpty()) r.setRoomNumber(roomNumber);
                            });

                    if (!bedName.isEmpty()) {
                        boolean isNew = createBedIfAbsent(organizationId, roomId, bedName);
                        if (isNew) created++;
                        else updated++;
                    } else {
                        updated++;
                    }
                } catch (Exception e) {
                    errors.add(new RowError(row, "—", e.getMessage()));
                    failed++;
                }
            }
        }

        saveJob(organizationId, "FACILITIES", row, created, updated, failed);
        return ApiResponse.ok("Upload complete", new UploadResult(row, created, updated, failed, errors));
    }

    // ─── Tenants Upload ──────────────────────────────────────────────────────────

    @PostMapping("/tenants/{organizationId}")
    ApiResponse<UploadResult> uploadTenants(@PathVariable Long organizationId,
                                            @RequestParam("file") MultipartFile file) throws IOException {
        int row = 0, created = 0, updated = 0, failed = 0;
        List<RowError> errors = new ArrayList<>();

        try (CSVParser parser = CSVParser.parse(file.getInputStream(), StandardCharsets.UTF_8,
                CSVFormat.DEFAULT.builder()
                        .setHeader().setSkipHeaderRecord(true)
                        .setIgnoreEmptyLines(true).setTrim(true).build())) {

            for (CSVRecord record : parser) {
                row++;
                try {
                    String fullName = col(record, "full_name");
                    String mobile   = col(record, "mobile_number");

                    if (fullName.isEmpty()) {
                        errors.add(new RowError(row, "full_name", "Required"));
                        failed++;
                        continue;
                    }
                    if (!mobile.matches("^[0-9]{10}$")) {
                        errors.add(new RowError(row, "mobile_number", "Must be 10 digits"));
                        failed++;
                        continue;
                    }

                    TenantCreateRequest req = new TenantCreateRequest(
                            fullName, mobile,
                            nullIfEmpty(col(record, "email")),
                            nullIfEmpty(col(record, "gender")),
                            parseDateOrNull(col(record, "date_of_birth")),
                            nullIfEmpty(col(record, "aadhaar_number")),
                            nullIfEmpty(col(record, "occupation")),
                            nullIfEmpty(col(record, "permanent_address")),
                            nullIfEmpty(col(record, "emergency_contact_name")),
                            nullIfEmpty(col(record, "emergency_contact_mobile")),
                            nullIfEmpty(col(record, "emergency_contact_relation")),
                            null, null, null,
                            null
                    );
                    var tenant = tenantService.create(organizationId, currentUser.userLoginId(), req);

                    // Optional bed assignment
                    String propName = col(record, "property_name");
                    String floorName = col(record, "floor_name");
                    String roomName  = col(record, "room_name");
                    String bedName   = col(record, "bed_name");
                    if (!propName.isEmpty() && !roomName.isEmpty() && !bedName.isEmpty()) {
                        Long bedId = resolveBed(organizationId, propName, floorName, roomName, bedName);
                        if (bedId != null) {
                            try {
                                occupancyService.assign(organizationId, currentUser.userLoginId(),
                                        new BedAssignRequest(
                                                tenant.tenantId(), bedId,
                                                parseDateOrNull(col(record, "move_in_date")),
                                                parseBdOrNull(col(record, "monthly_rent")),
                                                parseBdOrNull(col(record, "security_deposit")),
                                                null));
                            } catch (BadRequestException be) {
                                errors.add(new RowError(row, "bed_name", "Bed assignment skipped: " + be.getMessage()));
                            }
                        } else {
                            errors.add(new RowError(row, "bed_name", "Bed not found: " + bedName));
                        }
                    }

                    created++;
                } catch (Exception e) {
                    errors.add(new RowError(row, "—", e.getMessage()));
                    failed++;
                }
            }
        }

        saveJob(organizationId, "TENANTS", row, created, updated, failed);
        return ApiResponse.ok("Upload complete", new UploadResult(row, created, updated, failed, errors));
    }

    // ─── Facility helpers ────────────────────────────────────────────────────────

    private Long findFacilityByName(Long orgId, String typeId, String name) {
        return jdbc.query(
                "SELECT facility_id FROM facility WHERE organization_id=? AND facility_type_id=? AND LOWER(facility_name)=LOWER(?) LIMIT 1",
                rs -> rs.next() ? rs.getLong(1) : null,
                orgId, typeId, name);
    }

    private Long findChildByName(Long parentId, String typeId, String name) {
        return jdbc.query(
                "SELECT f.facility_id FROM facility f " +
                "JOIN facility_group_member fgm ON fgm.child_facility_id=f.facility_id AND fgm.thru_date IS NULL " +
                "WHERE fgm.parent_facility_id=? AND f.facility_type_id=? AND LOWER(f.facility_name)=LOWER(?) LIMIT 1",
                rs -> rs.next() ? rs.getLong(1) : null,
                parentId, typeId, name);
    }

    @FunctionalInterface
    private interface FacilityConfigurer {
        void configure(Facility f);
    }

    private Long findOrCreateChild(Long orgId, Long parentId, String typeId, String name, FacilityConfigurer cfg) {
        Long existing = findChildByName(parentId, typeId, name);
        if (existing != null) {
            if (cfg != null) {
                facilityRepository.findById(existing).ifPresent(f -> { cfg.configure(f); facilityRepository.save(f); });
            }
            return existing;
        }
        Facility f = new Facility();
        f.setOrganizationId(orgId);
        f.setFacilityTypeId(typeId);
        f.setFacilityName(name);
        if (cfg != null) cfg.configure(f);
        f = facilityRepository.save(f);
        String prefix = typeId.length() >= 3 ? typeId.substring(0, 3) : typeId;
        f.setFacilityCode(prefix + "_" + f.getFacilityId());
        facilityRepository.save(f);
        FacilityGroupMember link = new FacilityGroupMember();
        link.setParentFacilityId(parentId);
        link.setChildFacilityId(f.getFacilityId());
        link.setFromDate(LocalDate.now());
        groupMemberRepository.save(link);
        return f.getFacilityId();
    }

    private boolean createBedIfAbsent(Long orgId, Long parentId, String bedName) {
        if (findChildByName(parentId, FacilityType.BED, bedName) != null) return false;
        findOrCreateChild(orgId, parentId, FacilityType.BED, bedName, null);
        return true;
    }

    private Long resolveBed(Long orgId, String propName, String floorName, String roomName, String bedName) {
        Long propId = findFacilityByName(orgId, FacilityType.PROPERTY, propName);
        if (propId == null) return null;
        Long parentOfRoom = floorName.isEmpty() ? propId : findChildByName(propId, FacilityType.FLOOR, floorName);
        if (parentOfRoom == null) return null;
        Long roomId = findChildByName(parentOfRoom, FacilityType.ROOM, roomName);
        if (roomId == null) return null;
        return findChildByName(roomId, FacilityType.BED, bedName);
    }

    private void saveJob(Long orgId, String type, int total, int created, int updated, int failed) {
        jdbc.update(
                "INSERT INTO bulk_upload_job(organization_id,upload_type,total_rows,created_rows,updated_rows,failed_rows,performed_by_user_login_id,created_at) " +
                "VALUES(?,?,?,?,?,?,?,?)",
                orgId, type, total, created, updated, failed, currentUser.userLoginId(), LocalDateTime.now());
    }

    // ─── Parse helpers ───────────────────────────────────────────────────────────

    private static String col(CSVRecord r, String name) {
        try { String v = r.get(name); return v == null ? "" : v.trim(); }
        catch (IllegalArgumentException e) { return ""; }
    }

    private static String nullIfEmpty(String s) { return (s == null || s.isEmpty()) ? null : s; }

    private static Integer parseIntOrNull(String s) {
        try { return s.isEmpty() ? null : Integer.parseInt(s); }
        catch (NumberFormatException e) { return null; }
    }

    private static BigDecimal parseBdOrNull(String s) {
        try { return s.isEmpty() ? null : new BigDecimal(s); }
        catch (NumberFormatException e) { return null; }
    }

    private static LocalDate parseDateOrNull(String s) {
        try { return s.isEmpty() ? null : LocalDate.parse(s); }
        catch (DateTimeParseException e) { return null; }
    }

    // ─── Response types ──────────────────────────────────────────────────────────

    public record UploadResult(int totalRows, int created, int updated, int failed, List<RowError> errors) {}

    public record RowError(int row, String column, String message) {}
}
