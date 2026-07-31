package com.pgmanager.billing;

import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;

/**
 * Shared write-path for a tenant's move-in billing.
 *
 * <p>Creates the billing account and the move-in invoice (base rent + optional AC
 * breakdown + the one-time security deposit), and — for data imports — can backfill
 * already-settled invoices for historical months so an imported tenant looks exactly
 * like one who has been billed and paid month after month in the app.
 *
 * <p>Used by {@code OccupancyController} (in-app assign / make-permanent) and
 * {@code BulkUploadController} (CSV tenant import) so both go through identical SQL.
 */
@Service
@RequiredArgsConstructor
public class MoveInBillingService {
    private final JdbcTemplate jdbc;

    /** Finds or creates the tenant's ACTIVE billing account, returning its id. */
    public Long ensureBillingAccount(Long org, Long partyId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT billing_account_id FROM billing_account WHERE organization_id=? AND party_id=? AND status='ACTIVE' LIMIT 1",
                org, partyId);
        if (!rows.isEmpty()) return ((Number) rows.getFirst().get("billing_account_id")).longValue();
        return jdbc.queryForObject(
                "INSERT INTO billing_account(organization_id,party_id,currency_code,status,advance_balance,created_at,updated_at,version) " +
                        "VALUES(?,?,'INR','ACTIVE',0,?,?,0) RETURNING billing_account_id",
                Long.class, org, partyId, LocalDateTime.now(), LocalDateTime.now());
    }

    /**
     * Ensures the move-in invoice exists for the tenant's first billing month. The
     * invoice carries MONTHLY_RENT (base = rent - AC), optional AC_CHARGES, and the
     * one-time SECURITY_DEPOSIT. No-op if that month's invoice already exists.
     */
    public Long bootstrapMoveIn(Long org, Long partyId, LocalDate moveInDate,
                                BigDecimal monthlyRent, BigDecimal acCharges, BigDecimal securityDeposit) {
        Long baId = ensureBillingAccount(org, partyId);
        LocalDate moveIn = moveInDate != null ? moveInDate : LocalDate.now();
        createInvoiceForMonth(org, baId, YearMonth.from(moveIn), moveIn, monthlyRent, acCharges, securityDeposit);
        return baId;
    }

    /**
     * Creates a one-time invoice for a temporary stay's charge (a single TEMP_STAY line
     * item). Unlike the monthly move-in invoice this is not tied to a billing month, so
     * it uses a stay-dated invoice number and is idempotent on it (safe to re-run).
     * No-op when {@code amount} is null or non-positive.
     *
     * @return the billing account id, or null when nothing was charged
     */
    public Long bootstrapTempStay(Long org, Long partyId, LocalDate startDate, BigDecimal amount) {
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) return null;
        Long baId = ensureBillingAccount(org, partyId);
        LocalDate date = startDate != null ? startDate : LocalDate.now();
        LocalDate invoiceMonth = YearMonth.from(date).atDay(1);
        String invNum = "TEMP-" + org + "-" + baId + "-" + date.toString().replace("-", "");
        Long exists = jdbc.queryForObject("SELECT COUNT(*) FROM invoice WHERE organization_id=? AND invoice_number=?",
                Long.class, org, invNum);
        if (exists != null && exists > 0) return baId;

        LocalDateTime now = LocalDateTime.now();
        Long invoiceId = jdbc.queryForObject(
                "INSERT INTO invoice(organization_id,billing_account_id,invoice_number,invoice_month,issue_date,due_date," +
                        "total_amount,paid_amount,status,created_at,updated_at,version) VALUES(?,?,?,?,?,?,?,0,'PENDING',?,?,0) " +
                        "RETURNING invoice_id",
                Long.class, org, baId, invNum, invoiceMonth, date, date, amount, now, now);
        jdbc.update("INSERT INTO invoice_item(invoice_id,item_type_id,description,amount,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                invoiceId, "TEMP_STAY", "Temporary Stay Charge", amount, now, now);
        return baId;
    }

    /**
     * Updates the temporary-stay invoice's total to {@code newAmount} (recomputed after an
     * edit — e.g. changed check-out date or per-day override). Creates the invoice if it
     * doesn't exist yet and {@code newAmount > 0}. The invoice is located by the same
     * stay-dated number used at creation, so {@code startDate} must be the stay's original
     * check-in. Refuses to drop the total below what's already been paid.
     */
    public void updateTempStayInvoice(Long org, Long partyId, LocalDate startDate, BigDecimal newAmount) {
        Long baId = ensureBillingAccount(org, partyId);
        LocalDate date = startDate != null ? startDate : LocalDate.now();
        String invNum = "TEMP-" + org + "-" + baId + "-" + date.toString().replace("-", "");
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT invoice_id,paid_amount FROM invoice WHERE organization_id=? AND invoice_number=? LIMIT 1",
                org, invNum);
        if (rows.isEmpty()) {
            bootstrapTempStay(org, partyId, date, newAmount);
            return;
        }
        BigDecimal amount = newAmount != null ? newAmount : BigDecimal.ZERO;
        Long invoiceId = ((Number) rows.getFirst().get("invoice_id")).longValue();
        BigDecimal paid = decimal(rows.getFirst().get("paid_amount"));
        if (amount.compareTo(paid) < 0) {
            throw new org.springframework.dao.InvalidDataAccessApiUsageException(
                    "New amount (" + amount + ") is less than already paid (" + paid + ")");
        }
        String status = paid.compareTo(BigDecimal.ZERO) <= 0 ? "PENDING"
                : (paid.compareTo(amount) >= 0 ? "PAID" : "PARTIAL");
        LocalDateTime now = LocalDateTime.now();
        jdbc.update("UPDATE invoice SET total_amount=?,status=?,updated_at=?,version=version+1 WHERE invoice_id=?",
                amount, status, now, invoiceId);
        jdbc.update("UPDATE invoice_item SET amount=?,updated_at=? WHERE invoice_id=? AND item_type_id='TEMP_STAY'",
                amount, now, invoiceId);
    }

    /**
     * Backfills already-paid history: for every month from the move-in month through
     * {@code paidUpTo} (inclusive) it ensures the invoice exists (the first month also
     * carries the deposit) and records a full payment settling it. Safe to re-run —
     * existing invoices are reused and each invoice is settled at most once.
     *
     * @return the number of months for which a payment was newly recorded
     */
    public int backfillPaidHistory(Long org, Long partyId, LocalDate moveInDate,
                                   BigDecimal monthlyRent, BigDecimal acCharges, BigDecimal securityDeposit,
                                   YearMonth paidUpTo, String method) {
        Long baId = ensureBillingAccount(org, partyId);
        LocalDate moveIn = moveInDate != null ? moveInDate : LocalDate.now();
        YearMonth start = YearMonth.from(moveIn);
        if (paidUpTo == null || paidUpTo.isBefore(start)) return 0;
        String payMethod = (method == null || method.isBlank()) ? "CASH" : method.trim().toUpperCase();
        int paid = 0;
        for (YearMonth ym = start; !ym.isAfter(paidUpTo); ym = ym.plusMonths(1)) {
            boolean isMoveIn = ym.equals(start);
            Long invoiceId = createInvoiceForMonth(org, baId, ym, moveIn,
                    monthlyRent, acCharges, isMoveIn ? securityDeposit : BigDecimal.ZERO);
            if (invoiceId == null) invoiceId = existingInvoiceId(baId, ym);
            if (invoiceId != null && settleInvoice(org, partyId, invoiceId, payMethod)) paid++;
        }
        return paid;
    }

    /**
     * On converting a <b>bed allocation</b> to a permanent bed: carries any payment made
     * on the allocation's one-time {@code TEMP-…} invoice onto the newly created move-in
     * invoice (as an advance credit, so it shows PARTIAL/PAID and only the balance is due),
     * then <b>voids</b> the now-superseded TEMP invoice so the money is never counted twice.
     * Any credit beyond the move-in total is parked on the billing account's advance balance.
     *
     * <p>Keyed off {@code startDate} = the allocation's check-in (the move-in anchor), so the
     * TEMP invoice number and the move-in month both resolve from the same date. No-op when
     * there is no TEMP invoice for that date.
     */
    public void carryTempCreditToMoveIn(Long org, Long partyId, LocalDate startDate) {
        Long baId = ensureBillingAccount(org, partyId);
        LocalDate date = startDate != null ? startDate : LocalDate.now();
        String tempNum = "TEMP-" + org + "-" + baId + "-" + date.toString().replace("-", "");
        List<Map<String, Object>> tempRows = jdbc.queryForList(
                "SELECT invoice_id,paid_amount FROM invoice WHERE organization_id=? AND invoice_number=? AND status<>'CANCELLED' LIMIT 1",
                org, tempNum);
        if (tempRows.isEmpty()) return;
        Long tempId = ((Number) tempRows.getFirst().get("invoice_id")).longValue();
        BigDecimal tempPaid = decimal(tempRows.getFirst().get("paid_amount"));

        LocalDate invoiceMonth = YearMonth.from(date).atDay(1);
        List<Map<String, Object>> moveRows = jdbc.queryForList(
                "SELECT invoice_id,total_amount,paid_amount FROM invoice WHERE billing_account_id=? " +
                        "AND invoice_month=? AND invoice_number LIKE 'INV-%' LIMIT 1",
                baId, invoiceMonth);
        LocalDateTime now = LocalDateTime.now();
        if (moveRows.isEmpty()) {
            voidTempInvoice(tempId, now); // nothing to credit onto — just drop the temp charge
            return;
        }
        Long moveId = ((Number) moveRows.getFirst().get("invoice_id")).longValue();
        BigDecimal moveTotal = decimal(moveRows.getFirst().get("total_amount"));
        BigDecimal movePaid = decimal(moveRows.getFirst().get("paid_amount"));

        if (tempPaid.compareTo(BigDecimal.ZERO) > 0) {
            // Re-point the payment allocation(s) from the temp invoice to the move-in invoice
            // (preserves the link to the actual payment records).
            jdbc.update("UPDATE payment_allocation SET invoice_id=? WHERE invoice_id=?", moveId, tempId);
            BigDecimal room = moveTotal.subtract(movePaid).max(BigDecimal.ZERO);
            BigDecimal credit = tempPaid.min(room);
            BigDecimal newPaid = movePaid.add(credit);
            String status = newPaid.compareTo(moveTotal) >= 0 ? "PAID"
                    : (newPaid.compareTo(BigDecimal.ZERO) > 0 ? "PARTIAL" : "PENDING");
            jdbc.update("UPDATE invoice SET paid_amount=?,status=?,updated_at=?,version=version+1 WHERE invoice_id=?",
                    newPaid, status, now, moveId);
            BigDecimal excess = tempPaid.subtract(credit);
            if (excess.compareTo(BigDecimal.ZERO) > 0) {
                jdbc.update("UPDATE billing_account SET advance_balance=advance_balance+?,updated_at=?,version=version+1 " +
                        "WHERE billing_account_id=?", excess, now, baId);
            }
        }
        voidTempInvoice(tempId, now);
    }

    /**
     * Outstanding balance across the party's active (non-cancelled) {@code TEMP-…}
     * allocation invoices, i.e. {@code sum(total_amount - paid_amount)}. Read-only —
     * never creates a billing account (returns ZERO when the party has none).
     * Used to block make-permanent until the temporary invoice is settled.
     */
    public BigDecimal outstandingTempBalance(Long org, Long partyId) {
        List<Map<String, Object>> baRows = jdbc.queryForList(
                "SELECT billing_account_id FROM billing_account WHERE organization_id=? AND party_id=? AND status='ACTIVE' LIMIT 1",
                org, partyId);
        if (baRows.isEmpty()) return BigDecimal.ZERO;
        Long baId = ((Number) baRows.getFirst().get("billing_account_id")).longValue();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT total_amount, paid_amount FROM invoice WHERE billing_account_id=? AND organization_id=? " +
                        "AND invoice_number LIKE 'TEMP-%' AND status<>'CANCELLED'",
                baId, org);
        BigDecimal balance = BigDecimal.ZERO;
        for (Map<String, Object> r : rows) {
            balance = balance.add(decimal(r.get("total_amount")).subtract(decimal(r.get("paid_amount"))));
        }
        return balance.max(BigDecimal.ZERO);
    }

    private void voidTempInvoice(Long invoiceId, LocalDateTime now) {
        jdbc.update("UPDATE invoice SET total_amount=0,paid_amount=0,status='CANCELLED',updated_at=?,version=version+1 " +
                "WHERE invoice_id=?", now, invoiceId);
        jdbc.update("UPDATE invoice_item SET amount=0,updated_at=? WHERE invoice_id=? AND item_type_id='TEMP_STAY'",
                now, invoiceId);
    }

    // ── internals ────────────────────────────────────────────────────────────

    /** Creates the invoice + line items for the given month; returns its id, or null if it already exists. */
    private Long createInvoiceForMonth(Long org, Long baId, YearMonth month, LocalDate moveIn,
                                       BigDecimal monthlyRent, BigDecimal acCharges, BigDecimal securityDeposit) {
        LocalDate invoiceMonth = month.atDay(1);
        Long exists = jdbc.queryForObject("SELECT COUNT(*) FROM invoice WHERE billing_account_id=? AND invoice_month=?",
                Long.class, baId, invoiceMonth);
        if (exists != null && exists > 0) return null;

        BigDecimal rent = monthlyRent != null ? monthlyRent : BigDecimal.ZERO;
        BigDecimal deposit = securityDeposit != null ? securityDeposit : BigDecimal.ZERO;
        // monthlyRent already includes the AC premium; acCharges only splits the line items.
        BigDecimal ac = acCharges != null ? acCharges : BigDecimal.ZERO;
        if (ac.compareTo(BigDecimal.ZERO) < 0 || ac.compareTo(rent) > 0) ac = BigDecimal.ZERO;
        BigDecimal baseRent = rent.subtract(ac);

        // The move-in month keeps its exact join date as issue/due; later months issue
        // on the 1st and fall due on the move-in day-of-month (mirrors generate-invoices).
        boolean firstMonth = month.equals(YearMonth.from(moveIn));
        LocalDate issueDate = firstMonth ? moveIn : invoiceMonth;
        LocalDate dueDate = firstMonth ? moveIn
                : invoiceMonth.withDayOfMonth(Math.min(moveIn.getDayOfMonth(), invoiceMonth.lengthOfMonth()));

        String invNum = "INV-" + org + "-" + baId + "-" + invoiceMonth.toString().substring(0, 7).replace("-", "");
        Long invoiceId = jdbc.queryForObject(
                "INSERT INTO invoice(organization_id,billing_account_id,invoice_number,invoice_month,issue_date,due_date," +
                        "total_amount,paid_amount,status,created_at,updated_at,version) VALUES(?,?,?,?,?,?,?,0,'PENDING',?,?,0) " +
                        "RETURNING invoice_id",
                Long.class, org, baId, invNum, invoiceMonth, issueDate, dueDate, rent.add(deposit),
                LocalDateTime.now(), LocalDateTime.now());
        if (baseRent.compareTo(BigDecimal.ZERO) > 0) {
            jdbc.update("INSERT INTO invoice_item(invoice_id,item_type_id,description,amount,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                    invoiceId, "MONTHLY_RENT", "Monthly Rent", baseRent, LocalDateTime.now(), LocalDateTime.now());
        }
        if (ac.compareTo(BigDecimal.ZERO) > 0) {
            jdbc.update("INSERT INTO invoice_item(invoice_id,item_type_id,description,amount,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                    invoiceId, "AC_CHARGES", "AC Charges", ac, LocalDateTime.now(), LocalDateTime.now());
        }
        if (deposit.compareTo(BigDecimal.ZERO) > 0) {
            jdbc.update("INSERT INTO invoice_item(invoice_id,item_type_id,description,amount,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                    invoiceId, "SECURITY_DEPOSIT", "Security Deposit (one-time)", deposit, LocalDateTime.now(), LocalDateTime.now());
        }
        return invoiceId;
    }

    private Long existingInvoiceId(Long baId, YearMonth month) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT invoice_id FROM invoice WHERE billing_account_id=? AND invoice_month=? LIMIT 1",
                baId, month.atDay(1));
        return rows.isEmpty() ? null : ((Number) rows.getFirst().get("invoice_id")).longValue();
    }

    /**
     * Records a full payment settling the invoice's remaining balance and marks it PAID.
     * Idempotent per invoice via a deterministic idempotency key. Returns true if a
     * payment was newly recorded (false if already settled or previously imported).
     */
    private boolean settleInvoice(Long org, Long partyId, Long invoiceId, String method) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT total_amount,paid_amount,due_date FROM invoice WHERE invoice_id=? AND organization_id=? FOR UPDATE",
                invoiceId, org);
        if (rows.isEmpty()) return false;
        BigDecimal balance = decimal(rows.getFirst().get("total_amount")).subtract(decimal(rows.getFirst().get("paid_amount")));
        if (balance.compareTo(BigDecimal.ZERO) <= 0) return false;
        LocalDate payDate = rows.getFirst().get("due_date") != null
                ? ((java.sql.Date) rows.getFirst().get("due_date")).toLocalDate() : LocalDate.now();
        String ikey = "bulk-backfill-" + org + "-" + invoiceId;
        Long paymentId;
        try {
            paymentId = jdbc.queryForObject(
                    "INSERT INTO payment(organization_id,party_id,amount,payment_mode,payment_date,notes," +
                            "idempotency_key,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,'RECEIVED',?,?) " +
                            "RETURNING payment_id",
                    Long.class, org, partyId, balance, method, payDate, "Imported historical payment", ikey,
                    LocalDateTime.now(), LocalDateTime.now());
        } catch (DuplicateKeyException dup) {
            return false;
        }
        jdbc.update("INSERT INTO payment_allocation(organization_id,payment_id,invoice_id,amount,allocated_at) VALUES(?,?,?,?,?)",
                org, paymentId, invoiceId, balance, LocalDateTime.now());
        jdbc.update("UPDATE invoice SET paid_amount=total_amount,status='PAID',updated_at=?,version=version+1 WHERE invoice_id=?",
                LocalDateTime.now(), invoiceId);
        return true;
    }

    private BigDecimal decimal(Object value) {
        return value instanceof BigDecimal d ? d : new BigDecimal(value.toString());
    }
}
