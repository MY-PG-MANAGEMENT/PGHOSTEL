package com.pgmanager.whatsapp;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The reminder as a whole: reminder type, message wording, outstanding amount and phone
 * normalisation, all decided server-side.
 *
 * <p>These are the cases from the spec's test list. They deliberately assert the **message text**
 * rather than just the reminder type — the wording is the deliverable in Phase 1, and it is also the
 * part that must survive unchanged into Phase 2.
 */
class InvoiceReminderServiceTest {

    private static final LocalDate TODAY = LocalDate.now();
    private static final BigDecimal RENT = new BigDecimal("8500.00");
    private static final String DATE_FMT = "dd-MMM-yyyy";

    private InvoiceReminderService service;

    @BeforeEach
    void setUp() {
        service = new InvoiceReminderService(new WhatsAppProperties());
    }

    private InvoiceReminder build(LocalDate dueDate, String paid, String status, String mobile) {
        return service.build(new InvoiceReminderService.ReminderInput(
                "Ravi Kumar", mobile, "Sri Lakshmi PG", List.of("MONTHLY_RENT"),
                dueDate, RENT, new BigDecimal(paid), status));
    }

    private static String formatted(LocalDate date) {
        return date.format(DateTimeFormatter.ofPattern(DATE_FMT));
    }

    // ── Case 1: overdue ─────────────────────────────────────────────────────────

    @Test
    void anOverdueInvoiceProducesTheOverdueMessage() {
        InvoiceReminder reminder = build(TODAY.minusDays(3), "0.00", "PENDING", "9876543210");

        assertThat(reminder.status()).isEqualTo("OVERDUE");
        assertThat(reminder.canRemind()).isTrue();
        assertThat(reminder.blockedReason()).isNull();
        assertThat(reminder.message()).isEqualTo(
                "Hi Ravi Kumar 👋\n\n"
                + "Your Monthly Rent at Sri Lakshmi PG is overdue.\n\n"
                + "🧾 Payment: Monthly Rent\n"
                + "📅 Due date: " + formatted(TODAY.minusDays(3)) + "\n"
                + "⏳ Status: 3 days overdue\n"
                + "💰 Amount due: ₹8,500\n\n"
                + "Please clear the pending amount at your earliest convenience. 🙏\n\n"
                + "Sri Lakshmi PG · PG Manager");
    }

    /** One day late is singular — "1 days overdue" is the tell that a message was machine-written. */
    @Test
    void oneDayLateReadsInTheSingular() {
        InvoiceReminder reminder = build(TODAY.minusDays(1), "0.00", "PENDING", "9876543210");

        assertThat(reminder.message()).contains("Status: 1 day overdue");
    }

    // ── Case 2: due today ───────────────────────────────────────────────────────

    @Test
    void anInvoiceDueTodayProducesTheDueMessage() {
        InvoiceReminder reminder = build(TODAY, "0.00", "PENDING", "9876543210");

        assertThat(reminder.status()).isEqualTo("DUE");
        assertThat(reminder.message()).isEqualTo(
                "Hi Ravi Kumar 👋\n\n"
                + "A gentle reminder that your Monthly Rent at Sri Lakshmi PG is due today.\n\n"
                + "🧾 Payment: Monthly Rent\n"
                + "📅 Due date: " + formatted(TODAY) + "\n"
                + "⏳ Status: Due today\n"
                + "💰 Amount due: ₹8,500\n\n"
                + "Paying today keeps your account clear. ✅\n\n"
                + "Sri Lakshmi PG · PG Manager");
    }

    // ── Case 3: due tomorrow ────────────────────────────────────────────────────

    @Test
    void anInvoiceDueTomorrowProducesTheTomorrowMessage() {
        InvoiceReminder reminder = build(TODAY.plusDays(1), "0.00", "PENDING", "9876543210");

        assertThat(reminder.status()).isEqualTo("TOMORROW");
        assertThat(reminder.message()).isEqualTo(
                "Hi Ravi Kumar 👋\n\n"
                + "Just a heads-up — your Monthly Rent at Sri Lakshmi PG is due tomorrow.\n\n"
                + "🧾 Payment: Monthly Rent\n"
                + "📅 Due date: " + formatted(TODAY.plusDays(1)) + "\n"
                + "⏳ Status: Due in 1 day\n"
                + "💰 Amount due: ₹8,500\n\n"
                + "A small reminder so it does not slip by. 🙂\n\n"
                + "Sri Lakshmi PG · PG Manager");
    }

    /**
     * The reminder is plain text on purpose. WhatsApp's {@code *bold*} / {@code _italic_} markup
     * renders as literal asterisks in a notification preview, a chat export, and any quote or
     * forward — so a payment reminder, which is a business document, must carry none of it.
     */
    @Test
    void noVariantCarriesWhatsAppMarkup() {
        for (LocalDate due : List.of(TODAY.minusDays(2), TODAY, TODAY.plusDays(1))) {
            String message = build(due, "0.00", "PENDING", "9876543210").message();

            assertThat(message).as("markup in %s", message).doesNotContain("*").doesNotContain("_");
        }
    }

    // ── Case 4: fully paid ──────────────────────────────────────────────────────

    @Test
    void aFullyPaidInvoiceProducesNoReminderAtAll() {
        InvoiceReminder reminder = build(TODAY, "8500.00", "PAID", "9876543210");

        assertThat(reminder.status()).isEqualTo("SETTLED");
        assertThat(reminder.canRemind()).isFalse();
        // No message at all — there is nothing for the app to pre-fill, so it cannot accidentally
        // send a "you owe us ₹0" reminder.
        assertThat(reminder.message()).isNull();
        assertThat(reminder.blockedReason()).isNotBlank();
    }

    /**
     * Money is checked before dates. An invoice paid a month after its due date must not be
     * reported as overdue — this is the case that would send a wrong message to a paying tenant.
     */
    @Test
    void anInvoicePaidLateIsSettledNotOverdue() {
        assertThat(build(TODAY.minusMonths(2), "8500.00", "PENDING", "9876543210").status())
                .isEqualTo("SETTLED");
    }

    /** Delete is a soft-cancel, so a cancelled invoice still has a balance on paper. */
    @Test
    void aCancelledInvoiceIsNotChased() {
        InvoiceReminder reminder = build(TODAY.minusDays(3), "0.00", "CANCELLED", "9876543210");

        assertThat(reminder.status()).isEqualTo("CLOSED");
        assertThat(reminder.canRemind()).isFalse();
        assertThat(reminder.message()).isNull();
    }

    @Test
    void anInvoiceDueNextWeekIsNotYetChased() {
        InvoiceReminder reminder = build(TODAY.plusDays(7), "0.00", "PENDING", "9876543210");

        assertThat(reminder.status()).isEqualTo("NOT_DUE");
        assertThat(reminder.canRemind()).isFalse();
        assertThat(reminder.message()).isNull();
    }

    // ── Case 5: missing / invalid mobile ────────────────────────────────────────

    @Test
    void aMissingMobileBlocksTheReminderWithTheSpecifiedMessage() {
        InvoiceReminder reminder = build(TODAY, "0.00", "PENDING", null);

        assertThat(reminder.canRemind()).isFalse();
        assertThat(reminder.blockedReason()).isEqualTo("WhatsApp number is not available for this tenant.");
        assertThat(reminder.whatsappNumber()).isNull();
        // Still a DUE invoice — the block is about the number, not the money.
        assertThat(reminder.status()).isEqualTo("DUE");
    }

    @Test
    void anInvalidMobileBlocksTheReminderWithTheSpecifiedMessage() {
        InvoiceReminder reminder = build(TODAY, "0.00", "PENDING", "12345");

        assertThat(reminder.canRemind()).isFalse();
        assertThat(reminder.blockedReason()).isEqualTo("Invalid WhatsApp number.");
        assertThat(reminder.whatsappNumber()).isNull();
    }

    @Test
    void theNumberIsNormalisedToDigitsReadyForAWaMeLink() {
        assertThat(build(TODAY, "0.00", "PENDING", "+91 98765-43210").whatsappNumber())
                .isEqualTo("919876543210");
    }

    /**
     * A settled invoice reports the money problem, not the phone problem: the owner cannot act on a
     * bad number for an invoice there is no reason to chase, and showing both would be noise.
     */
    @Test
    void aSettledInvoiceWithABadNumberReportsTheSettledReason() {
        InvoiceReminder reminder = build(TODAY, "8500.00", "PAID", "nonsense");

        assertThat(reminder.status()).isEqualTo("SETTLED");
        assertThat(reminder.blockedReason()).contains("fully paid");
    }

    // ── Amounts, payment type and fallbacks ────────────────────────────────────

    @Test
    void thePartPaidBalanceIsWhatTheMessageAsksFor() {
        InvoiceReminder reminder = build(TODAY, "3000.00", "PARTIAL", "9876543210");

        assertThat(reminder.dueAmount()).isEqualByComparingTo("5500.00");
        assertThat(reminder.message()).contains("₹5,500");
    }

    @Test
    void anOverpaymentNeverBecomesANegativeDue() {
        InvoiceReminder reminder = build(TODAY, "9000.00", "PENDING", "9876543210");

        assertThat(reminder.dueAmount()).isEqualByComparingTo(BigDecimal.ZERO);
        assertThat(reminder.canRemind()).isFalse();
    }

    @Test
    void aTempStayInvoiceIsDescribedAsATemporaryStay() {
        InvoiceReminder reminder = service.build(new InvoiceReminderService.ReminderInput(
                "Ravi Kumar", "9876543210", "Sri Lakshmi PG", List.of("TEMP_STAY"),
                TODAY, RENT, BigDecimal.ZERO, "PENDING"));

        assertThat(reminder.paymentType()).isEqualTo("Temporary Stay");
        assertThat(reminder.message()).contains("your Temporary Stay at");
        assertThat(reminder.message()).contains("🧾 Payment: Temporary Stay");
    }

    /**
     * A tenant with no property membership is normal here — added before any property existed, or
     * through the org-level self check-in link. The sentence still has to read properly, and the
     * sign-off drops the property rather than reading "— your PG · PG Manager".
     */
    @Test
    void aTenantWithNoPropertyStillGetsAReadableSentence() {
        InvoiceReminder reminder = service.build(new InvoiceReminderService.ReminderInput(
                "Ravi Kumar", "9876543210", null, List.of("MONTHLY_RENT"),
                TODAY, RENT, BigDecimal.ZERO, "PENDING"));

        assertThat(reminder.message()).contains("at your PG is due today");
        assertThat(reminder.message()).endsWith("\n\nPG Manager");
    }

    // ── Row coercion, as BillingController hands it over ───────────────────────

    @Test
    void buildsFromTheInvoiceDetailRowIncludingSqlDateAndBigDecimal() {
        Map<String, Object> row = new HashMap<>();
        row.put("full_name", "Ravi Kumar");
        row.put("mobile_number", "9876543210");
        row.put("property_name", "Sri Lakshmi PG");
        row.put("due_date", java.sql.Date.valueOf(TODAY));
        row.put("total_amount", RENT);
        row.put("paid_amount", BigDecimal.ZERO);
        row.put("status", "PENDING");

        InvoiceReminder reminder = service.fromInvoiceRow(row, List.of("MONTHLY_RENT", "AC_CHARGES"));

        assertThat(reminder.status()).isEqualTo("DUE");
        assertThat(reminder.canRemind()).isTrue();
        assertThat(reminder.tenantName()).isEqualTo("Ravi Kumar");
        assertThat(reminder.whatsappNumber()).isEqualTo("919876543210");
        assertThat(reminder.paymentType()).isEqualTo("Monthly Rent");
    }

    /** A brand-new invoice row can have a null mobile; coercion must not NPE on the way through. */
    @Test
    void aRowWithNullsCoercesWithoutBlowingUp() {
        Map<String, Object> row = new HashMap<>();
        row.put("total_amount", RENT);
        row.put("paid_amount", null);
        row.put("status", "PENDING");

        InvoiceReminder reminder = service.fromInvoiceRow(row, List.of());

        assertThat(reminder.status()).isEqualTo("NOT_DUE");
        assertThat(reminder.canRemind()).isFalse();
    }
}
