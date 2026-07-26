package com.pgmanager.manager;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Owner-only management of property-scoped staff logins.
 *
 * <p><b>OWNER only, deliberately.</b> Every method is guarded to OWNER rather than the usual
 * OWNER/PROPERTY_MANAGER/MANAGER list: a manager who could create manager logins, or edit their own
 * assignments, could grant themselves the properties they were denied. This is the one surface in
 * the application where PROPERTY_MANAGER must be excluded, because it is the surface that defines
 * what PROPERTY_MANAGER means.
 */
@RestController
@RequestMapping("/api/managers")
@RequiredArgsConstructor
@PreAuthorize("hasRole('OWNER')")
public class PropertyManagerController {

    private final PropertyManagerService service;
    private final CurrentUser currentUser;

    @GetMapping
    ApiResponse<List<Map<String, Object>>> list() {
        return ApiResponse.ok(service.list(currentUser.organizationId()));
    }

    /** Returns the generated username and temporary password — the only time the password is visible. */
    @PostMapping
    ApiResponse<Map<String, Object>> create(@Valid @RequestBody CreateManagerRequest request) {
        return ApiResponse.ok("Manager login created",
                service.create(currentUser.organizationId(), request.fullName(), request.mobileNumber(),
                        request.propertyIds() == null ? Set.of() : request.propertyIds()));
    }

    @PutMapping("/{userLoginId}/properties")
    ApiResponse<Void> setProperties(@PathVariable Long userLoginId,
                                    @RequestBody PropertiesRequest request) {
        service.setProperties(currentUser.organizationId(), userLoginId,
                request.propertyIds() == null ? Set.of() : request.propertyIds());
        return ApiResponse.ok("Assigned properties updated", null);
    }

    @PatchMapping("/{userLoginId}/status")
    ApiResponse<Void> setStatus(@PathVariable Long userLoginId, @RequestBody Map<String, Object> body) {
        Object raw = body.get("active");
        boolean active = Boolean.TRUE.equals(raw) || "true".equalsIgnoreCase(String.valueOf(raw));
        service.setStatus(currentUser.organizationId(), userLoginId, active);
        return ApiResponse.ok("Manager login " + (active ? "activated" : "deactivated"), null);
    }

    @PostMapping("/{userLoginId}/reset-password")
    ApiResponse<Map<String, Object>> resetPassword(@PathVariable Long userLoginId) {
        String temp = service.resetPassword(currentUser.organizationId(), userLoginId);
        return ApiResponse.ok("Password reset", Map.of("temporaryPassword", temp));
    }

    public record CreateManagerRequest(
            @NotBlank String fullName,
            @NotBlank @Pattern(regexp = "\\d{10}", message = "Mobile number must be 10 digits") String mobileNumber,
            Set<Long> propertyIds
    ) {}

    public record PropertiesRequest(Set<Long> propertyIds) {}
}
