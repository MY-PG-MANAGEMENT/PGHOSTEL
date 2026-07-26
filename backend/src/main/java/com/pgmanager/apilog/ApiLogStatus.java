package com.pgmanager.apilog;

/**
 * Outcome of one API hit, derived from the response status plus whatever the
 * {@code @RestControllerAdvice} recorded. Stored as a string (never an ordinal) so adding a
 * value later cannot reinterpret existing rows.
 *
 * <p>Precedence is deliberate — see {@code ApiLogFilter#resolveStatus}. 401/403 win over
 * EXCEPTION because "who was rejected at the gate" is the more useful signal; an
 * {@code AccessDeniedException} that lands as a 403 reads as FORBIDDEN, not EXCEPTION.
 */
public enum ApiLogStatus {
    /** 2xx/3xx with no recorded exception. */
    SUCCESS,
    /** 4xx/5xx that did not come from a thrown exception (e.g. an unmapped 404). */
    FAILED,
    /** An exception reached the handler advice; {@code errorCode}/{@code errorMessage} are set. */
    EXCEPTION,
    /** 401 — no or invalid credentials. Produced inside the Spring Security chain. */
    UNAUTHORIZED,
    /** 403 — authenticated but not permitted. */
    FORBIDDEN,
    /** Async/dispatch timeout (504, or Spring's AsyncRequestTimeoutException). */
    TIMEOUT
}
