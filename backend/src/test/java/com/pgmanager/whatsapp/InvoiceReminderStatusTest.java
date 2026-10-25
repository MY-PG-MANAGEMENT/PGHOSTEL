package com.pgmanager.whatsapp;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The reminder status is the one thing a client must never be allowed to supply, so it is the
 * one thing that has to be right. These are pure-function tests over the money/date matrix —
 * no database, no clock.
 */
class InvoiceReminderStatusTest {

    private static final LocalDate TODAY = LocalDate.of(2026, 8, 8);
    private static final BigDecimal RENT = new BigDecimal("8500.00");
    private static final BigDecimal NOTHING = BigDecimal.ZERO;

    private static InvoiceReminderStatus derive(LocalDate dueDate, BigDecimal paid) {
        return InvoiceReminderStatus.derive(dueDate, RENT, paid, "PENDING", TODAY);
    }

    // ── The three sendable windows ──────────────────────────────────────────────

    @Test
    void aPastDueDateWithMoneyOutstandingIsOverdue() {
        assertThat(derive(TODAY.minusDays(1), NOTHING)).isEqualTo(InvoiceReminderStatus.OVERDUE);
        assertThat(derive(TODAY.minusMonths(3), NOTHING)).isEqualTo(InvoiceReminderStatus.OVERDUE);
    }

    @Test
    void todayIsDue() {
        assertThat(derive(TODAY, NOTHING)).isEqualTo(InvoiceReminderStatus.DUE);
    }

    @Test
    void tomorrowIsTomorrow() {
        assertThat(derive(TODAY.plusDays(1), NOTHING)).isEqualTo(InvoiceReminderStatus.TOMORROW);
    }

    /** The day after tomorrow is not a reminder window — chasing that early is noise. */
    @Test
    void twoDaysOutIsNotDue() {
        assertThat(derive(TODAY.plusDays(2), NOTHING)).isEqualTo(InvoiceReminderStatus.NOT_DUE);
        assertThat(derive(TODAY.plusMonths(1), NOTHING)).isEqualTo(InvoiceReminderStatus.NOT_DUE);
    }

    @Test
    void aPartPaidInvoiceStillInsideTheWindowIsStillChaseable() {
        assertThat(derive(TODAY, new BigDecimal("3000.00"))).isEqualTo(InvoiceReminderStatus.DUE);
        assertThat(derive(TODAY.minusDays(5), new BigDecimal("8499.99"))).isEqualTo(InvoiceReminderStatus.OVERDUE);
    }

    // ── Money wins over the calendar ────────────────────────────────────────────

    /**
     * The whole reason money is checked before dates: an invoice paid in full a month after its
     * due date must not be reported as overdue. This is the case that would send a wrong message.
     */
    @Test
    void aFullyPaidInvoiceIsSettledEvenWhenLongOverdue() {
        assertThat(derive(TODAY.minusMonths(2), RENT)).isEqualTo(InvoiceReminderStatus.SETTLED);
    }

    @Test
    void anOverpaidInvoiceIsSettledAndNeverReportsANegativeDue() {
        assertThat(derive(TODAY, new BigDecimal("9000.00"))).isEqualTo(InvoiceReminderStatus.SETTLED);
        assertThat(InvoiceReminderStatus.outstanding(RENT, new BigDecimal("9000.00")))
                .isEqualByComparingTo(BigDecimal.ZERO);
    }

    @Test
    void aPaidStatusIsSettledEvenIfTheAmountsDisagree() {
        // Defensive: mark-paid sets paid_amount = total_amount, but a manual correction could
        // leave the two out of step and the status must still win.
        assertThat(InvoiceReminderStatus.derive(TODAY, RENT, NOTHING, "PAID", TODAY))
                .isEqualTo(InvoiceReminderStatus.SETTLED);
    }

    // ── Invoices that are not live dues ─────────────────────────────────────────

    /**
     * A cancelled invoice keeps its balance on paper (delete is a soft-cancel), so without this
     * screen a deleted invoice would look overdue and be chaseable.
     */
    @ParameterizedTest
    @ValueSource(strings = {"CANCELLED", "cancelled", "WRITTEN_OFF"})
    void aClosedInvoiceIsNotADue(String status) {
        assertThat(InvoiceReminderStatus.derive(TODAY.minusDays(10), RENT, NOTHING, status, TODAY))
                .isEqualTo(InvoiceReminderStatus.CLOSED);
    }

    @Test
    void aMissingDueDateIsNotChased() {
        assertThat(derive(null, NOTHING)).isEqualTo(InvoiceReminderStatus.NOT_DUE);
    }

    // ── The sendable contract ───────────────────────────────────────────────────

    @Test
    void onlyTheThreeDueWindowsAreSendable() {
        assertThat(InvoiceReminderStatus.OVERDUE.sendable()).isTrue();
        assertThat(InvoiceReminderStatus.DUE.sendable()).isTrue();
        assertThat(InvoiceReminderStatus.TOMORROW.sendable()).isTrue();
        assertThat(InvoiceReminderStatus.NOT_DUE.sendable()).isFalse();
        assertThat(InvoiceReminderStatus.SETTLED.sendable()).isFalse();
        assertThat(InvoiceReminderStatus.CLOSED.sendable()).isFalse();
    }

    /** Every non-sendable state must be able to explain itself — the sheet renders this text. */
    @Test
    void everyBlockedStatusCarriesAnExplanation() {
        for (InvoiceReminderStatus status : InvoiceReminderStatus.values()) {
            if (!status.sendable()) {
                assertThat(status.explanation()).as("explanation for %s", status).isNotBlank();
            }
        }
    }

    @Test
    void outstandingTreatsNullsAsZero() {
        assertThat(InvoiceReminderStatus.outstanding(null, null)).isEqualByComparingTo(BigDecimal.ZERO);
        assertThat(InvoiceReminderStatus.outstanding(RENT, null)).isEqualByComparingTo(RENT);
    }
}
