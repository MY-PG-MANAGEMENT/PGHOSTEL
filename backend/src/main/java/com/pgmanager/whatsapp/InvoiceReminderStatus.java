package com.pgmanager.whatsapp;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Why an invoice is (or is not) worth chasing on WhatsApp.
 *
 * <p><b>The client never supplies this.</b> A reminder that says "overdue" when the tenant
 * paid yesterday is worse than no reminder at all, so the status is derived here from the
 * invoice's own money and dates and nowhere else. {@link #derive} is a pure function, which
 * is the whole point: it is exhaustively unit-tested without a database
 * ({@code InvoiceReminderStatusTest}).
 */
public enum InvoiceReminderStatus {

    /** Due date has passed and money is still outstanding. */
    OVERDUE(true),

    /** Due today, still outstanding. */
    DUE(true),

    /** Due tomorrow, still outstanding. */
    TOMORROW(true),

    /**
     * Outstanding, but the due date is far enough away that a payment reminder would be
     * noise. Not an error — the sheet explains it and disables Send.
     */
    NOT_DUE(false),

    /** Nothing left to collect. A reminder here would be plainly wrong. */
    SETTLED(false),

    /** The invoice was cancelled or written off; it is not a due. */
    CLOSED(false);

    private final boolean sendable;

    InvoiceReminderStatus(boolean sendable) {
        this.sendable = sendable;
    }

    /** Whether a reminder may be sent for an invoice in this state. */
    public boolean sendable() {
        return sendable;
    }

    /**
     * Derives the status from the invoice itself.
     *
     * <p>Order matters. Money is checked before dates: an invoice whose outstanding amount
     * has reached zero is {@link #SETTLED} even if it is a month overdue, because the
     * question "should we chase this?" is answered by the balance, not the calendar.
     * Statuses that are not a live due ({@code CANCELLED}, {@code WRITTEN_OFF}, {@code PAID})
     * are screened out first for the same reason — {@code CheckoutInvoiceService} and the
     * owner-facing delete both leave rows behind that still have a balance on paper.
     *
     * @param dueDate       {@code invoice.due_date}; null is treated as not chaseable
     * @param totalAmount   {@code invoice.total_amount}
     * @param paidAmount    {@code invoice.paid_amount}
     * @param invoiceStatus {@code invoice.status}
     * @param today         the reference date, injected so tests are not clock-dependent
     */
    public static InvoiceReminderStatus derive(LocalDate dueDate,
                                               BigDecimal totalAmount,
                                               BigDecimal paidAmount,
                                               String invoiceStatus,
                                               LocalDate today) {
        String normalized = invoiceStatus == null ? "" : invoiceStatus.trim().toUpperCase();
        if (normalized.equals("CANCELLED") || normalized.equals("WRITTEN_OFF")) {
            return CLOSED;
        }
        if (outstanding(totalAmount, paidAmount).compareTo(BigDecimal.ZERO) <= 0 || normalized.equals("PAID")) {
            return SETTLED;
        }
        if (dueDate == null || today == null) {
            return NOT_DUE;
        }
        if (dueDate.isBefore(today)) return OVERDUE;
        if (dueDate.isEqual(today)) return DUE;
        if (dueDate.isEqual(today.plusDays(1))) return TOMORROW;
        return NOT_DUE;
    }

    /** {@code total - paid}, never negative — an overpayment is not a credit to chase. */
    public static BigDecimal outstanding(BigDecimal totalAmount, BigDecimal paidAmount) {
        BigDecimal total = totalAmount == null ? BigDecimal.ZERO : totalAmount;
        BigDecimal paid = paidAmount == null ? BigDecimal.ZERO : paidAmount;
        BigDecimal balance = total.subtract(paid);
        return balance.compareTo(BigDecimal.ZERO) < 0 ? BigDecimal.ZERO : balance;
    }

    /** A short sentence the app shows when {@link #sendable()} is false. */
    public String explanation() {
        return switch (this) {
            case SETTLED -> "This invoice is fully paid — there is nothing to remind about.";
            case CLOSED -> "This invoice is cancelled or written off, so it is not a due.";
            case NOT_DUE -> "A payment reminder can be sent from the day before the due date onwards.";
            default -> "";
        };
    }
}
