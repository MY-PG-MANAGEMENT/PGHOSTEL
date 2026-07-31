package com.pgmanager.apilog;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface ApiRequestLogRepository extends JpaRepository<ApiRequestLog, Long> {

    /**
     * Deletes one bounded batch of expired rows.
     *
     * <p>Native query because JPQL has no {@code LIMIT}, and the limit is the point: at
     * "log every hit" volume, ten days of rows is potentially millions, and a single
     * {@code DELETE} would hold one enormous transaction, produce a huge amount of dead tuples
     * for autovacuum to chase, and lock a huge swath of the {@code created_date} index. The
     * scheduler calls this in a loop until a batch comes back short. Returns the number of rows
     * removed.
     *
     * <p>PostgreSQL has no {@code DELETE ... LIMIT}, so the batch is selected first and deleted
     * by {@code ctid} (the physical row address — the cheapest possible way back to the exact
     * rows chosen). {@code FOR UPDATE SKIP LOCKED} keeps two overlapping cleanup runs from
     * blocking on each other or double-counting the same rows.
     */
    @Modifying
    @Transactional
    @Query(value = "DELETE FROM api_request_log WHERE ctid IN (" +
                   "  SELECT ctid FROM api_request_log WHERE created_date < :cutoff " +
                   "  ORDER BY created_date LIMIT :batchSize FOR UPDATE SKIP LOCKED)",
           nativeQuery = true)
    int deleteBatchOlderThan(@Param("cutoff") LocalDateTime cutoff, @Param("batchSize") int batchSize);

    long countByCreatedDateBefore(LocalDateTime cutoff);

    /** Support/debug lookup: every hop of one client request, newest first. */
    List<ApiRequestLog> findByRequestIdOrderByIdDesc(String requestId);
}
