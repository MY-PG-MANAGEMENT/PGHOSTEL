package com.pgmanager.complaint;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Owner/staff-facing complaint triage. Org scope is derived from the JWT. Tenants use the
 * tenant portal ({@code /api/tenant/complaints}) instead.
 */
@RestController
@RequestMapping("/api/complaints")
@RequiredArgsConstructor
@PreAuthorize("hasAnyRole('OWNER','PROPERTY_MANAGER','MANAGER','SUPPORT')")
public class ComplaintController {

    private final ComplaintService complaintService;
    private final CurrentUser currentUser;

    @GetMapping
    ApiResponse<List<Map<String, Object>>> list(@RequestParam(required = false) Long propertyId,
                                                 @RequestParam(required = false) String status) {
        return ApiResponse.ok(complaintService.listForOwner(currentUser.organizationId(), propertyId, status));
    }

    @GetMapping("/{complaintId}")
    ApiResponse<Map<String, Object>> detail(@PathVariable Long complaintId) {
        return ApiResponse.ok(complaintService.detail(currentUser.organizationId(), complaintId, null));
    }

    @PatchMapping("/{complaintId}/status")
    ApiResponse<Map<String, Object>> updateStatus(@PathVariable Long complaintId,
                                                   @Valid @RequestBody StatusRequest request) {
        return ApiResponse.ok("Complaint updated",
                complaintService.updateStatus(currentUser.organizationId(), currentUser.userLoginId(),
                        complaintId, request.status(), request.note()));
    }

    public record StatusRequest(@NotBlank String status, String note) {}
}
