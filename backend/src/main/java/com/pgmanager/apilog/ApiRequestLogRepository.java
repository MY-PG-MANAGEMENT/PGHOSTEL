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
     * {@code DELETE} would hold one enormous transaction, bloat the undo log and lock a huge
     * swath of the {@code created_date} index. The scheduler calls this in a loop until a batch
     * comes back short. Returns the number of rows removed.
     */
    @Modifying
    @Transactional
    @Query(value = "DELETE FROM api_request_log WHERE created_date < :cutoff LIMIT :batchSize",
           nativeQuery = true)
    int deleteBatchOlderThan(@Param("cutoff") LocalDateTime cutoff, @Param("batchSize") int batchSize);

    long countByCreatedDateBefore(LocalDateTime cutoff);

    /** Support/debug lookup: every hop of one client request, newest first. */
    List<ApiRequestLog> findByRequestIdOrderByIdDesc(String requestId);
}
