package com.pgmanager.notice;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * Owner/manager-facing notice authoring. Tenants read notices via {@code /api/tenant/notices}.
 */
@RestController
@RequestMapping("/api/notices")
@RequiredArgsConstructor
@PreAuthorize("hasAnyRole('OWNER','PROPERTY_MANAGER','MANAGER')")
public class NoticeController {

    private final NoticeService noticeService;
    private final CurrentUser currentUser;

    @GetMapping
    ApiResponse<List<Map<String, Object>>> list(@RequestParam(required = false) Long propertyId) {
        return ApiResponse.ok(noticeService.listForOwner(currentUser.organizationId(), propertyId));
    }

    @PostMapping
    ApiResponse<Map<String, Object>> create(@Valid @RequestBody NoticeRequest request) {
        Notice n = noticeService.create(currentUser.organizationId(), currentUser.userLoginId(),
                request.propertyId(), request.type(), request.title(), request.body(), request.expiresAt());
        return ApiResponse.ok("Notice published", NoticeService.toMap(n));
    }

    @PatchMapping("/{noticeId}")
    ApiResponse<Void> deactivate(@PathVariable Long noticeId) {
        noticeService.deactivate(currentUser.organizationId(), noticeId);
        return ApiResponse.ok("Notice deactivated", null);
    }

    public record NoticeRequest(Long propertyId, String type, @NotBlank String title,
                                @NotBlank String body, LocalDateTime expiresAt) {}
}
