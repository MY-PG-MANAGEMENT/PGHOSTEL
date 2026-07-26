package com.pgmanager.apilog;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class ApiLogCleanupSchedulerTest {

    private ApiRequestLogRepository repository;
    private ApiLogProperties properties;
    private ApiLogCleanupScheduler scheduler;

    @BeforeEach
    void setUp() {
        repository = mock(ApiRequestLogRepository.class);
        properties = new ApiLogProperties();
        scheduler = new ApiLogCleanupScheduler(repository, properties);
    }

    @Test
    void deletesUsingTheConfiguredRetentionWindow() {
        properties.setRetentionDays(10);
        when(repository.deleteBatchOlderThan(any(), anyInt())).thenReturn(0);

        LocalDateTime before = LocalDateTime.now().minusDays(10);
        scheduler.purgeExpiredLogs();
        LocalDateTime after = LocalDateTime.now().minusDays(10);

        ArgumentCaptor<LocalDateTime> cutoff = ArgumentCaptor.forClass(LocalDateTime.class);
        verify(repository).deleteBatchOlderThan(cutoff.capture(), anyInt());
        assertThat(cutoff.getValue()).isBetween(before, after);
    }

    @Test
    void keepsDeletingUntilABatchComesBackShort() {
        properties.setCleanupBatchSize(100);
        // Two full batches, then a partial one — the partial batch is the stop signal.
        when(repository.deleteBatchOlderThan(any(), anyInt())).thenReturn(100, 100, 42);

        scheduler.purgeExpiredLogs();

        verify(repository, times(3)).deleteBatchOlderThan(any(), anyInt());
    }

    @Test
    void stopsAtTheBatchCeilingSoOneRunCannotHammerTheDatabaseAllNight() {
        properties.setCleanupBatchSize(10);
        properties.setCleanupMaxBatchesPerRun(5);
        // Always a full batch: without the ceiling this would loop forever.
        when(repository.deleteBatchOlderThan(any(), anyInt())).thenReturn(10);

        scheduler.purgeExpiredLogs();

        verify(repository, times(5)).deleteBatchOlderThan(any(), anyInt());
    }

    @Test
    void doesNothingWhenLoggingIsDisabled() {
        properties.setEnabled(false);

        scheduler.purgeExpiredLogs();

        verifyNoInteractions(repository);
    }

    @Test
    void refusesToRunWithANonPositiveRetentionWindow() {
        // A misconfigured 0 must not be read as "delete everything".
        properties.setRetentionDays(0);

        scheduler.purgeExpiredLogs();

        verify(repository, never()).deleteBatchOlderThan(any(), anyInt());
    }
}
