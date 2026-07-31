package com.pgmanager.expense;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * Shared write path for expense + petty-cash ledger rows so other modules
 * (e.g. staff salary payments) record spend through the same rules as
 * ExpenseController: approved expenses paid in CASH mirror an OUT row into
 * the petty-cash ledger, idempotently per expense.
 */
@Component
@RequiredArgsConstructor
public class ExpenseWriter {
    private final JdbcTemplate jdbc;

    /** Inserts an already-approved expense and returns its id. */
    public Long insertApproved(Long organizationId, Long propertyId, String category, String title,
                               BigDecimal amount, String paymentMethod, LocalDate date, Long userLoginId) {
        LocalDateTime now = LocalDateTime.now();
        Long expenseId = jdbc.queryForObject(
                "INSERT INTO expense(organization_id,property_facility_id,category,title,amount,expense_date," +
                        "payment_method,status,approved_by,approved_at,created_by,created_at,updated_at) " +
                        "VALUES(?,?,?,?,?,?,?,'APPROVED',?,?,?,?,?) RETURNING expense_id",
                Long.class, organizationId, propertyId, category, title, amount, date, paymentMethod,
                userLoginId, now, userLoginId, now, now);
        if ("CASH".equals(paymentMethod)) {
            recordCashOut(organizationId, propertyId, expenseId, amount, title, date, userLoginId);
        }
        return expenseId;
    }

    /** OUT ledger row mirrored from an approved CASH expense (idempotent per expense). */
    public void recordCashOut(Long organizationId, Long propertyId, Long expenseId, BigDecimal amount,
                              String note, LocalDate date, Long userLoginId) {
        Long exists = jdbc.queryForObject("SELECT COUNT(*) FROM petty_cash_entry WHERE organization_id=? AND expense_id=?",
                Long.class, organizationId, expenseId);
        if (exists != null && exists > 0) return;
        jdbc.update("INSERT INTO petty_cash_entry(organization_id,property_facility_id,entry_type,amount,note,entry_date," +
                        "expense_id,created_by,created_at,updated_at) VALUES(?,?,'OUT',?,?,?,?,?,LOCALTIMESTAMP,LOCALTIMESTAMP)",
                organizationId, propertyId != null ? propertyId : 0L, amount, note, date, expenseId, userLoginId);
    }
}
