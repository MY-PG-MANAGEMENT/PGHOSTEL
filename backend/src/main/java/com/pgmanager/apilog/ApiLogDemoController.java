package com.pgmanager.apilog;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Sample API demonstrating the framework, plus the lookup a support engineer actually needs.
 *
 * <p>The point of the demo endpoints is what is <b>not</b> in them: no logging call, no timing
 * code, no try/catch for audit purposes. They are ordinary controller methods. Every field of the
 * log row — identity, handler name, payloads, timing, device headers, outcome — is produced by the
 * filter and interceptor around them. That is the acceptance test for "no logging code inside
 * individual controllers".
 *
 * <p>Endpoints:
 * <ul>
 *   <li>{@code POST /api/api-logs/demo/echo} — happy path. Send a body containing
 *       {@code password} and confirm the persisted {@code request_body} shows
 *       {@code ***MASKED***} while the response is unaffected.</li>
 *   <li>{@code GET /api/api-logs/demo/boom} — throws, so the row lands as {@code EXCEPTION} with
 *       {@code errorCode=BadRequestException}, and the client still receives the normal 400
 *       envelope from {@code GlobalExceptionHandler}.</li>
 *   <li>{@code GET /api/super-admin/api-logs/{requestId}} — resolves the {@code X-Request-Id} a
 *       user quotes back to the stored row.</li>
 * </ul>
 *
 * <p><b>Note the two different path prefixes</b>, and why there is no class-level
 * {@code @RequestMapping}. {@code SecurityConfig} guards {@code /api/**} with
 * {@code hasAnyRole(OWNER, PROPERTY_MANAGER, MANAGER, ACCOUNTANT, SUPPORT, VIEWER)} — a list that
 * does <em>not</em> include SUPER_ADMIN, which is granted its own branch at
 * {@code /api/super-admin/**}. So a super-admin-only endpoint sitting under {@code /api/api-logs}
 * would be rejected by the URL guard before {@code @PreAuthorize} ever ran: unreachable by the one
 * role meant to use it, and reachable by nobody else. The lookup therefore lives under the
 * super-admin prefix, and the {@code @PreAuthorize} stays as defence in depth.
 */
@RestController
@RequiredArgsConstructor
public class ApiLogDemoController {

    private final ApiRequestLogRepository repository;

    /** Ordinary endpoint. Nothing here knows it is being logged. */
    @PostMapping("/api/api-logs/demo/echo")
    ApiResponse<Map<String, Object>> echo(@Valid @RequestBody EchoRequest request) {
        return ApiResponse.ok("Echoed", Map.of(
                "username", request.username(),
                "received", true
        ));
    }

    /** Throws on purpose to demonstrate the EXCEPTION path. */
    @GetMapping("/api/api-logs/demo/boom")
    ApiResponse<Void> boom() {
        throw new BadRequestException("Demonstration failure - this request is logged as EXCEPTION");
    }

    /**
     * Support lookup by correlation id. Restricted to super admins: these rows carry request and
     * response payloads across every organization, so this is the one place in the framework where
     * an authorization guard is not optional.
     */
    @GetMapping("/api/super-admin/api-logs/{requestId}")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    ApiResponse<List<ApiRequestLog>> byRequestId(@PathVariable String requestId) {
        return ApiResponse.ok(repository.findByRequestIdOrderByIdDesc(requestId));
    }

    /**
     * {@code password} is here to be masked, not stored. Post this endpoint a real value and read
     * the row back: the body column holds the mask, and the {@code Authorization} header does too.
     */
    public record EchoRequest(
            @NotBlank String username,
            @NotBlank String password,
            String otp
    ) {}
}
