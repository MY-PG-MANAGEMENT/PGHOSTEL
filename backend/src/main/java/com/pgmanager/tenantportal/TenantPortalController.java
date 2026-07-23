package com.pgmanager.tenantportal;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Tenant self-service portal. Guarded to ROLE_TENANT by SecurityConfig ({@code /api/tenant/**}).
 * Organization and tenant identity come only from the JWT via {@link CurrentUser} — never from
 * the request — enforcing strict per-tenant, per-org isolation.
 */
@RestController
@RequestMapping("/api/tenant")
@RequiredArgsConstructor
public class TenantPortalController {

    private final TenantPortalService portal;
    private final CurrentUser currentUser;

    private Long org() { return currentUser.organizationId(); }
    private Long me() { return currentUser.partyId(); }

    @GetMapping("/dashboard")
    ApiResponse<Map<String, Object>> dashboard() {
        return ApiResponse.ok(portal.dashboard(org(), me()));
    }

    @GetMapping("/profile")
    ApiResponse<Map<String, Object>> profile() {
        return ApiResponse.ok(portal.profile(org(), me()));
    }

    @GetMapping("/payments")
    ApiResponse<Map<String, Object>> payments() {
        return ApiResponse.ok(portal.payments(org(), me()));
    }

    @PostMapping("/change-password")
    ApiResponse<Void> changePassword(@Valid @RequestBody ChangePasswordRequest request) {
        portal.changePassword(currentUser.userLoginId(), request.oldPassword(), request.newPassword());
        return ApiResponse.ok("Password changed", null);
    }

    // ─── Complaints ─────────────────────────────────────────────────────────────
    @GetMapping("/complaints")
    ApiResponse<List<Map<String, Object>>> complaints() {
        return ApiResponse.ok(portal.listComplaints(org(), me()));
    }

    @GetMapping("/complaints/{complaintId}")
    ApiResponse<Map<String, Object>> complaint(@PathVariable Long complaintId) {
        return ApiResponse.ok(portal.complaintDetail(org(), me(), complaintId));
    }

    @PostMapping("/complaints")
    ApiResponse<Map<String, Object>> raiseComplaint(@Valid @RequestBody ComplaintRequest request) {
        return ApiResponse.ok("Complaint submitted",
                portal.raiseComplaint(org(), me(), request.category(), request.title(),
                        request.description(), request.priority()));
    }

    // ─── Notices ────────────────────────────────────────────────────────────────
    @GetMapping("/notices")
    ApiResponse<List<Map<String, Object>>> notices() {
        return ApiResponse.ok(portal.listNotices(org(), me()));
    }

    @GetMapping("/notices/{noticeId}")
    ApiResponse<Map<String, Object>> notice(@PathVariable Long noticeId) {
        return ApiResponse.ok(portal.noticeDetail(org(), me(), noticeId));
    }

    // ─── Notifications ────────────────────────────────────────────────────────────
    @GetMapping("/notifications")
    ApiResponse<List<Map<String, Object>>> notifications(@RequestParam(defaultValue = "50") int limit) {
        return ApiResponse.ok(portal.listNotifications(me(), limit));
    }

    @PostMapping("/notifications/{notificationId}/read")
    ApiResponse<Void> markRead(@PathVariable Long notificationId) {
        portal.markNotificationRead(me(), notificationId);
        return ApiResponse.ok("Marked read", null);
    }

    public record ChangePasswordRequest(@NotBlank String oldPassword,
                                         @NotBlank @Size(min = 6, message = "must be at least 6 characters") String newPassword) {}

    public record ComplaintRequest(@NotBlank String category,
                                   @NotBlank @Size(max = 160) String title,
                                   @NotBlank @Size(max = 2000) String description,
                                   String priority) {}
}
