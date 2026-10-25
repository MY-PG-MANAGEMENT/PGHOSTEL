package com.pgmanager.whatsapp;

import java.math.BigDecimal;
import java.text.DecimalFormat;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.List;

/**
 * Turns an invoice's facts into the reminder text a tenant reads.
 *
 * <p><b>This class is the Phase 2 survivor.</b> Phase 1 delivers the message as a
 * {@code wa.me} deep link that the owner sends by hand; Phase 2 will hand the same text (or the
 * same parameters) to the WhatsApp Cloud API. Everything that decides <i>what the message says</i>
 * lives here, and nothing here knows or cares <i>how it travels</i> — no URL building, no HTTP, no
 * provider. Swapping the delivery mechanism must not touch this file.
 *
 * <p>It is deliberately a pure static function of its inputs, with no Spring dependencies, so the
 * wording is verified in a plain unit test rather than through a controller.
 *
 * <p>It also lives on the <b>backend</b> rather than in the Flutter app on purpose. Building the
 * text in Dart would work fine for deep linking and then have to be rewritten for Phase 2, where
 * the message (and eventually the approved template parameters) must be assembled server-side.
 */
public final class InvoiceReminderMessageBuilder {

    /** {@code 08-Aug-2026}. Matches the date style {@code NotificationService} uses for emails. */
    private static final DateTimeFormatter DUE_DATE = DateTimeFormatter.ofPattern("dd-MMM-yyyy");

    /** Grouped, and no trailing {@code .00}: {@code 8500.00} renders as {@code 8,500}. */
    private static final String AMOUNT_PATTERN = "#,##0.##";

    /** Signs the message off so a tenant knows the number is their PG, not a stranger. */
    private static final String SENDER = "PG Manager";

    private InvoiceReminderMessageBuilder() {
    }

    /**
     * The reminder body for a sendable status.
     *
     * <p>The three variants share one layout — greeting, one-line lead, a labelled detail block, a
     * closing line and a signature — and differ only in tone and the status line, so a tenant who has
     * had one reminder recognises the next at a glance.
     *
     * <p><b>Deliberately plain text: no {@code *bold*}, no {@code _italic_}, no banner, no rule.</b>
     * WhatsApp markup renders as literal asterisks in a notification preview, in a chat export, and
     * anywhere the message is quoted or forwarded — a payment reminder is a business document and has
     * to read cleanly everywhere, not just inside the chat bubble. Emoji are kept as line markers
     * because they render as glyphs in all of those places. Labels are plain {@code "Label: value"}
     * rather than space-padded columns: WhatsApp renders in a proportional font, so a padded column
     * that lines up in the editor arrives crooked on the tenant's phone.
     *
     * @param today reference date, injected rather than read from the clock so the "3 days overdue"
     *              line is testable and cannot disagree with the status derived alongside it
     * @throws IllegalArgumentException when {@code status} is not sendable — callers check
     *                                  {@link InvoiceReminderStatus#sendable()} first, and there is
     *                                  no such thing as a reminder for a settled invoice
     */
    public static String build(InvoiceReminderStatus status,
                              String tenantName,
                              String paymentType,
                              String propertyName,
                              BigDecimal dueAmount,
                              LocalDate dueDate,
                              LocalDate today) {
        String name = orFallback(tenantName, "there");
        String type = orFallback(paymentType, "rent");
        String property = orFallback(propertyName, "your PG");
        String amount = formatAmount(dueAmount);
        String date = dueDate == null ? "-" : dueDate.format(DUE_DATE);

        return switch (status) {
            case OVERDUE -> card(name,
                    "Your " + type + " at " + property + " is overdue.",
                    type, date, overdueStatusLine(dueDate, today), amount,
                    "Please clear the pending amount at your earliest convenience. 🙏", propertyName);
            case DUE -> card(name,
                    "A gentle reminder that your " + type + " at " + property + " is due today.",
                    type, date, "Due today", amount,
                    "Paying today keeps your account clear. ✅", propertyName);
            case TOMORROW -> card(name,
                    "Just a heads-up — your " + type + " at " + property + " is due tomorrow.",
                    type, date, "Due in 1 day", amount,
                    "A small reminder so it does not slip by. 🙂", propertyName);
            default -> throw new IllegalArgumentException("No reminder message for status " + status);
        };
    }

    /**
     * The one layout all three reminders are cut from, so a wording change cannot leave the variants
     * looking like messages from three different businesses.
     */
    private static String card(String name,
                               String lead,
                               String paymentType,
                               String dueDate,
                               String statusLine,
                               String amount,
                               String closing,
                               String propertyName) {
        return "Hi " + name + " 👋\n\n"
                + lead + "\n\n"
                + "🧾 Payment: " + paymentType + "\n"
                + "📅 Due date: " + dueDate + "\n"
                + "⏳ Status: " + statusLine + "\n"
                + "💰 Amount due: " + amount + "\n\n"
                + closing + "\n\n"
                + signature(propertyName);
    }

    /**
     * Falls back to the bare product name when the tenant has no property. The lead sentence can say
     * "your PG" and still read, but a sign-off reading "your PG · PG Manager" cannot.
     */
    private static String signature(String propertyName) {
        return propertyName == null || propertyName.isBlank()
                ? SENDER
                : propertyName + " · " + SENDER;
    }

    private static String overdueStatusLine(LocalDate dueDate, LocalDate today) {
        long days = daysLate(dueDate, today);
        if (days <= 0) return "Overdue";
        return days + (days == 1 ? " day overdue" : " days overdue");
    }

    /**
     * Zero when either date is missing. {@code build} is public and its callers need not have a
     * clock, and a reminder that says "0 days overdue" is worse than one that just says "Overdue".
     */
    private static long daysLate(LocalDate dueDate, LocalDate today) {
        if (dueDate == null || today == null) return 0;
        return ChronoUnit.DAYS.between(dueDate, today);
    }

    /** {@code 8500.00} → {@code ₹8,500}. */
    public static String formatAmount(BigDecimal amount) {
        return "₹" + new DecimalFormat(AMOUNT_PATTERN).format(amount == null ? BigDecimal.ZERO : amount);
    }

    /**
     * Human label for what the invoice is charging for, used in the message and shown on the
     * invoice sheet.
     *
     * <p>There is no payment-type column on {@code invoice} — the type is whatever the invoice is
     * mostly made of. A move-in invoice carries rent + AC + deposit, so "Monthly Rent" is the
     * honest summary; a temp-stay invoice is a single {@code TEMP_STAY} line.
     */
    public static String paymentTypeLabel(List<String> itemTypeIds) {
        if (itemTypeIds == null || itemTypeIds.isEmpty()) return "Rent";
        if (itemTypeIds.contains("TEMP_STAY")) return "Temporary Stay";
        if (itemTypeIds.contains("MONTHLY_RENT")) return "Monthly Rent";
        if (itemTypeIds.contains("SECURITY_DEPOSIT")) return "Security Deposit";
        if (itemTypeIds.contains("AC_CHARGES")) return "AC Charges";
        return "Rent";
    }

    /**
     * Keeps the sentence readable when a field is missing rather than emitting "Hello ,". A tenant
     * with no property membership is normal in this schema — added before any property existed, or
     * through the org-level self check-in link.
     */
    private static String orFallback(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
