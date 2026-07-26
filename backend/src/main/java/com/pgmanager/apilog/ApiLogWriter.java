package com.pgmanager.apilog;

/**
 * How a finished log row leaves the request thread.
 *
 * <p>The filter depends on this one method and nothing else — not on Spring events, not on an
 * executor, not on a repository. That is the Dependency Inversion part of the design and it buys
 * two concrete things: the filter is unit-testable with a list-collecting stub (no Spring context,
 * no database), and the delivery mechanism can change — sync today, events tomorrow, Kafka later —
 * without reopening the capture logic.
 */
public interface ApiLogWriter {

    /**
     * Hands over a fully populated, detached entry. The caller has already finished with the
     * request, so the implementation may hop threads freely.
     *
     * <p>Implementations must not throw: logging is never allowed to fail a business request.
     */
    void write(ApiRequestLog entry);
}
