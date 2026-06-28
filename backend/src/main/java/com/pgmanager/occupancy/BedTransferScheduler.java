package com.pgmanager.occupancy;

import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Applies scheduled (sharing-change) bed transfers once their effective date arrives.
 * Runs shortly after midnight so a transfer effective on, say, Jul 2 is applied before
 * that day's invoice generation, ensuring the new sharing's rent lands on the new cycle.
 */
@Component
@RequiredArgsConstructor
public class BedTransferScheduler {
    private static final Logger log = LoggerFactory.getLogger(BedTransferScheduler.class);
    private final OccupancyService occupancyService;

    @Scheduled(cron = "0 5 0 * * *")
    public void applyDueTransfers() {
        int applied = occupancyService.applyDueTransfers();
        if (applied > 0) {
            log.info("Applied {} scheduled bed transfer(s)", applied);
        }
    }
}
