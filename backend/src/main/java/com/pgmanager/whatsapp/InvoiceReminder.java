package com.pgmanager.whatsapp;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * A payment reminder, ready to deliver — attached to the invoice-detail response as
 * {@code reminder}.
 *
 * <p>Delivery-agnostic on purpose. In Phase 1 the Flutter app takes {@link #whatsappNumber()} and
 * {@link #message()} and builds a {@code wa.me} deep link; in Phase 2 the backend will hand the
 * same pair (or the template parameters behind it) to the WhatsApp Cloud API. Nothing in this
 * record mentions a URL, a channel or a provider, so that swap does not change its shape.
 *
 * @param status         the derived reminder type: {@code OVERDUE}, {@code DUE} or {@code TOMORROW}
 *                       when sendable; otherwise why not
 * @param canRemind      whether a reminder may be sent at all
 * @param blockedReason  the sentence the app shows when {@code canRemind} is false; null otherwise
 * @param message        the full reminder text, or null when {@code canRemind} is false
 * @param whatsappNumber E.164 digits with no {@code +}, ready for {@code wa.me}; null when unusable
 * @param dueAmount      outstanding amount, clamped at zero
 */
public record InvoiceReminder(
        String status,
        boolean canRemind,
        String blockedReason,
        String tenantName,
        String propertyName,
        String paymentType,
        BigDecimal dueAmount,
        LocalDate dueDate,
        String whatsappNumber,
        String message
) {
    /**
     * A reminder that cannot be sent, carrying the reason and the context the sheet still renders
     * (a paid invoice should still show who it was for).
     */
    static InvoiceReminder blocked(InvoiceReminderStatus status,
                                   String reason,
                                   String tenantName,
                                   String propertyName,
                                   String paymentType,
                                   BigDecimal dueAmount,
                                   LocalDate dueDate,
                                   String whatsappNumber) {
        return new InvoiceReminder(status.name(), false, reason, tenantName, propertyName,
                paymentType, dueAmount, dueDate, whatsappNumber, null);
    }
}
