package com.pgmanager.apilog;

import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * The only place a log row is written.
 *
 * <p>{@code REQUIRES_NEW} is the important annotation. When {@code logging.api.async=false} the
 * save runs on the request thread, which may still be inside the business transaction; joining it
 * would mean a rolled-back business transaction also discards the log of the request that failed —
 * exactly the row you most want to keep. A separate transaction makes the audit trail independent
 * of the outcome it is recording.
 *
 * <p>Failures are caught and logged, never rethrown: a full disk or a locked table must degrade
 * observability, not the API.
 */
@Service
@RequiredArgsConstructor
public class ApiLogPersistenceService {

    private static final Logger log = LoggerFactory.getLogger(ApiLogPersistenceService.class);

    private final ApiRequestLogRepository repository;

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void persist(ApiRequestLog entry) {
        try {
            repository.save(entry);
        } catch (Exception ex) {
            // Fall back to the file log so the hit is not lost entirely, and keep the message
            // short — a stack trace per failed insert would flood the log during an outage.
            log.error("Could not persist API log [{} {} status={} requestId={}]: {}",
                    entry.getHttpMethod(), entry.getRequestUri(), entry.getResponseStatusCode(),
                    entry.getRequestId(), ex.getMessage());
        }
    }
}
