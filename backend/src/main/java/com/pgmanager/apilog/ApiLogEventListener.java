package com.pgmanager.apilog;

import lombok.RequiredArgsConstructor;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

/**
 * Moves persistence off the request thread.
 *
 * <p>{@code @Async} names {@link ApiLogAsyncConfig#API_LOG_EXECUTOR} explicitly rather than
 * relying on the ambient default executor. That matters: Boot's default is an unbounded
 * {@code SimpleAsyncTaskExecutor}-style pool in some versions, and sharing one pool between API
 * logging and any future async work means a slow database backs up unrelated tasks. A dedicated,
 * bounded, named pool keeps the failure blast radius inside this feature.
 *
 * <p>When {@code logging.api.async=false} the {@code @Async} advice is skipped
 * (see {@link ApiLogAsyncConfig}) and the save runs inline — useful in tests, and the honest
 * choice on a box where losing the tail of the log on shutdown is unacceptable.
 */
@Component
@RequiredArgsConstructor
public class ApiLogEventListener {

    private final ApiLogPersistenceService persistenceService;

    @Async(ApiLogAsyncConfig.API_LOG_EXECUTOR)
    @EventListener
    public void onApiLog(ApiLogEvent event) {
        persistenceService.persist(event.entry());
    }
}
