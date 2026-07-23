package com.pgmanager.notification;

/**
 * A fully-resolved message ready for a {@link MessageChannel} to deliver.
 * Assembled by {@link OutboxDispatcher} from a {@code notification_outbox} row
 * joined with the notification, recipient person, and organization.
 */
public record OutboundMessage(
        String email,
        String mobile,
        String recipientName,
        String subject,
        String body,
        String orgName,
        String orgEmail
) {}
