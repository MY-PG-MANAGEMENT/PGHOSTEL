package com.pgmanager.apilog;

import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;

/**
 * Enforces the retention window. Default 03:15 daily, both the cron and the window configurable.
 *
 * <p><b>Why it deletes in batches instead of one statement.</b> At "log every hit" volume, ten
 * days is easily millions of rows. A single {@code DELETE ... WHERE created_date < ?} would hold
 * one transaction open for minutes, inflate the InnoDB undo log until concurrent reads slow down,
 * lock a large range of the {@code created_date} index, and — on replicated setups — ship as one
 * enormous binlog event. Chunking keeps every transaction short and lets normal traffic interleave.
 *
 * <p>{@code cleanupMaxBatchesPerRun} is the safety stop: if a backlog somehow exceeds what one run
 * should tackle, the job gives up for tonight and says so, rather than hammering the database
 * until morning. The next run continues where this one stopped.
 *
 * <p>Single-instance assumption: with several application nodes this runs on each of them. The
 * batched delete is idempotent so concurrent runs are harmless (they just race to remove the same
 * rows), but if that ever matters, guard it with ShedLock rather than switching it off.
 */
@Component
@RequiredArgsConstructor
public class ApiLogCleanupScheduler {

    private static final Logger log = LoggerFactory.getLogger(ApiLogCleanupScheduler.class);

    private final ApiRequestLogRepository repository;
    private final ApiLogProperties properties;

    @Scheduled(cron = "${logging.api.cleanup-cron:0 15 3 * * *}")
    public void purgeExpiredLogs() {
        if (!properties.isEnabled()) return;

        int retentionDays = properties.getRetentionDays();
        if (retentionDays <= 0) {
            log.warn("API log cleanup skipped: retention-days is {} — refusing to delete everything", retentionDays);
            return;
        }

        LocalDateTime cutoff = LocalDateTime.now().minusDays(retentionDays);
        int batchSize = Math.max(1, properties.getCleanupBatchSize());
        int maxBatches = Math.max(1, properties.getCleanupMaxBatchesPerRun());

        long totalDeleted = 0;
        int batches = 0;
        while (batches < maxBatches) {
            // Each call is its own transaction, because the @Transactional sits on the repository
            // method. Putting it on a method of *this* bean and calling it from here would be
            // self-invocation: the call never leaves the object, so the proxy is bypassed and the
            // annotation silently does nothing — a classic way to end up with one implicit
            // auto-commit per statement and no batching guarantee at all.
            int deleted = repository.deleteBatchOlderThan(cutoff, batchSize);
            totalDeleted += deleted;
            batches++;
            // A short batch means the tail is reached — stop rather than issue a pointless query.
            if (deleted < batchSize) break;
        }

        if (batches >= maxBatches) {
            log.warn("API log cleanup hit the {}-batch ceiling ({} rows removed, cutoff {}). " +
                     "Remaining rows will be purged on the next run.", maxBatches, totalDeleted, cutoff);
        } else if (totalDeleted > 0) {
            log.info("API log cleanup removed {} rows older than {} ({} day retention)",
                    totalDeleted, cutoff, retentionDays);
        }
    }
}
