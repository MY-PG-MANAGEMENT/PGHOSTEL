package com.pgmanager.auth;

import com.pgmanager.auth.TenantAuthService.TenantAuthResult;
import com.pgmanager.auth.dto.AuthDtos.TenantLoginRequest;
import com.pgmanager.common.api.ApiResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Public tenant auth endpoint. Sits under {@code /api/auth/**} (permitAll in SecurityConfig).
 * Token refresh reuses the shared {@code POST /api/auth/refresh}.
 */
@RestController
@RequestMapping("/api/auth/tenant")
@RequiredArgsConstructor
public class TenantAuthController {

    private final TenantAuthService tenantAuthService;

    @PostMapping("/login")
    ApiResponse<TenantAuthResult> login(@Valid @RequestBody TenantLoginRequest request) {
        TenantAuthResult result = tenantAuthService.login(request);
        return ApiResponse.ok(result.needsOrgSelection() ? "Select your organization" : "Logged in", result);
    }
}
