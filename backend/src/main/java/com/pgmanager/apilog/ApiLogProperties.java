package com.pgmanager.apilog;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Everything about API logging is switchable from {@code application.yml} under
 * {@code logging.api.*}. Defaults are the production-safe answer, so an empty config block
 * still behaves correctly.
 */
@Getter
@Setter
@ConfigurationProperties(prefix = "logging.api")
public class ApiLogProperties {

    /** Master switch. When false the filter/interceptor short-circuit and nothing is persisted. */
    private boolean enabled = true;

    /** Capture request payloads. Turning this off also stops the request body being buffered. */
    private boolean storeRequestBody = true;

    /** Capture response payloads. Turning this off also stops the response being buffered. */
    private boolean storeResponseBody = true;

    /** Run values through {@link SensitiveDataMasker} before persisting. Leave on. */
    private boolean maskSensitiveData = true;

    /** Persist off the request thread via the api-log executor. */
    private boolean async = true;

    /** Rows older than this are deleted by {@link ApiLogCleanupScheduler}. */
    private int retentionDays = 10;

    /**
     * Hard cap on each stored payload, in characters. Masking runs first, then truncation —
     * truncating first would leave unparseable JSON whose tail could still hold a secret.
     * Keep at or below what the TEXT columns hold (65,535 <em>bytes</em>; 8,000 chars of
     * utf8mb4 is worst-case ~32 KB, comfortably inside).
     */
    private int maxPayloadChars = 8_000;

    /**
     * How many bytes may be buffered per body before capture is abandoned altogether.
     *
     * <p>Derived rather than configured, to keep the two numbers from drifting apart. It is
     * deliberately larger than {@link #maxPayloadChars}: a body somewhat over the cap should be
     * buffered and <em>truncated</em> (the head of a payload is what you debug from), while a body
     * far over it — a 40 MB CSV upload — should never enter the heap at all. Buffering to 4× also
     * means moderately oversized JSON is still complete enough to parse, so the structural masker
     * runs instead of degrading to the regex fallback.
     */
    public long maxBufferedBytes() {
        return (long) maxPayloadChars * 4;
    }

    /**
     * Content types whose bodies are safe to buffer as text. Anything else (multipart CSV
     * uploads, PDFs, images, octet-stream) is still logged as a hit, but the body is replaced
     * with a placeholder rather than pulled into heap. Prefix match, case-insensitive.
     */
    private Set<String> loggableContentTypes = new LinkedHashSet<>(Set.of(
            "application/json",
            "application/x-www-form-urlencoded",
            "text/plain",
            "text/html",
            "text/xml",
            "application/xml"
    ));

    /** Cleanup cron. Default 03:15 daily — off-peak, and clear of the 01:00 invoice sweep. */
    private String cleanupCron = "0 15 3 * * *";

    /** Rows deleted per statement by the cleanup job. Keeps each transaction and lock window short. */
    private int cleanupBatchSize = 5_000;

    /** Safety stop so one run cannot loop forever on a pathologically large backlog. */
    private int cleanupMaxBatchesPerRun = 200;

    @Getter
    @Setter
    private Executor executor = new Executor();

    /**
     * Bounded pool, on purpose. The scope is "log every hit, no sampling", so a discard policy
     * is not an option — the queue is capped and overflow falls back to the caller
     * (see {@link ApiLogAsyncConfig}), which trades latency for never losing a row.
     */
    @Getter
    @Setter
    public static class Executor {
        private int coreSize = 2;
        private int maxSize = 8;
        private int queueCapacity = 10_000;
        private int awaitTerminationSeconds = 20;
    }
}
