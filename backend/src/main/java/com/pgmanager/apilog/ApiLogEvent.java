package com.pgmanager.apilog;

/**
 * Carries one finished log row from the request thread to whoever wants it.
 *
 * <p>The payload is an already-populated, detached {@link ApiRequestLog}: every field was read
 * from the request before it was recycled, so no listener ever touches servlet state. A record
 * (not a class) makes the immutability of the envelope explicit.
 *
 * <p>Using an event rather than calling the repository directly is what makes this framework
 * extensible without modification — a metrics counter, a slow-request alerter or an Elasticsearch
 * shipper is a new {@code @EventListener}, with no edit to the filter. That is Open/Closed
 * applied where it actually pays off.
 */
public record ApiLogEvent(ApiRequestLog entry) {
}
