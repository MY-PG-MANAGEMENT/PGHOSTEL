package com.pgmanager.notification;

import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Drains {@code notification_outbox} and delivers each PENDING row through its
 * {@link MessageChannel}. Runs on a fixed delay (independent of the request that
 * enqueued the row), so external delivery never blocks or fails a business
 * operation. Failed sends are retried with exponential backoff up to
 * {@link #MAX_ATTEMPTS}, after which the row is marked FAILED.
 *
 * <p>If no channel is enabled the dispatcher does nothing and rows stay queued,
 * so enabling email later flushes anything that accumulated in the meantime.
 */
@Component
@RequiredArgsConstructor
public class OutboxDispatcher {

    private static final Logger log = LoggerFactory.getLogger(OutboxDispatcher.class);
    private static final int MAX_ATTEMPTS = 5;
    private static final int BATCH_SIZE = 100;

    private final JdbcTemplate jdbc;
    private final List<MessageChannel> channelBeans;
    private final Map<String, MessageChannel> channels = new HashMap<>();

    @PostConstruct
    void indexChannels() {
        for (MessageChannel c : channelBeans) {
            channels.put(c.channelId(), c);
        }
    }

    @Scheduled(fixedDelay = 60_000, initialDelay = 15_000)
    public void dispatch() {
        boolean anyEnabled = channels.values().stream().anyMatch(MessageChannel::enabled);
        if (!anyEnabled) return; // nothing configured yet — leave rows queued

        List<Map<String, Object>> due = jdbc.queryForList(
                "SELECT o.outbox_id, o.channel_type_id, o.attempt_count, " +
                "       n.title, n.message, n.organization_id, " +
                "       org.facility_name AS org_name, org.email AS org_email, p.full_name, p.email, p.mobile_number " +
                "FROM notification_outbox o " +
                "JOIN notification n ON n.notification_id = o.notification_id " +
                "JOIN person p        ON p.party_id = o.party_id " +
                "LEFT JOIN facility org ON org.facility_id = n.organization_id " +
                "WHERE o.status = 'PENDING' AND (o.next_attempt_at IS NULL OR o.next_attempt_at <= ?) " +
                "ORDER BY o.outbox_id LIMIT " + BATCH_SIZE,
                LocalDateTime.now());

        for (Map<String, Object> row : due) {
            Long id = ((Number) row.get("outbox_id")).longValue();
            String channelId = (String) row.get("channel_type_id");
            MessageChannel channel = channels.get(channelId);

            if (channel == null || !channel.enabled()) continue; // this channel not ready — retry later

            int nextAttempt = ((Number) row.get("attempt_count")).intValue() + 1;
            try {
                OutboundMessage msg = new OutboundMessage(
                        (String) row.get("email"),
                        (String) row.get("mobile_number"),
                        (String) row.get("full_name"),
                        (String) row.get("title"),
                        (String) row.get("message"),
                        (String) row.get("org_name"),
                        (String) row.get("org_email"));
                String providerId = channel.send(msg);
                jdbc.update(
                        "UPDATE notification_outbox SET status='SENT', provider_code=?, provider_message_id=?, " +
                        "attempt_count=?, last_error=NULL, updated_at=? WHERE outbox_id=?",
                        channelId, truncate(providerId, 160), nextAttempt, LocalDateTime.now(), id);
            } catch (Exception e) {
                boolean giveUp = nextAttempt >= MAX_ATTEMPTS;
                // exponential backoff: 2, 4, 8, 16 minutes
                LocalDateTime next = LocalDateTime.now().plusMinutes((long) Math.pow(2, nextAttempt));
                jdbc.update(
                        "UPDATE notification_outbox SET status=?, attempt_count=?, next_attempt_at=?, last_error=?, updated_at=? " +
                        "WHERE outbox_id=?",
                        giveUp ? "FAILED" : "PENDING", nextAttempt, next, truncate(e.getMessage(), 1000),
                        LocalDateTime.now(), id);
                log.warn("Outbox delivery {} on {} failed (attempt {}/{}): {}",
                        id, channelId, nextAttempt, MAX_ATTEMPTS, e.getMessage());
            }
        }
    }

    private static String truncate(String s, int max) {
        if (s == null) return null;
        return s.length() <= max ? s : s.substring(0, max);
    }
}
