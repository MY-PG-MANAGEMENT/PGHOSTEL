package com.pgmanager.apilog;

import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.AsyncConfigurer;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.util.concurrent.Executor;
import java.util.concurrent.ThreadPoolExecutor;

/**
 * The async half of the write path, and the switch that turns it off.
 *
 * <p><b>How {@code logging.api.async=false} works.</b> Rather than branching inside the listener,
 * the whole {@code @EnableAsync} registration is conditional. With the property off, Spring never
 * installs the async advice, so {@code @Async} on {@link ApiLogEventListener} is inert and the
 * save runs inline on the request thread. One annotation, no duplicated code path, and nothing to
 * keep in sync between the two modes.
 *
 * <p><b>Pool sizing is a lossless-vs-latency decision.</b> The requirement is every hit
 * persisted — no sampling, no exclusions — so a discard policy is off the table. An unbounded
 * queue is the other common answer and it is worse: under a sustained burst it grows until the
 * heap dies, taking the application with it. So the queue is bounded and overflow uses
 * {@link ThreadPoolExecutor.CallerRunsPolicy}: when the pool is saturated the request thread
 * performs the insert itself. That is deliberate backpressure — requests slow down, the queue
 * drains, and not one row is lost. Slow beats silently incomplete for an audit trail.
 *
 * <p>Shutdown waits for the queue to drain ({@code setWaitForTasksToCompleteOnShutdown}) so a
 * rolling deploy does not discard the last few seconds of traffic.
 */
@Configuration
@EnableAsync
@RequiredArgsConstructor
@ConditionalOnProperty(name = "logging.api.async", havingValue = "true", matchIfMissing = true)
public class ApiLogAsyncConfig implements AsyncConfigurer {

    public static final String API_LOG_EXECUTOR = "apiLogExecutor";

    private static final Logger log = LoggerFactory.getLogger(ApiLogAsyncConfig.class);

    private final ApiLogProperties properties;

    @Bean(name = API_LOG_EXECUTOR)
    public Executor apiLogExecutor() {
        ApiLogProperties.Executor config = properties.getExecutor();
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(config.getCoreSize());
        executor.setMaxPoolSize(config.getMaxSize());
        executor.setQueueCapacity(config.getQueueCapacity());
        executor.setThreadNamePrefix("api-log-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(config.getAwaitTerminationSeconds());
        executor.initialize();
        return executor;
    }

    /**
     * {@code @Async} on a {@code void} method swallows exceptions by default — the row would
     * vanish with no trace at all. This surfaces them.
     *
     * <p>{@code getAsyncExecutor()} is deliberately left at its default (null → Spring's own
     * executor): making the api-log pool the application-wide default would mean a future
     * {@code @Async} method competes for the same bounded queue that carries the audit trail.
     */
    @Override
    public org.springframework.aop.interceptor.AsyncUncaughtExceptionHandler getAsyncUncaughtExceptionHandler() {
        return (throwable, method, params) ->
                log.error("Async API log task failed in {}: {}", method.getName(), throwable.getMessage(), throwable);
    }
}
