package com.pgmanager.admin;

import com.pgmanager.audit.AuditService;
import com.pgmanager.billing.MoveInBillingService;
import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.cache.CacheConfig;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.occupancy.dto.OccupancyDtos.OccupancyResponse;
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
import java.time.YearMonth;
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
    private final MoveInBillingService moveInBillingService;
    private final AuditService auditService;
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;

    // ─── CSV Templates ───────────────────────────────────────────────────────────

    @GetMapping(value = "/template/facilities", produces = "text/csv")
    ResponseEntity<String> facilitiesTemplate() {
        String csv = "property_name,property_code,floor_name,floor_number,floor_code,room_name,room_number,room_code," +
                "sharing_type,monthly_rent,security_deposit,is_ac,capacity,bed_name,bed_code\n" +
                "My PG Property,PROP-A,Ground Floor,0,FL-G,Room G01,G01,RM-G01,DOUBLE,5000,10000,false,2,Bed A,BED-G01-A\n" +
                "My PG Property,PROP-A,Ground Floor,0,FL-G,Room G01,G01,RM-G01,DOUBLE,5000,10000,false,2,Bed B,BED-G01-B\n" +
                "My PG Property,PROP-A,First Floor,1,FL-1,Room 101,101,RM-101,SINGLE,7000,14000,true,1,Bed 1,BED-101-1\n";
        return ResponseEntity.ok()
                .header("Content-Disposition", "attachment; filename=\"facilities_template.csv\"")
                .body(csv);
    }

    @GetMapping(value = "/template/tenants", produces = "text/csv")
    ResponseEntity<String> tenantsTemplate() {
        String csv = "full_name,mobile_number,email,gender,date_of_birth,aadhaar_number,occupation,permanent_address," +
                "employer_name,designation,work_address,has_vehicle," +
                "emergency_contact_name,emergency_contact_mobile,emergency_contact_relation," +
                "property_name,property_code,floor_name,floor_code,room_name,room_code,bed_name,bed_code," +
                "move_in_date,monthly_rent,ac_charges,security_deposit,expected_checkout_date,paid_up_to_month,payment_method\n" +
                "Ravi Kumar,9876543210,ravi@example.com,MALE,1998-05-20,123456789012,Software Engineer,Hyderabad," +
                "Infosys,Senior Engineer,Hitech City,true,Suresh Kumar,9876543211,Father," +
                "My PG Property,,Ground Floor,,Room G01,,Bed A,,2024-01-15,5000,0,10000,,2024-04,CASH\n" +
                "Bharat Rao,9876543299,,MALE,,,,Hyderabad,,,,false,,,,,,,,,,,BED-101-1,2024-03-01,7000,,14000,,2024-05,UPI\n" +
                "Cathy Iyer,9876543288,,FEMALE,,,,Pune,,,,false,,,,,PROP-A,,,,RM-101,Bed 1,,2024-04-01,7000,,14000,,2024-06,BANK\n" +
                "Priya Sharma,9887654321,,,,,,,,,,,,,,,,,,,,,,,,,,,,\n";
        return ResponseEntity.ok()
                .header("Content-Disposition", "attachment; filename=\"tenants_template.csv\"")
                .body(csv);
    }

    // ─── Facilities Upload ───────────────────────────────────────────────────────

    // Creates facilities + group-member links directly (not via FacilityService.link),
    // so evict the tree and every occupancy read model wholesale after the import.
    @org.springframework.cache.annotation.CacheEvict(cacheNames = {CacheConfig.FACILITY_TREE,
            CacheConfig.ROOM_SUMMARY, CacheConfig.PROPERTY_STATS, CacheConfig.VACANT_BEDS,
            CacheConfig.TEMP_STAYS}, allEntries = true)
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
                    String propertyCode = col(record, "property_code");
                    String floorName    = col(record, "floor_name");
                    String roomName     = col(record, "room_name");
                    String bedName      = col(record, "bed_name");
                    // Explicit codes — used both to match an existing node (code-wise) and,
                    // on create, as the node's facility_code (else one is auto-generated).
                    String floorCode    = col(record, "floor_code");
                    String roomCode     = col(record, "room_code");
                    String bedCode      = col(record, "bed_code");

                    if (propertyName.isEmpty() && propertyCode.isEmpty()) {
                        errors.add(new RowError(row, "property_name", "property_name or property_code required"));
                        failed++;
                        continue;
                    }

                    // Find the property (by code or name); create it under the org if missing.
                    Long propertyId = findProperty(organizationId, propertyCode, propertyName);
                    if (propertyId == null) {
                        if (propertyName.isEmpty()) {
                            errors.add(new RowError(row, "property_name", "property_name required to create a new property"));
                            failed++;
                            continue;
                        }
                        propertyId = createProperty(organizationId, propertyName, propertyCode);
                    }

                    Integer floorNum    = parseIntOrNull(col(record, "floor_number"));
                    String sharingType  = col(record, "sharing_type");
                    BigDecimal rent     = parseBdOrNull(col(record, "monthly_rent"));
                    String roomNumber   = col(record, "room_number");
                    BigDecimal roomDeposit = parseBdOrNull(col(record, "security_deposit"));
                    Integer capacity    = parseIntOrNull(col(record, "capacity"));
                    boolean isAc        = parseBool(col(record, "is_ac"));

                    Long floorId = floorName.isEmpty() ? propertyId
                            : findOrCreateChild(organizationId, propertyId, FacilityType.FLOOR, floorName, floorCode,
                                    f -> f.setFloorNumber(floorNum));

                    Long roomId = roomName.isEmpty() ? floorId
                            : findOrCreateChild(organizationId, floorId, FacilityType.ROOM, roomName, roomCode, r -> {
                                if (!sharingType.isEmpty()) r.setSharingType(sharingType);
                                if (rent != null) r.setMonthlyRent(rent);
                                if (!roomNumber.isEmpty()) r.setRoomNumber(roomNumber);
                                if (roomDeposit != null) r.setSecurityDeposit(roomDeposit);
                                if (capacity != null) r.setCapacity(capacity);
                                r.setAc(isAc);
                            });

                    if (!bedName.isEmpty()) {
                        boolean isNew = createBedIfAbsent(organizationId, roomId, bedName, bedCode);
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
                            nullIfEmpty(col(record, "employer_name")),
                            nullIfEmpty(col(record, "designation")),
                            nullIfEmpty(col(record, "work_address")),
                            parseBool(col(record, "has_vehicle")),
                            null
                    );
                    var tenant = tenantService.create(organizationId, currentUser.userLoginId(), req);

                    // Optional bed assignment — every level resolves by code (preferred) or name.
                    String propName = col(record, "property_name");
                    String propCode = col(record, "property_code");
                    String floorName = col(record, "floor_name");
                    String floorCode = col(record, "floor_code");
                    String roomName  = col(record, "room_name");
                    String roomCode  = col(record, "room_code");
                    String bedName   = col(record, "bed_name");
                    String bedCode   = col(record, "bed_code");

                    boolean hasBedCode = !bedCode.isEmpty();
                    boolean hasProp = !propName.isEmpty() || !propCode.isEmpty();
                    boolean hasRoom = !roomName.isEmpty() || !roomCode.isEmpty();
                    boolean hasNamePath = hasProp && hasRoom && !bedName.isEmpty();
                    if (hasBedCode || hasNamePath) {
                        // A bed_code resolves directly (code-wise); otherwise walk property→room→bed
                        // resolving each level by its code when present, else its name.
                        Long bedId = hasBedCode
                                ? findFacilityByCode(organizationId, FacilityType.BED, bedCode)
                                : resolveBed(organizationId, propName, propCode, floorName, floorCode, roomName, roomCode, bedName);
                        if (bedId != null) {
                            try {
                                OccupancyResponse occ = occupancyService.assign(organizationId, currentUser.userLoginId(),
                                        new BedAssignRequest(
                                                tenant.tenantId(), bedId,
                                                parseDateOrNull(col(record, "move_in_date")),
                                                parseBdOrNull(col(record, "monthly_rent")),
                                                parseBdOrNull(col(record, "security_deposit")),
                                                parseDateOrNull(col(record, "expected_checkout_date")),
                                                parseBdOrNull(col(record, "ac_charges"))));
                                // Create the move-in invoice (rent + one-time deposit) — same as the
                                // in-app assign flow, which the bulk path previously skipped.
                                moveInBillingService.bootstrapMoveIn(organizationId, tenant.tenantId(),
                                        occ.fromDate(), occ.monthlyRent(), occ.acCharges(), occ.securityDeposit());
                                // Optionally backfill already-paid historical months so imported
                                // tenants carry the same invoice + payment history as in-app ones.
                                YearMonth paidUpTo = parseMonthOrNull(col(record, "paid_up_to_month"));
                                if (paidUpTo != null) {
                                    moveInBillingService.backfillPaidHistory(organizationId, tenant.tenantId(),
                                            occ.fromDate(), occ.monthlyRent(), occ.acCharges(), occ.securityDeposit(),
                                            paidUpTo, col(record, "payment_method"));
                                }
                            } catch (BadRequestException be) {
                                errors.add(new RowError(row, "bed", "Bed assignment skipped: " + be.getMessage()));
                            }
                        } else {
                            errors.add(new RowError(row, hasBedCode ? "bed_code" : "bed_name",
                                    "Bed not found: " + (hasBedCode ? bedCode : (propName + "/" + roomName + "/" + bedName))));
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

    /** Look up a facility of the given type by its unique {@code facility_code} within an org. */
    private Long findFacilityByCode(Long orgId, String typeId, String code) {
        return jdbc.query(
                "SELECT facility_id FROM facility WHERE organization_id=? AND facility_type_id=? AND facility_code=? LIMIT 1",
                rs -> rs.next() ? rs.getLong(1) : null,
                orgId, typeId, code);
    }

    /** Look up a direct child (of {@code parentId}) of the given type by its {@code facility_code}. */
    private Long findChildByCode(Long parentId, String typeId, String code) {
        return jdbc.query(
                "SELECT f.facility_id FROM facility f " +
                "JOIN facility_group_member fgm ON fgm.child_facility_id=f.facility_id AND fgm.thru_date IS NULL " +
                "WHERE fgm.parent_facility_id=? AND f.facility_type_id=? AND f.facility_code=? LIMIT 1",
                rs -> rs.next() ? rs.getLong(1) : null,
                parentId, typeId, code);
    }

    /** Find a direct child by code when a code is given, else by name; null if neither matches. */
    private Long findChild(Long parentId, String typeId, String code, String name) {
        if (code != null && !code.isEmpty()) return findChildByCode(parentId, typeId, code);
        if (name != null && !name.isEmpty()) return findChildByName(parentId, typeId, name);
        return null;
    }

    /** Find a property in an org by code (preferred) or name. */
    private Long findProperty(Long orgId, String code, String name) {
        if (code != null && !code.isEmpty()) return findFacilityByCode(orgId, FacilityType.PROPERTY, code);
        if (name != null && !name.isEmpty()) return findFacilityByName(orgId, FacilityType.PROPERTY, name);
        return null;
    }

    /** Create a PROPERTY under the organization, linked org→property; sets the given code or auto-generates one. */
    private Long createProperty(Long orgId, String name, String code) {
        Facility f = new Facility();
        f.setOrganizationId(orgId);
        f.setFacilityTypeId(FacilityType.PROPERTY);
        f.setFacilityName(name);
        if (code != null && !code.isEmpty()) f.setFacilityCode(code);
        f = facilityRepository.save(f);
        if (f.getFacilityCode() == null || f.getFacilityCode().isEmpty()) {
            f.setFacilityCode("PROP_" + f.getFacilityId());
            f = facilityRepository.save(f);
        }
        FacilityGroupMember link = new FacilityGroupMember();
        link.setParentFacilityId(orgId);
        link.setChildFacilityId(f.getFacilityId());
        link.setFromDate(LocalDate.now());
        groupMemberRepository.save(link);
        return f.getFacilityId();
    }

    @FunctionalInterface
    private interface FacilityConfigurer {
        void configure(Facility f);
    }

    /**
     * Finds a child by code (when a code is given) or by name, otherwise creates it.
     * When {@code code} is non-empty it becomes the new node's {@code facility_code};
     * otherwise a code is auto-generated as {@code <TYPE-prefix>_<id>}.
     */
    private Long findOrCreateChild(Long orgId, Long parentId, String typeId, String name, String code, FacilityConfigurer cfg) {
        Long existing = (code != null && !code.isEmpty()) ? findChildByCode(parentId, typeId, code) : null;
        if (existing == null) existing = findChildByName(parentId, typeId, name);
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
        if (code != null && !code.isEmpty()) f.setFacilityCode(code);
        if (cfg != null) cfg.configure(f);
        f = facilityRepository.save(f);
        if (f.getFacilityCode() == null || f.getFacilityCode().isEmpty()) {
            String prefix = typeId.length() >= 3 ? typeId.substring(0, 3) : typeId;
            f.setFacilityCode(prefix + "_" + f.getFacilityId());
            f = facilityRepository.save(f);
        }
        FacilityGroupMember link = new FacilityGroupMember();
        link.setParentFacilityId(parentId);
        link.setChildFacilityId(f.getFacilityId());
        link.setFromDate(LocalDate.now());
        groupMemberRepository.save(link);
        return f.getFacilityId();
    }

    private boolean createBedIfAbsent(Long orgId, Long parentId, String bedName, String bedCode) {
        Long existing = (bedCode != null && !bedCode.isEmpty())
                ? findChildByCode(parentId, FacilityType.BED, bedCode)
                : findChildByName(parentId, FacilityType.BED, bedName);
        if (existing != null) return false;
        findOrCreateChild(orgId, parentId, FacilityType.BED, bedName, bedCode, null);
        return true;
    }

    /**
     * Resolve a bed by walking property → (floor) → room → bed, matching each level by
     * its code when supplied, otherwise by name. The bed itself is matched by name here;
     * a direct {@code bed_code} is resolved by the caller via {@link #findFacilityByCode}.
     */
    private Long resolveBed(Long orgId, String propName, String propCode,
                            String floorName, String floorCode,
                            String roomName, String roomCode, String bedName) {
        Long propId = findProperty(orgId, propCode, propName);
        if (propId == null) return null;
        boolean hasFloor = !floorCode.isEmpty() || !floorName.isEmpty();
        Long parentOfRoom = hasFloor ? findChild(propId, FacilityType.FLOOR, floorCode, floorName) : propId;
        if (parentOfRoom == null) return null;
        Long roomId = findChild(parentOfRoom, FacilityType.ROOM, roomCode, roomName);
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

    /** Parses a {@code YYYY-MM} billing month; returns null if empty or malformed. */
    private static YearMonth parseMonthOrNull(String s) {
        try { return s.isEmpty() ? null : YearMonth.parse(s); }
        catch (DateTimeParseException e) { return null; }
    }

    /** Truthy CSV values: {@code true / 1 / yes / y} (case-insensitive); everything else is false. */
    private static boolean parseBool(String s) {
        if (s == null) return false;
        String v = s.trim().toLowerCase();
        return v.equals("true") || v.equals("1") || v.equals("yes") || v.equals("y");
    }

    // ─── Response types ──────────────────────────────────────────────────────────

    public record UploadResult(int totalRows, int created, int updated, int failed, List<RowError> errors) {}

    public record RowError(int row, String column, String message) {}
}
