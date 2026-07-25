package com.pgmanager.billing;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Drops the invoice a checking-out tenant never consumed.
 *
 * <p>{@link InvoiceAutoGenerationScheduler} raises the monthly invoice
 * {@code invoiceLeadDays} <em>before</em> its due date, so a tenant who leaves around
 * that date is holding an invoice for a month they will not stay. Asking the owner to
 * pay or write that off is wrong — the charge never should have existed. Within the
 * grace window it is therefore <strong>hard-deleted</strong> (row + line items), not
 * cancelled: no CANCELLED invoice lingers in the tenant's history.
 *
 * <p>The window is {@code due_date + checkoutGraceDays} (per-org, V27, default 2). With
 * the default lead of 1 day an invoice due on the 26th is dropped for a checkout on the
 * 25th, 26th, 27th or 28th; from the 29th the tenant has consumed enough of the cycle,
 * so the invoice stays and checkout shows Pay / Write Off as before.
 *
 * <p>Never dropped — these fall through to the normal Pay / Write Off flow:
 * <ul>
 *   <li>anything with money against it ({@code paid_amount > 0}, a payment allocation,
 *       or a status other than PENDING — PARTIAL / PAID / WRITTEN_OFF / CANCELLED);</li>
 *   <li>invoices carrying a {@code SECURITY_DEPOSIT} line (the move-in invoice), since
 *       deleting one would erase the deposit charge while the checkout screen still
 *       offers to refund that deposit.</li>
 * </ul>
 */
@Service
@RequiredArgsConstructor
public class CheckoutInvoiceService {
    private final JdbcTemplate jdbc;
    private final BillingConfigService billingConfigService;

    /** An invoice removed at checkout — returned so the caller can audit-log it. */
    public record DroppedInvoice(Long invoiceId, String invoiceNumber, LocalDate dueDate, BigDecimal amount) {}

    /** Invoices that {@link #dropUnconsumedInvoices} would delete for this checkout date. */
    @Transactional(readOnly = true)
    public List<DroppedInvoice> previewUnconsumedInvoices(Long organizationId, Long partyId, LocalDate checkoutDate) {
        return findUnconsumed(organizationId, partyId, checkoutDate, false);
    }

    /**
     * Hard-deletes the unconsumed invoices for {@code partyId} as of {@code checkoutDate}
     * and returns what was removed (empty when there is nothing to drop).
     */
    @Transactional
    public List<DroppedInvoice> dropUnconsumedInvoices(Long organizationId, Long partyId, LocalDate checkoutDate) {
        List<DroppedInvoice> dropped = findUnconsumed(organizationId, partyId, checkoutDate, true);
        for (DroppedInvoice invoice : dropped) {
            jdbc.update("DELETE FROM invoice_item WHERE invoice_id=?", invoice.invoiceId());
            jdbc.update("DELETE FROM invoice WHERE invoice_id=? AND organization_id=?",
                    invoice.invoiceId(), organizationId);
        }
        return dropped;
    }

    private List<DroppedInvoice> findUnconsumed(Long organizationId, Long partyId, LocalDate checkoutDate,
                                                boolean lock) {
        if (partyId == null) return List.of();
        LocalDate date = checkoutDate != null ? checkoutDate : LocalDate.now();
        int graceDays = billingConfigService.get(organizationId).checkoutGraceDays();
        // Drop when checkoutDate <= dueDate + grace, i.e. dueDate >= checkoutDate - grace.
        LocalDate earliestDueDate = date.minusDays(graceDays);

        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT i.invoice_id,i.invoice_number,i.due_date,i.total_amount " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "WHERE i.organization_id=? AND ba.party_id=? AND i.status='PENDING' AND i.paid_amount<=0 " +
                "  AND i.due_date>=? " +
                "  AND NOT EXISTS (SELECT 1 FROM payment_allocation pa WHERE pa.invoice_id=i.invoice_id) " +
                "  AND NOT EXISTS (SELECT 1 FROM invoice_item ii WHERE ii.invoice_id=i.invoice_id " +
                "                    AND ii.item_type_id='SECURITY_DEPOSIT')" +
                (lock ? " FOR UPDATE" : ""),
                organizationId, partyId, earliestDueDate);

        List<DroppedInvoice> invoices = new ArrayList<>();
        for (Map<String, Object> row : rows) {
            invoices.add(new DroppedInvoice(
                    ((Number) row.get("invoice_id")).longValue(),
                    (String) row.get("invoice_number"),
                    toLocalDate(row.get("due_date")),
                    row.get("total_amount") instanceof BigDecimal d ? d : BigDecimal.ZERO));
        }
        return invoices;
    }

    private LocalDate toLocalDate(Object value) {
        if (value instanceof java.sql.Date d) return d.toLocalDate();
        if (value instanceof LocalDate d) return d;
        return null;
    }
}
