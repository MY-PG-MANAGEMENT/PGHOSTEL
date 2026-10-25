package com.pgmanager.whatsapp;

import com.pgmanager.common.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * Builds the WhatsApp payment reminder for an invoice. It does <b>not</b> deliver it.
 *
 * <p>That split is the whole design. Everything that is genuinely business logic — which reminder
 * type applies, what the outstanding amount is, whether a reminder is warranted, what the message
 * says, which number it goes to — is decided here and survives unchanged into Phase 2. The only
 * Phase-1-specific code is the {@code wa.me} URI the Flutter app assembles from
 * {@link InvoiceReminder#whatsappNumber()} and {@link InvoiceReminder#message()}, which is the piece
 * Phase 2 deletes.
 *
 * <p><b>No endpoint of its own.</b> The reminder is attached to the existing
 * {@code GET /api/billing/invoices/{id}} response, which the Flutter invoice sheet already fetches
 * for its charge breakdown — so the icon needs no extra round trip and there is no duplicate API to
 * keep in step. Multi-tenant scoping is therefore inherited from that endpoint
 * ({@code organization_id} predicate + {@code PropertyAccessGuard}); nothing here trusts a
 * client-supplied tenant, property or phone number, because it is never given one.
 *
 * <p>Reads no database of its own either: the caller already has the invoice row, so re-querying
 * would be a second trip for data in hand.
 */
@Service
@RequiredArgsConstructor
public class InvoiceReminderService {

    private final WhatsAppProperties properties;

    /**
     * Builds the reminder from the invoice-detail row and its line-item types.
     *
     * <p>Takes the raw {@code JdbcTemplate} row because that is what {@code BillingController}
     * already holds and how this codebase passes query results around; the coercion lives here so
     * the controller stays a marshaller. The typed {@link #build} below is the testable core.
     */
    public InvoiceReminder fromInvoiceRow(Map<String, Object> row, List<String> itemTypeIds) {
        return build(new ReminderInput(
                asString(row.get("full_name")),
                asString(row.get("mobile_number")),
                asString(row.get("property_name")),
                itemTypeIds,
                asDate(row.get("due_date")),
                asDecimal(row.get("total_amount")),
                asDecimal(row.get("paid_amount")),
                asString(row.get("status"))));
    }

    /**
     * The core. Pure apart from reading today's date and the configured country code.
     *
     * <p>Never throws for an ineligible invoice: this is part of a plain invoice fetch, so a fully
     * paid invoice or a tenant with no phone number returns {@code canRemind = false} plus a reason
     * the app can show. Failing the whole invoice-detail request over a missing mobile number would
     * break the charge breakdown too.
     */
    public InvoiceReminder build(ReminderInput input) {
        // Read the clock once: the status and the "N days overdue" line in the message are derived
        // from the same date, so a build straddling midnight cannot say DUE and "1 day overdue".
        LocalDate today = LocalDate.now();
        InvoiceReminderStatus status = InvoiceReminderStatus.derive(
                input.dueDate(), input.totalAmount(), input.paidAmount(), input.invoiceStatus(), today);

        BigDecimal dueAmount = InvoiceReminderStatus.outstanding(input.totalAmount(), input.paidAmount());
        String paymentType = InvoiceReminderMessageBuilder.paymentTypeLabel(input.itemTypeIds());

        // Normalise the number even when the status blocks the send, so the sheet can report a bad
        // number as well as a settled invoice rather than hiding one behind the other.
        String phone = null;
        String phoneProblem = null;
        try {
            phone = PhoneNumberNormalizer.toE164Digits(input.mobileNumber(), properties.getDefaultCountryCode());
        } catch (BadRequestException e) {
            phoneProblem = e.getMessage();
        }

        if (!status.sendable()) {
            return InvoiceReminder.blocked(status, status.explanation(), input.tenantName(),
                    input.propertyName(), paymentType, dueAmount, input.dueDate(), phone);
        }
        if (phoneProblem != null) {
            return InvoiceReminder.blocked(status, phoneProblem, input.tenantName(),
                    input.propertyName(), paymentType, dueAmount, input.dueDate(), null);
        }

        String message = InvoiceReminderMessageBuilder.build(status, input.tenantName(), paymentType,
                input.propertyName(), dueAmount, input.dueDate(), today);
        return new InvoiceReminder(status.name(), true, null, input.tenantName(), input.propertyName(),
                paymentType, dueAmount, input.dueDate(), phone, message);
    }

    /** The facts a reminder is built from. Typed so {@link #build} is testable without a database. */
    public record ReminderInput(String tenantName,
                                String mobileNumber,
                                String propertyName,
                                List<String> itemTypeIds,
                                LocalDate dueDate,
                                BigDecimal totalAmount,
                                BigDecimal paidAmount,
                                String invoiceStatus) {}

    // ── Row coercion ────────────────────────────────────────────────────────────

    private static String asString(Object value) {
        return value == null ? null : value.toString();
    }

    private static BigDecimal asDecimal(Object value) {
        if (value == null) return BigDecimal.ZERO;
        return value instanceof BigDecimal decimal ? decimal : new BigDecimal(value.toString());
    }

    private static LocalDate asDate(Object value) {
        if (value == null) return null;
        if (value instanceof java.sql.Date date) return date.toLocalDate();
        if (value instanceof LocalDate date) return date;
        if (value instanceof java.time.LocalDateTime dateTime) return dateTime.toLocalDate();
        return LocalDate.parse(value.toString().substring(0, 10));
    }
}
