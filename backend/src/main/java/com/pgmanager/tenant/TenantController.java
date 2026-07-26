package com.pgmanager.tenant;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.security.PropertyAccessGuard;
import com.pgmanager.selfcheckin.SelfCheckinTokenService;
import com.pgmanager.tenant.dto.TenantDtos.TenantArchiveRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantCreateRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantPatchRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantResponse;
import com.pgmanager.tenant.dto.TenantDtos.TenantUpdateRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/tenants")
@RequiredArgsConstructor
public class TenantController {
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(TenantController.class);

    /** Archiving / restoring a tenant is a management action — read-only roles are excluded. */
    private static final String ARCHIVE_ROLES = "hasAnyRole('OWNER','PROPERTY_MANAGER','MANAGER')";

    private final TenantService tenantService;
    private final TenantArchiveService tenantArchiveService;
    private final CurrentUser currentUser;
    private final SelfCheckinTokenService selfCheckinTokenService;
    private final TenantLoginPolicy tenantLoginPolicy;
    private final TenantLoginService tenantLoginService;
    private final PropertyAccessGuard propertyAccessGuard;

    @PostMapping
    ApiResponse<TenantResponse> create(@Valid @RequestBody TenantCreateRequest request) {
        Long orgId = currentUser.organizationId();
        log.info("POST /api/tenants received: org={}, mobile={}, propertyId={}", orgId, request.mobileNumber(), request.propertyId());
        TenantResponse created = tenantService.create(orgId, currentUser.userLoginId(), request);
        log.info("POST /api/tenants done: tenantId={} (org={})", created.tenantId(), orgId);
        return ApiResponse.ok("Tenant created", created);
    }

    /** Whether Tenant Login is enabled for the caller's org (drives the owner "Generate Logins" affordance). */
    @GetMapping("/login-feature")
    ApiResponse<Map<String, Boolean>> loginFeature() {
        return ApiResponse.ok(Map.of("enabled", tenantLoginPolicy.enabled(currentUser.organizationId())));
    }

    /**
     * Owner action: generate tenant login accounts for existing tenants without one
     * (skips inactive, checked-out, and already-provisioned tenants). Returns a summary.
     */
    @PostMapping("/generate-logins")
    ApiResponse<Map<String, Object>> generateLogins() {
        return ApiResponse.ok("Tenant logins generated",
                tenantLoginService.generateForOrganization(currentUser.organizationId()));
    }

    @GetMapping("/self-checkin-link")
    ApiResponse<Map<String, String>> selfCheckinLink(
            @RequestParam(name = "propertyId", required = false) Long propertyId) {
        long orgId = currentUser.organizationId();
        long prop = propertyId != null ? propertyId : 0L;
        return ApiResponse.ok(Map.of(
                "url", selfCheckinTokenService.linkFor(orgId, prop),
                "path", selfCheckinTokenService.pathFor(orgId, prop)));
    }

    @GetMapping
    ApiResponse<List<TenantResponse>> list() {
        List<TenantResponse> tenants = tenantService.list(currentUser.organizationId());
        log.info("GET /api/tenants: org={} returned {} tenants", currentUser.organizationId(), tenants.size());
        return ApiResponse.ok(tenants);
    }

    /**
     * Archived ("deleted") tenants for the org — hidden from the normal tenant lists but
     * fully intact. Optionally scoped to a property and filtered by name / mobile.
     */
    @GetMapping("/archived")
    ApiResponse<List<Map<String, Object>>> archived(
            @RequestParam(name = "propertyId", required = false) Long propertyId,
            @RequestParam(name = "q", required = false) String q) {
        List<Map<String, Object>> items = tenantArchiveService.list(currentUser.organizationId(), propertyId, q);
        log.info("GET /api/tenants/archived: org={} propertyId={} returned {} archived tenants",
                currentUser.organizationId(), propertyId, items.size());
        return ApiResponse.ok(items);
    }

    /**
     * "Delete" one tenant = move them to the archive. Nothing is removed: their party,
     * person, occupancy history, invoices and payments all stay, they just stop showing in
     * the tenant lists. Rejected while the tenant still holds a bed — check them out first.
     */
    @DeleteMapping("/{partyId}")
    @PreAuthorize(ARCHIVE_ROLES)
    ApiResponse<Map<String, Object>> archive(@PathVariable Long partyId) {
        Long orgId = currentUser.organizationId();
        tenantArchiveService.archiveOne(orgId, currentUser.userLoginId(), partyId);
        log.info("DELETE /api/tenants/{}: archived (org={})", partyId, orgId);
        return ApiResponse.ok("Tenant deleted", Map.of("archived", 1));
    }

    /** Bulk "delete" from the Inactive list's multi-select. Returns a per-reason summary. */
    @PostMapping("/archive")
    @PreAuthorize(ARCHIVE_ROLES)
    ApiResponse<Map<String, Object>> archiveBulk(@Valid @RequestBody TenantArchiveRequest request) {
        return ApiResponse.ok("Tenants deleted",
                tenantArchiveService.archiveMany(currentUser.organizationId(), currentUser.userLoginId(),
                        request.partyIds()));
    }

    /**
     * Brings an archived tenant back (Inactive, no bed) with their full history. The Add
     * Tenant form does this automatically when a rejoining tenant's mobile matches; this is
     * the explicit Restore action on the Archived Tenants screen.
     */
    @PostMapping("/{partyId}/restore")
    @PreAuthorize(ARCHIVE_ROLES)
    ApiResponse<TenantResponse> restore(@PathVariable Long partyId,
            @RequestParam(name = "propertyId", required = false) Long propertyId) {
        return ApiResponse.ok("Tenant restored",
                tenantService.restoreFromArchive(currentUser.organizationId(), currentUser.userLoginId(),
                        partyId, propertyId, null));
    }

    @GetMapping("/{partyId}")
    ApiResponse<TenantResponse> get(@PathVariable Long partyId) {
        return ApiResponse.ok(tenantService.get(currentUser.organizationId(), partyId));
    }

    @PutMapping("/{partyId}")
    ApiResponse<TenantResponse> update(@PathVariable Long partyId, @Valid @RequestBody TenantUpdateRequest request) {
        return ApiResponse.ok(tenantService.update(currentUser.organizationId(), partyId, request));
    }

    @PatchMapping("/{partyId}")
    ApiResponse<TenantResponse> patch(@PathVariable Long partyId, @Valid @RequestBody TenantPatchRequest request) {
        return ApiResponse.ok(tenantService.patch(currentUser.organizationId(), partyId, request));
    }
}
