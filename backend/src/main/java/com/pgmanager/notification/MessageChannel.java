package com.pgmanager.notification;

/**
 * A delivery channel for an outbound notification (EMAIL now; WHATSAPP later).
 * Implementations are auto-discovered by {@link OutboxDispatcher} and keyed by
 * {@link #channelId()}, which must match the {@code channel_type_id} written to
 * {@code notification_outbox}.
 */
public interface MessageChannel {

    /** The channel constant, e.g. {@code "EMAIL"}. Matches {@code notification_outbox.channel_type_id}. */
    String channelId();

    /** Whether this channel is configured and ready to send. When false, the dispatcher leaves rows queued. */
    boolean enabled();

    /**
     * Delivers the message and returns a provider message id (or a non-null marker).
     * Throws on failure so the dispatcher can retry with backoff.
     */
    String send(OutboundMessage message);
}
