package com.pgmanager.transaction;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.security.CurrentUser;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Unified money-in / money-out ledger for a month: RECEIVED tenant payments
 * (in) merged with APPROVED/PAID expenses (out). JdbcTemplate — aggregate
 * query across two modules, same rationale as BillingController. Property
 * scoping: payments via the tenant's property-level TENANT membership in
 * facility_party (payments carry no facility id), expenses directly via
 * property_facility_id.
 */
@RestController
@RequestMapping("/api/transactions")
@RequiredArgsConstructor
public class TransactionController {
    private final CurrentUser currentUser;
    private final JdbcTemplate jdbc;

    @GetMapping
    ApiResponse<Map<String, Object>> ledger(@RequestParam(required = false) Long propertyId,
                                            @RequestParam(required = false) String month) {
        Long org = currentUser.organizationId();
        YearMonth ym = parseMonth(month);
        LocalDate start = ym.atDay(1), end = ym.atEndOfMonth();

        String inScope = propertyId != null
                ? " AND p.party_id IN (SELECT fp.party_id FROM facility_party fp WHERE fp.organization_id=? AND fp.facility_id=? AND fp.role_type_id='TENANT')"
                : "";
        Object[] inArgs = propertyId != null
                ? new Object[]{org, start, end, org, propertyId}
                : new Object[]{org, start, end};
        List<Map<String, Object>> payments = jdbc.queryForList(
                "SELECT p.payment_id id, COALESCE(per.full_name, 'Tenant') title, p.amount, " +
                "p.payment_mode method, p.payment_date txnDate " +
                "FROM payment p LEFT JOIN person per ON per.party_id = p.party_id " +
                "WHERE p.organization_id=? AND p.status='RECEIVED' AND p.payment_date BETWEEN ? AND ?" + inScope,
                inArgs);

        String outScope = propertyId != null ? " AND property_facility_id=?" : "";
        Object[] outArgs = propertyId != null
                ? new Object[]{org, start, end, propertyId}
                : new Object[]{org, start, end};
        List<Map<String, Object>> expenses = jdbc.queryForList(
                "SELECT expense_id id, title, category, amount, payment_method method, expense_date txnDate " +
                "FROM expense WHERE organization_id=? AND status IN ('APPROVED','PAID') AND expense_date BETWEEN ? AND ?" + outScope,
                outArgs);

        BigDecimal totalIn = BigDecimal.ZERO, totalOut = BigDecimal.ZERO;
        List<Map<String, Object>> items = new ArrayList<>();
        for (Map<String, Object> p : payments) {
            totalIn = totalIn.add(decimal(p.get("amount")));
            items.add(item("IN", p, null));
        }
        for (Map<String, Object> e : expenses) {
            totalOut = totalOut.add(decimal(e.get("amount")));
            items.add(item("OUT", e, (String) e.get("category")));
        }
        items.sort(Comparator
                .comparing((Map<String, Object> i) -> (LocalDate) i.get("date")).reversed()
                .thenComparing(i -> ((Number) i.get("id")).longValue(), Comparator.reverseOrder()));

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("totalIn", totalIn);
        summary.put("totalOut", totalOut);
        summary.put("net", totalIn.subtract(totalOut));
        summary.put("countIn", payments.size());
        summary.put("countOut", expenses.size());

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("month", ym.toString());
        result.put("summary", summary);
        result.put("items", items);
        return ApiResponse.ok(result);
    }

    private static Map<String, Object> item(String type, Map<String, Object> row, String category) {
        Map<String, Object> item = new LinkedHashMap<>();
        item.put("type", type);
        item.put("id", row.get("id"));
        item.put("title", row.get("title"));
        item.put("category", category);
        item.put("amount", row.get("amount"));
        item.put("method", row.get("method"));
        item.put("date", ((java.sql.Date) row.get("txnDate")).toLocalDate());
        return item;
    }

    private static BigDecimal decimal(Object value) {
        return value == null ? BigDecimal.ZERO : new BigDecimal(value.toString());
    }

    private static YearMonth parseMonth(String month) {
        if (month == null || month.isBlank()) return YearMonth.now();
        try {
            return YearMonth.parse(month);
        } catch (Exception e) {
            throw new BadRequestException("Invalid month format; use YYYY-MM");
        }
    }
}
