package com.pgmanager.apilog;

import jakarta.servlet.http.HttpServletRequest;
import lombok.Getter;
import lombok.Setter;

/**
 * Per-request scratch space shared by the three components that each see a different slice of
 * the request.
 *
 * <p><b>Why a request attribute and not a ThreadLocal.</b> A ThreadLocal is the usual reflex
 * here and it is the wrong one: Spring MVC async dispatch resumes the request on a
 * <em>different</em> thread, so the ThreadLocal set in {@code preHandle} would be invisible when
 * the filter finishes — and a missed {@code remove()} on a pooled container thread leaks the
 * previous caller's org id into the next request, which is a cross-tenant data bug. A request
 * attribute is bound to the {@code HttpServletRequest} itself: it survives the async hop,
 * dies with the request, and needs no cleanup. Each request has exactly one instance touched by
 * one thread at a time, so the mutable fields need no synchronisation.
 *
 * <p>Written by {@link ApiLogHandlerInterceptor} (identity + handler) and by
 * {@code GlobalExceptionHandler} (error details); read by {@link ApiLogFilter} once the
 * response is complete.
 */
@Getter
@Setter
public class ApiLogContext {

    private static final String ATTRIBUTE = ApiLogContext.class.getName();

    /** Correlation id, echoed to the client in the {@code X-Request-Id} response header. */
    private String requestId;

    /** Monotonic start mark. Immune to wall-clock steps, unlike the persisted timestamps. */
    private long startNanos;

    private Long organizationId;
    private Long userLoginId;
    private Long tenantId;

    private String controllerName;
    private String methodName;

    private String errorCode;
    private String errorMessage;

    /**
     * Set when the handler advice converted an exception into a response. The filter cannot infer
     * this from the status code alone — a business {@code BadRequestException} and a controller
     * that simply returns 400 are indistinguishable by the time the bytes are written.
     */
    private boolean exceptionRecorded;

    /** Attaches a fresh context to the request. Called once, by the filter. */
    static ApiLogContext create(HttpServletRequest request, String requestId, long startNanos) {
        ApiLogContext context = new ApiLogContext();
        context.requestId = requestId;
        context.startNanos = startNanos;
        request.setAttribute(ATTRIBUTE, context);
        return context;
    }

    /**
     * The context for this request, or {@code null} when logging is disabled or the filter never
     * ran (e.g. a plain unit test). Every caller outside the filter must tolerate null — that is
     * what keeps the feature switchable without touching call sites.
     */
    public static ApiLogContext from(HttpServletRequest request) {
        if (request == null) return null;
        Object attribute = request.getAttribute(ATTRIBUTE);
        return attribute instanceof ApiLogContext context ? context : null;
    }

    /**
     * Records an exception that the handler advice has already turned into a client response.
     * A no-op when logging is off, so the advice needs no conditional of its own.
     */
    public static void recordError(HttpServletRequest request, String errorCode, String errorMessage) {
        ApiLogContext context = from(request);
        if (context == null) return;
        context.exceptionRecorded = true;
        context.errorCode = errorCode;
        context.errorMessage = errorMessage;
    }
}
