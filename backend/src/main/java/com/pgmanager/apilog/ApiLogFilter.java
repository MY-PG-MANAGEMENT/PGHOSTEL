package com.pgmanager.apilog;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.security.SecurityProperties;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.async.AsyncRequestTimeoutException;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

/**
 * The outermost link in the chain: starts the clock, wraps request and response so both bodies
 * are re-readable, and — whatever happens downstream — assembles exactly one log row.
 *
 * <p><b>Why this runs outside the Spring Security chain.</b> Order is
 * {@code SecurityProperties.DEFAULT_FILTER_ORDER - 10}, i.e. ahead of
 * {@code springSecurityFilterChain}. That placement is load-bearing: a 401 from the
 * authentication entry point or a 403 from an authorization decision is written and committed
 * <em>inside</em> the security chain and never reaches a filter registered after it. Sitting
 * outside is the only way UNAUTHORIZED and FORBIDDEN rows exist at all — and rejected traffic is
 * precisely what you want logged. The cost of that placement is that
 * {@code SecurityContextHolder} is already cleared on the way out, which is why identity comes
 * from {@link ApiLogHandlerInterceptor} instead.
 *
 * <p><b>Everything is extracted on the request thread.</b> The entity is fully built here, then
 * handed to the publisher as an immutable payload. Touching the {@code HttpServletRequest} from
 * the async persistence thread would be a use-after-free: the container recycles request objects
 * the moment the response completes, so the org id you read there may belong to the next caller.
 * This is the single most important rule in the whole design.
 */
@Component
@Order(ApiLogFilter.ORDER)
public class ApiLogFilter extends OncePerRequestFilter {

    /** Ahead of Spring Security so rejected requests are still logged. */
    public static final int ORDER = SecurityProperties.DEFAULT_FILTER_ORDER - 10;

    private static final Logger log = LoggerFactory.getLogger(ApiLogFilter.class);
    private static final String REQUEST_ID_HEADER = "X-Request-Id";

    private final ApiLogProperties properties;
    private final SensitiveDataMasker masker;
    private final ApiLogWriter writer;
    private final ObjectMapper objectMapper;

    public ApiLogFilter(ApiLogProperties properties, SensitiveDataMasker masker,
                        ApiLogWriter writer, ObjectMapper objectMapper) {
        this.properties = properties;
        this.masker = masker;
        this.writer = writer;
        this.objectMapper = objectMapper;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !properties.isEnabled();
    }

    /**
     * Async dispatches must not be logged twice. The row is written on the final dispatch, when
     * the response is actually complete.
     */
    @Override
    protected boolean shouldNotFilterAsyncDispatch() {
        return false;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {

        String requestId = resolveRequestId(request);
        ApiLogContext context = ApiLogContext.create(request, requestId, System.nanoTime());
        LocalDateTime startTime = LocalDateTime.now();

        ApiLogRequestWrapper wrappedRequest = properties.isStoreRequestBody()
                ? new ApiLogRequestWrapper(request, properties) : null;
        ApiLogResponseWrapper wrappedResponse = properties.isStoreResponseBody()
                ? new ApiLogResponseWrapper(response, properties) : null;

        HttpServletRequest effectiveRequest = wrappedRequest != null ? wrappedRequest : request;
        HttpServletResponse effectiveResponse = wrappedResponse != null ? wrappedResponse : response;

        // Correlation id goes back to the client so a user-reported failure maps to a row.
        effectiveResponse.setHeader(REQUEST_ID_HEADER, requestId);

        Exception failure = null;
        try {
            chain.doFilter(effectiveRequest, effectiveResponse);
        } catch (Exception ex) {
            // Reached only when nothing downstream handled it (the advice normally does). Record
            // it, log the row, then rethrow untouched so the client still gets the original
            // error — the logger must never change the response contract.
            failure = ex;
            throw ex;
        } finally {
            if (request.isAsyncStarted()) {
                // Response is not finished; the final dispatch will come back through this filter.
                if (wrappedResponse != null) copyBodyQuietly(wrappedResponse);
            } else {
                try {
                    persist(request, effectiveResponse, wrappedRequest, wrappedResponse,
                            context, startTime, failure);
                } catch (Exception loggingFailure) {
                    // A logging defect must never become a client-visible failure.
                    log.error("API log assembly failed for {} {}", request.getMethod(),
                            request.getRequestURI(), loggingFailure);
                } finally {
                    // Non-negotiable: without this the client receives an empty body.
                    if (wrappedResponse != null) copyBodyQuietly(wrappedResponse);
                }
            }
        }
    }

    private void copyBodyQuietly(ApiLogResponseWrapper wrappedResponse) {
        try {
            wrappedResponse.copyBodyToResponse();
        } catch (IOException ex) {
            log.warn("Failed to flush cached response body: {}", ex.getMessage());
        }
    }

    private void persist(HttpServletRequest request, HttpServletResponse response,
                         ApiLogRequestWrapper wrappedRequest, ApiLogResponseWrapper wrappedResponse,
                         ApiLogContext context, LocalDateTime startTime, Exception failure) {

        long elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - context.getStartNanos());
        LocalDateTime endTime = LocalDateTime.now();
        int statusCode = response.getStatus();

        if (failure != null && !context.isExceptionRecorded()) {
            context.setExceptionRecorded(true);
            context.setErrorCode(failure.getClass().getSimpleName());
            context.setErrorMessage(failure.getMessage());
        }

        ApiRequestLog entry = ApiRequestLog.builder()
                .organizationId(context.getOrganizationId())
                .userLoginId(context.getUserLoginId())
                .tenantId(context.getTenantId())
                .requestId(context.getRequestId())
                .sessionId(sessionId(request))
                .requestUri(truncate(request.getRequestURI(), 512))
                .httpMethod(truncate(request.getMethod(), 10))
                .controllerName(truncate(context.getControllerName(), 160))
                .methodName(truncate(context.getMethodName(), 120))
                .requestBody(payload(wrappedRequest == null ? null : wrappedRequest.bodyAsText()))
                .queryParameters(queryParameters(request))
                .requestHeaders(headers(request))
                .responseStatusCode(statusCode)
                .responseBody(payload(wrappedResponse == null ? null : wrappedResponse.bodyAsText()))
                .requestStartTime(startTime)
                .requestEndTime(endTime)
                .executionTimeMs(elapsedMs)
                .platform(header(request, "Platform", 40))
                .appVersion(header(request, "App-Version", 40))
                .buildNumber(header(request, "Build-Number", 40))
                .deviceModel(header(request, "Device-Model", 120))
                .manufacturer(header(request, "Manufacturer", 80))
                .osName(header(request, "OS-Name", 40))
                .osVersion(header(request, "OS-Version", 40))
                .clientIpAddress(clientIp(request))
                .networkType(header(request, "Network-Type", 40))
                .userAgent(header(request, "User-Agent", 512))
                .status(resolveStatus(statusCode, context, failure))
                .errorCode(truncate(context.getErrorCode(), 120))
                .errorMessage(truncate(context.getErrorMessage(), 1000))
                .createdDate(endTime)
                .build();

        writer.write(entry);
    }

    /**
     * Status precedence: transport-level rejections first, then a recorded exception, then a
     * plain error status. 401/403 outrank EXCEPTION because the gate is the story — an
     * {@code AccessDeniedException} surfacing as 403 is more useful filed as FORBIDDEN.
     */
    private ApiLogStatus resolveStatus(int statusCode, ApiLogContext context, Exception failure) {
        if (statusCode == 401) return ApiLogStatus.UNAUTHORIZED;
        if (statusCode == 403) return ApiLogStatus.FORBIDDEN;
        if (statusCode == 504 || failure instanceof AsyncRequestTimeoutException) return ApiLogStatus.TIMEOUT;
        if (context.isExceptionRecorded()) return ApiLogStatus.EXCEPTION;
        if (statusCode >= 400) return ApiLogStatus.FAILED;
        return ApiLogStatus.SUCCESS;
    }

    /** Honours a client {@code X-Request-Id} so mobile and server traces line up; else mints one. */
    private String resolveRequestId(HttpServletRequest request) {
        String supplied = request.getHeader(REQUEST_ID_HEADER);
        if (supplied != null && !supplied.isBlank()) return truncate(supplied.trim(), 64);
        return UUID.randomUUID().toString();
    }

    /** Never creates a session — the app is STATELESS and must stay that way. */
    private String sessionId(HttpServletRequest request) {
        var session = request.getSession(false);
        return session == null ? null : truncate(session.getId(), 128);
    }

    /**
     * First hop of {@code X-Forwarded-For} when present — behind a load balancer
     * {@code getRemoteAddr()} is the balancer, not the caller. Only the first entry is trusted;
     * the rest of the chain is client-controlled and can be forged.
     */
    private String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            int comma = forwarded.indexOf(',');
            return truncate((comma > 0 ? forwarded.substring(0, comma) : forwarded).trim(), 64);
        }
        String realIp = request.getHeader("X-Real-IP");
        if (realIp != null && !realIp.isBlank()) return truncate(realIp.trim(), 64);
        return truncate(request.getRemoteAddr(), 64);
    }

    private String header(HttpServletRequest request, String name, int max) {
        String value = request.getHeader(name);
        return value == null || value.isBlank() ? null : truncate(value.trim(), max);
    }

    private String queryParameters(HttpServletRequest request) {
        String query = request.getQueryString();
        if (query == null || query.isBlank()) return null;
        String processed = properties.isMaskSensitiveData() ? masker.maskQueryString(query) : query;
        return truncate(processed, properties.getMaxPayloadChars());
    }

    /** Header names are case-insensitive, so masking is applied per name via the masker. */
    private String headers(HttpServletRequest request) {
        Map<String, String> collected = new LinkedHashMap<>();
        var names = request.getHeaderNames();
        if (names == null) return null;
        for (String name : Collections.list(names)) {
            collected.put(name, request.getHeader(name));
        }
        Map<String, String> finalHeaders = properties.isMaskSensitiveData()
                ? masker.maskHeaders(collected) : collected;
        try {
            return truncate(objectMapper.writeValueAsString(finalHeaders), properties.getMaxPayloadChars());
        } catch (Exception ex) {
            return truncate(finalHeaders.toString(), properties.getMaxPayloadChars());
        }
    }

    /**
     * Mask first, truncate second. The reverse order is a real leak: cutting JSON mid-document
     * makes it unparseable, the structural masker then bails out, and the surviving tail can
     * still contain a raw secret.
     */
    private String payload(String body) {
        if (body == null || body.isBlank()) return null;
        String masked = properties.isMaskSensitiveData() ? masker.maskPayload(body) : body;
        return truncate(masked, properties.getMaxPayloadChars());
    }

    private static final String TRUNCATION_MARKER = "...[truncated]";

    /**
     * Guarantees a result of at most {@code max} characters — the marker is written <i>inside</i>
     * the budget, not appended past it. Appending would push a value over the column length and
     * turn a logging concern into a failed insert.
     */
    private static String truncate(String value, int max) {
        if (value == null || value.length() <= max) return value;
        if (max <= TRUNCATION_MARKER.length()) return value.substring(0, max);
        return value.substring(0, max - TRUNCATION_MARKER.length()) + TRUNCATION_MARKER;
    }
}
