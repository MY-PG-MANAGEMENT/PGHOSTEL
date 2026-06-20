package com.pgmanager.tenant;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.occupancy.OccupancyService;
import com.pgmanager.occupancy.dto.OccupancyDtos.BedAssignRequest;
import com.pgmanager.occupancy.dto.OccupancyDtos.CheckoutRequest;
import com.pgmanager.security.CurrentUser;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/tenants/{partyId}")
@RequiredArgsConstructor
public class TenantLifecycleController {
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;
    private final OccupancyService occupancyService;

    @GetMapping("/emergency-contacts")
    ApiResponse<List<Map<String, Object>>> contacts(@PathVariable Long partyId) {
        assertTenant(partyId);
        return ApiResponse.ok(jdbc.queryForList("SELECT * FROM emergency_contact WHERE organization_id=? AND party_id=? ORDER BY is_primary DESC",
                currentUser.organizationId(), partyId));
    }

    @PutMapping("/emergency-contacts")
    @Transactional
    ApiResponse<List<Map<String, Object>>> saveContacts(@PathVariable Long partyId, @RequestBody List<@Valid ContactRequest> contacts) {
        assertTenant(partyId);
        if (contacts.stream().filter(ContactRequest::primary).count() > 1) throw new BadRequestException("Only one primary emergency contact is allowed");
        jdbc.update("DELETE FROM emergency_contact WHERE organization_id=? AND party_id=?", currentUser.organizationId(), partyId);
        contacts.forEach(c -> jdbc.update("INSERT INTO emergency_contact(organization_id,party_id,contact_name,relationship_type_id,mobile_number," +
                        "alternate_number,address,is_primary,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)", currentUser.organizationId(), partyId,
                c.contactName(), c.relationship(), c.mobileNumber(), c.alternateNumber(), c.address(), c.primary(), LocalDateTime.now(), LocalDateTime.now()));
        return contacts(partyId);
    }

    @GetMapping("/employment")
    ApiResponse<List<Map<String, Object>>> employment(@PathVariable Long partyId) {
        assertTenant(partyId);
        return ApiResponse.ok(jdbc.queryForList("SELECT * FROM tenant_employment WHERE organization_id=? AND party_id=? ORDER BY from_date DESC",
                currentUser.organizationId(), partyId));
    }

    @PutMapping("/employment")
    @Transactional
    ApiResponse<Map<String, Object>> saveEmployment(@PathVariable Long partyId, @Valid @RequestBody EmploymentRequest request) {
        assertTenant(partyId);
        jdbc.update("UPDATE tenant_employment SET thru_date=? WHERE organization_id=? AND party_id=? AND thru_date IS NULL",
                request.fromDate().minusDays(1), currentUser.organizationId(), partyId);
        jdbc.update("INSERT INTO tenant_employment(organization_id,party_id,company_name,designation,employee_id,monthly_salary,work_email,office_address," +
                        "from_date,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)", currentUser.organizationId(), partyId, request.companyName(),
                request.designation(), request.employeeId(), request.monthlySalary(), request.workEmail(), request.officeAddress(), request.fromDate(),
                LocalDateTime.now(), LocalDateTime.now());
        return ApiResponse.ok(jdbc.queryForMap("SELECT * FROM tenant_employment WHERE tenant_employment_id=LAST_INSERT_ID()"));
    }

    @GetMapping("/documents")
    ApiResponse<Map<String, Object>> documents(@PathVariable Long partyId) {
        assertTenant(partyId);
        return ApiResponse.ok(Map.of("storageEnabled", false, "items", jdbc.queryForList("SELECT identity_document_id,document_type_id,document_number," +
                "verification_status,verified_at,expires_on FROM identity_document WHERE organization_id=? AND party_id=?",
                currentUser.organizationId(), partyId)));
    }

    @PostMapping("/documents")
    ApiResponse<Map<String, Object>> saveDocumentMetadata(@PathVariable Long partyId, @Valid @RequestBody DocumentRequest request) {
        assertTenant(partyId);
        jdbc.update("INSERT INTO identity_document(organization_id,party_id,document_type_id,document_number,verification_status,expires_on,created_at,updated_at) " +
                        "VALUES(?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE document_number=VALUES(document_number),expires_on=VALUES(expires_on),updated_at=VALUES(updated_at)",
                currentUser.organizationId(), partyId, request.documentTypeId(), request.documentNumber(), "PENDING", request.expiresOn(),
                LocalDateTime.now(), LocalDateTime.now());
        return documents(partyId);
    }

    @PostMapping("/admissions")
    @Transactional
    ApiResponse<Map<String, Object>> createAdmission(@PathVariable Long partyId, @Valid @RequestBody AdmissionRequest request) {
        assertTenant(partyId);
        Long org = currentUser.organizationId();
        Long bedCount = jdbc.queryForObject("SELECT COUNT(*) FROM facility WHERE facility_id=? AND organization_id=? AND facility_type_id='BED' AND status='ACTIVE'",
                Long.class, request.bedFacilityId(), org);
        if (bedCount == null || bedCount == 0) throw new NotFoundException("Available bed not found");
        jdbc.update("INSERT INTO admission(organization_id,party_id,bed_facility_id,move_in_date,monthly_rent,security_deposit,advance_amount," +
                        "notice_period_days,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?, 'DRAFT',?,?)", org, partyId, request.bedFacilityId(),
                request.moveInDate(), request.monthlyRent(), request.securityDeposit(), request.advanceAmount(), request.noticePeriodDays(),
                LocalDateTime.now(), LocalDateTime.now());
        Long admissionId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        String agreementNumber = "AGR-" + org + "-" + admissionId;
        jdbc.update("INSERT INTO agreement(organization_id,admission_id,agreement_number,from_date,terms,status,created_at,updated_at) " +
                        "VALUES(?,?,?,?,?,'DRAFT',?,?)", org, admissionId, agreementNumber, request.moveInDate(), request.terms(), LocalDateTime.now(), LocalDateTime.now());
        return ApiResponse.ok(Map.of("admissionId", admissionId, "agreementNumber", agreementNumber, "status", "DRAFT"));
    }

    @PostMapping("/admissions/{admissionId}/sign")
    @Transactional
    ApiResponse<Map<String, Object>> sign(@PathVariable Long partyId, @PathVariable Long admissionId) {
        assertTenant(partyId);
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT * FROM admission WHERE admission_id=? AND organization_id=? AND party_id=? AND status='DRAFT' FOR UPDATE",
                admissionId, currentUser.organizationId(), partyId);
        if (rows.isEmpty()) throw new BadRequestException("Admission is not available for signing");
        Map<String, Object> admission = rows.getFirst();
        LocalDate moveIn = ((java.sql.Date) admission.get("move_in_date")).toLocalDate();
        Long bedId = ((Number) admission.get("bed_facility_id")).longValue();
        occupancyService.assign(currentUser.organizationId(), currentUser.userLoginId(), new BedAssignRequest(partyId, bedId, moveIn));
        jdbc.update("UPDATE admission SET status='ACTIVE',updated_at=?,version=version+1 WHERE admission_id=?", LocalDateTime.now(), admissionId);
        jdbc.update("UPDATE agreement SET status='SIGNED',signed_at=?,updated_at=?,version=version+1 WHERE admission_id=?",
                LocalDateTime.now(), LocalDateTime.now(), admissionId);
        jdbc.update("INSERT INTO billing_account(organization_id,party_id,admission_id,currency_code,status,advance_balance,created_at,updated_at) " +
                        "VALUES(?,?,?,'INR','ACTIVE',?,?,?)", currentUser.organizationId(), partyId, admissionId,
                admission.get("advance_amount"), LocalDateTime.now(), LocalDateTime.now());
        return ApiResponse.ok(Map.of("admissionId", admissionId, "status", "ACTIVE", "bedFacilityId", bedId));
    }

    @GetMapping("/agreements")
    ApiResponse<List<Map<String, Object>>> agreements(@PathVariable Long partyId) {
        assertTenant(partyId);
        return ApiResponse.ok(jdbc.queryForList("SELECT a.agreement_id,a.agreement_number,a.from_date,a.thru_date,a.terms,a.status,a.signed_at " +
                "FROM agreement a JOIN admission d ON d.admission_id=a.admission_id WHERE a.organization_id=? AND d.party_id=? ORDER BY a.from_date DESC",
                currentUser.organizationId(), partyId));
    }

    @PostMapping("/checkout")
    @Transactional
    ApiResponse<Map<String, Object>> checkout(@PathVariable Long partyId, @Valid @RequestBody CheckoutRequestBody request) {
        assertTenant(partyId);
        List<Map<String, Object>> admissions = jdbc.queryForList("SELECT * FROM admission WHERE organization_id=? AND party_id=? AND status='ACTIVE' FOR UPDATE",
                currentUser.organizationId(), partyId);
        if (admissions.isEmpty()) throw new NotFoundException("Active admission not found");
        Map<String, Object> admission = admissions.getFirst();
        Long admissionId = ((Number) admission.get("admission_id")).longValue();
        occupancyService.checkout(currentUser.organizationId(), currentUser.userLoginId(), new CheckoutRequest(partyId, request.checkoutDate()));
        BigDecimal refundable = decimal(admission.get("security_deposit")).subtract(request.pendingDues()).subtract(request.damageCharges()).subtract(request.otherDeductions());
        if (refundable.signum() < 0) refundable = BigDecimal.ZERO;
        jdbc.update("UPDATE admission SET status='CHECKED_OUT',updated_at=?,version=version+1 WHERE admission_id=?", LocalDateTime.now(), admissionId);
        jdbc.update("UPDATE agreement SET status='TERMINATED',thru_date=?,updated_at=?,version=version+1 WHERE admission_id=?",
                request.checkoutDate(), LocalDateTime.now(), admissionId);
        jdbc.update("INSERT INTO checkout(organization_id,admission_id,checkout_date,pending_dues,damage_charges,other_deductions,refundable_deposit,status,created_at,updated_at) " +
                        "VALUES(?,?,?,?,?,?,?,'PENDING',?,?)", currentUser.organizationId(), admissionId, request.checkoutDate(), request.pendingDues(),
                request.damageCharges(), request.otherDeductions(), refundable, LocalDateTime.now(), LocalDateTime.now());
        return ApiResponse.ok(Map.of("admissionId", admissionId, "refundableDeposit", refundable, "status", "PENDING_SETTLEMENT"));
    }

    @PostMapping("/checkout/{checkoutId}/settle")
    ApiResponse<Map<String, Object>> settle(@PathVariable Long partyId, @PathVariable Long checkoutId, @Valid @RequestBody SettlementRequest request) {
        assertTenant(partyId);
        int updated = jdbc.update("UPDATE checkout c JOIN admission a ON a.admission_id=c.admission_id SET c.status='SETTLED',c.refund_method='CASH'," +
                        "c.refund_reference=?,c.settled_at=?,c.updated_at=? WHERE c.checkout_id=? AND c.organization_id=? AND a.party_id=? AND c.status='PENDING'",
                request.referenceNumber(), LocalDateTime.now(), LocalDateTime.now(), checkoutId, currentUser.organizationId(), partyId);
        if (updated == 0) throw new BadRequestException("Checkout is not available for settlement");
        return ApiResponse.ok(Map.of("checkoutId", checkoutId, "status", "SETTLED", "refundMethod", "CASH"));
    }

    private void assertTenant(Long partyId) {
        Long count = jdbc.queryForObject("SELECT COUNT(*) FROM facility_party WHERE organization_id=? AND party_id=? AND role_type_id='TENANT' AND thru_date IS NULL",
                Long.class, currentUser.organizationId(), partyId);
        if (count == null || count == 0) throw new NotFoundException("Tenant not found in current organization");
    }

    private BigDecimal decimal(Object value) { return value instanceof BigDecimal d ? d : new BigDecimal(value.toString()); }

    public record ContactRequest(@NotBlank String contactName, @NotBlank String relationship, @NotBlank String mobileNumber,
                                 String alternateNumber, String address, boolean primary) {}
    public record EmploymentRequest(String companyName, String designation, String employeeId, BigDecimal monthlySalary,
                                    String workEmail, String officeAddress, @NotNull LocalDate fromDate) {}
    public record DocumentRequest(@NotBlank String documentTypeId, String documentNumber, LocalDate expiresOn) {}
    public record AdmissionRequest(@NotNull Long bedFacilityId, @NotNull LocalDate moveInDate,
                                   @NotNull @DecimalMin("0") BigDecimal monthlyRent, @NotNull @DecimalMin("0") BigDecimal securityDeposit,
                                   @NotNull @DecimalMin("0") BigDecimal advanceAmount, int noticePeriodDays, String terms) {}
    public record CheckoutRequestBody(@NotNull LocalDate checkoutDate, @NotNull @DecimalMin("0") BigDecimal pendingDues,
                                      @NotNull @DecimalMin("0") BigDecimal damageCharges, @NotNull @DecimalMin("0") BigDecimal otherDeductions) {}
    public record SettlementRequest(String referenceNumber) {}
}
