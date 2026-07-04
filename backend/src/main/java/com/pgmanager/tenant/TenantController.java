package com.pgmanager.tenant;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.selfcheckin.SelfCheckinTokenService;
import com.pgmanager.tenant.dto.TenantDtos.TenantCreateRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantPatchRequest;
import com.pgmanager.tenant.dto.TenantDtos.TenantResponse;
import com.pgmanager.tenant.dto.TenantDtos.TenantUpdateRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
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
    private final TenantService tenantService;
    private final CurrentUser currentUser;
    private final SelfCheckinTokenService selfCheckinTokenService;

    @PostMapping
    ApiResponse<TenantResponse> create(@Valid @RequestBody TenantCreateRequest request) {
        return ApiResponse.ok("Tenant created", tenantService.create(currentUser.organizationId(), currentUser.userLoginId(), request));
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
        return ApiResponse.ok(tenantService.list(currentUser.organizationId()));
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
