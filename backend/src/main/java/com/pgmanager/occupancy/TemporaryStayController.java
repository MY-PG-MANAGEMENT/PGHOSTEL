package com.pgmanager.occupancy;

import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.cache.CacheConfig;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.security.PropertyAccessGuard;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Date;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Property-scoped read model for the Temporary Stay screen. Temporary stays are
 * {@code facility_party} rows (role {@code TEMP_OCCUPANT}) — check-in in {@code from_date},
 * planned check-out in {@code expected_checkout_date}, actual check-out in {@code thru_date},
 * and the (editable) total charge in {@code monthly_rent}. The one-time invoice (if any)
 * is matched by its stay-dated {@code TEMP-…} number for payment status.
 *
 * <p>JdbcTemplate is used for the aggregate join (same rationale as billing/transactions).
 */
@RestController
@RequestMapping("/api/occupancy")
@RequiredArgsConstructor
public class TemporaryStayController {

    private final JdbcTemplate jdbc;
    private final CurrentUser currentUser;
    private final PropertyAccessGuard propertyAccessGuard;

    private static final String LIST_SQL = """
            SELECT fp.facility_party_id, fp.party_id, fp.facility_id AS bed_id,
                   fp.from_date, fp.expected_checkout_date, fp.thru_date, fp.monthly_rent AS amount,
                   fp.security_deposit AS security_deposit,
                   bed.facility_name AS bed_name,
                   room.facility_name AS room_name, room.sharing_type,
                   floor.facility_name AS floor_name,
                   p.full_name, p.mobile_number, p.gender,
                   inv.invoice_id AS inv_id, inv.total_amount AS inv_total, inv.paid_amount AS inv_paid
            FROM facility_party fp
            JOIN facility bed ON bed.facility_id = fp.facility_id AND bed.facility_type_id = 'BED'
            JOIN facility_group_member gmb ON gmb.child_facility_id = bed.facility_id AND gmb.thru_date IS NULL
            JOIN facility room ON room.facility_id = gmb.parent_facility_id
            JOIN facility_group_member gmf ON gmf.child_facility_id = room.facility_id AND gmf.thru_date IS NULL
            JOIN facility floor ON floor.facility_id = gmf.parent_facility_id
            JOIN facility_group_member gmp ON gmp.child_facility_id = floor.facility_id AND gmp.thru_date IS NULL
            JOIN facility prop ON prop.facility_id = gmp.parent_facility_id AND prop.facility_type_id = 'PROPERTY'
            JOIN person p ON p.party_id = fp.party_id
            LEFT JOIN billing_account ba ON ba.organization_id = fp.organization_id
                     AND ba.party_id = fp.party_id AND ba.status = 'ACTIVE'
            LEFT JOIN invoice inv ON inv.billing_account_id = ba.billing_account_id
                     AND inv.invoice_number = CONCAT('TEMP-', fp.organization_id, '-', ba.billing_account_id, '-',
                                                     DATE_FORMAT(fp.from_date, '%Y%m%d'))
            WHERE fp.organization_id = ? AND fp.role_type_id = 'TEMP_OCCUPANT' AND prop.facility_id = ?
            ORDER BY fp.from_date DESC
            """;

    // Cached per org:property:status:q; evicted wholesale on every temp-stay / occupancy
    // write (see OccupancyService). null status/q are normalized in the key.
    @Cacheable(cacheNames = CacheConfig.TEMP_STAYS,
            key = "@currentUser.organizationId() + ':' + #propertyId + ':' + (#status == null ? '' : #status) + ':' + (#q == null ? '' : #q)")
    @GetMapping("/temp-stays")
    ApiResponse<Map<String, Object>> list(@RequestParam Long propertyId,
                                          @RequestParam(required = false) String status,
                                          @RequestParam(required = false) String q) {
        propertyAccessGuard.assertCanAccess(propertyId);
        Long org = currentUser.organizationId();
        LocalDate today = LocalDate.now();
        List<Map<String, Object>> rows = jdbc.queryForList(LIST_SQL, org, propertyId);

        List<Map<String, Object>> all = new ArrayList<>(rows.size());
        int active = 0, todayCheckins = 0, todayCheckouts = 0, guests = 0;
        for (Map<String, Object> r : rows) {
            LocalDate from = toLocal(r.get("from_date"));
            LocalDate checkout = toLocal(r.get("expected_checkout_date"));
            LocalDate thru = toLocal(r.get("thru_date"));
            String bookingStatus = bookingStatus(from, checkout, thru, today);
            Long remaining = (thru == null && checkout != null) ? ChronoUnit.DAYS.between(today, checkout) : null;
            long days = (from != null && checkout != null)
                    ? Math.max(1, ChronoUnit.DAYS.between(from, checkout)) : 1;

            BigDecimal amount = decimal(r.get("amount"));
            Long invId = r.get("inv_id") != null ? ((Number) r.get("inv_id")).longValue() : null;
            BigDecimal invTotal = r.get("inv_total") != null ? decimal(r.get("inv_total")) : null;
            BigDecimal invPaid = r.get("inv_paid") != null ? decimal(r.get("inv_paid")) : BigDecimal.ZERO;
            BigDecimal perDay = days > 0 ? amount.divide(BigDecimal.valueOf(days), 2, RoundingMode.HALF_UP) : amount;
            // For a bed allocation, monthly_rent holds the future permanent rent (not the
            // charge), so the card's total/paid/due come from the one-time TEMP invoice.
            boolean allocation = checkout == null && thru == null;
            BigDecimal displayTotal = invTotal != null ? invTotal : (allocation ? invPaid : amount);
            BigDecimal deposit = r.get("security_deposit") != null ? decimal(r.get("security_deposit")) : null;
            // Outstanding is only collectable when a TEMP invoice exists; extending a
            // stay re-totals that invoice, so a previously-paid stay can go PARTIAL.
            BigDecimal due = (invId != null && invTotal != null)
                    ? invTotal.subtract(invPaid).max(BigDecimal.ZERO) : BigDecimal.ZERO;

            if (thru == null) {
                guests++;
                if (!"UPCOMING".equals(bookingStatus)) active++;
            }
            if (from != null && from.equals(today)) todayCheckins++;
            if (thru == null && checkout != null && checkout.equals(today)) todayCheckouts++;

            Map<String, Object> item = new LinkedHashMap<>();
            item.put("facilityPartyId", r.get("facility_party_id"));
            item.put("partyId", r.get("party_id"));
            item.put("bedFacilityId", r.get("bed_id"));
            item.put("bedName", r.get("bed_name"));
            item.put("roomName", r.get("room_name"));
            item.put("floorName", r.get("floor_name"));
            item.put("sharingType", r.get("sharing_type"));
            item.put("fullName", r.get("full_name"));
            item.put("mobileNumber", r.get("mobile_number"));
            item.put("gender", r.get("gender"));
            item.put("checkInDate", from != null ? from.toString() : null);
            item.put("checkOutDate", checkout != null ? checkout.toString() : null);
            item.put("actualCheckOutDate", thru != null ? thru.toString() : null);
            item.put("totalDays", days);
            item.put("pricePerDay", perDay);
            item.put("totalAmount", displayTotal);
            // Future permanent rent + deposit captured at allocation time (prefilled at
            // make-permanent). For a regular temp stay monthlyRent mirrors the charge.
            item.put("monthlyRent", amount);
            item.put("securityDeposit", deposit);
            item.put("paidAmount", invPaid);
            item.put("dueAmount", due);
            item.put("invoiceId", invId);
            item.put("paymentStatus", paymentStatus(invTotal, invPaid));
            item.put("bookingStatus", bookingStatus);
            item.put("remainingDays", remaining);
            all.add(item);
        }

        // Filter for the list view (summary above is computed over everything).
        String wantStatus = status == null || status.isBlank() || status.equalsIgnoreCase("ALL")
                ? null : status.trim().toUpperCase();
        String query = q == null ? "" : q.trim().toLowerCase();
        List<Map<String, Object>> items = new ArrayList<>();
        for (Map<String, Object> it : all) {
            if (wantStatus != null && !wantStatus.equals(it.get("bookingStatus"))) continue;
            if (!query.isEmpty()) {
                String hay = (str(it.get("fullName")) + " " + str(it.get("mobileNumber")) + " "
                        + str(it.get("roomName")) + " " + str(it.get("bedName")) + " "
                        + str(it.get("floorName"))).toLowerCase();
                if (!hay.contains(query)) continue;
            }
            items.add(it);
        }

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("totalGuests", guests);
        summary.put("active", active);
        summary.put("todayCheckins", todayCheckins);
        summary.put("todayCheckouts", todayCheckouts);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("summary", summary);
        out.put("items", items);
        return ApiResponse.ok(out);
    }

    private static String bookingStatus(LocalDate from, LocalDate checkout, LocalDate thru, LocalDate today) {
        if (thru != null) return "CHECKED_OUT";
        if (from != null && from.isAfter(today)) return "UPCOMING";
        if (checkout != null) {
            if (checkout.isBefore(today)) return "OVERDUE";
            if (checkout.isEqual(today)) return "CHECKOUT_TODAY";
        }
        return "ACTIVE";
    }

    private static String paymentStatus(BigDecimal total, BigDecimal paid) {
        if (total == null || total.compareTo(BigDecimal.ZERO) <= 0) return "NONE";
        if (paid.compareTo(total) >= 0) return "PAID";
        if (paid.compareTo(BigDecimal.ZERO) > 0) return "PARTIAL";
        return "PENDING";
    }

    private static LocalDate toLocal(Object v) {
        return v == null ? null : ((Date) v).toLocalDate();
    }

    private static BigDecimal decimal(Object v) {
        if (v == null) return BigDecimal.ZERO;
        return v instanceof BigDecimal d ? d : new BigDecimal(v.toString());
    }

    private static String str(Object v) {
        return v == null ? "" : v.toString();
    }
}
