package com.pgmanager.apilog;

import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

/**
 * The default {@link ApiLogWriter}: turns a finished row into an application event.
 *
 * <p>Publishing is synchronous and cheap (it just walks the listener list); the actual thread hop
 * happens in {@link ApiLogEventListener}, which is {@code @Async}. Keeping the hop in the listener
 * rather than here is what lets {@code logging.api.async=false} degrade to a plain in-thread save
 * with no second code path to maintain.
 */
@Component
@RequiredArgsConstructor
public class ApiLogEventPublisher implements ApiLogWriter {

    private static final Logger log = LoggerFactory.getLogger(ApiLogEventPublisher.class);

    private final ApplicationEventPublisher publisher;

    @Override
    public void write(ApiRequestLog entry) {
        try {
            publisher.publishEvent(new ApiLogEvent(entry));
        } catch (Exception ex) {
            // Swallow by contract. A broken logger degrades observability; it must not turn a
            // working API call into a 500.
            log.error("Failed to publish API log event for {} {}", entry.getHttpMethod(), entry.getRequestUri(), ex);
        }
    }
}
