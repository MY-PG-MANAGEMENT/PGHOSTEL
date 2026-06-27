package com.pgmanager.notification;

import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.sql.Date;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

@Component
@RequiredArgsConstructor
public class RentReminderScheduler {

    private static final Logger log = LoggerFactory.getLogger(RentReminderScheduler.class);
    private static final DateTimeFormatter DATE_FMT = DateTimeFormatter.ofPattern("dd-MMM-yyyy");

    private final JdbcTemplate jdbc;
    private final NotificationService notificationService;

    @Scheduled(cron = "0 0 9 * * *") // 9 AM every day
    public void runDailyReminders() {
        log.info("Running daily rent and checkout reminders");
        sendRentReminders();
        sendCheckoutReminders();
    }

    // ─── Rent Reminders ───────────────────────────────────────────────────────

    void sendRentReminders() {
        LocalDate today = LocalDate.now();

        List<Map<String, Object>> rents = jdbc.queryForList(
                "SELECT r.rent_id, r.organization_id, r.party_id, r.rent_month, r.monthly_rent, " +
                "       p.full_name, " +
                "       COALESCE(froom.facility_name, '') AS room_name, " +
                "       COALESCE(fbed.facility_name, '')  AS bed_name " +
                "FROM rent r " +
                "JOIN person p ON p.party_id = r.party_id " +
                "LEFT JOIN facility_party fp " +
                "       ON fp.party_id = r.party_id AND fp.organization_id = r.organization_id " +
                "       AND fp.role_type_id = 'OCCUPANT' AND fp.thru_date IS NULL " +
                "LEFT JOIN facility fbed  ON fbed.facility_id = fp.facility_id " +
                "LEFT JOIN facility_group_member fgm " +
                "       ON fgm.child_facility_id = fbed.facility_id AND fgm.thru_date IS NULL " +
                "LEFT JOIN facility froom ON froom.facility_id = fgm.parent_facility_id " +
                "WHERE r.paid_amount < (r.monthly_rent - COALESCE(r.discount,0) + COALESCE(r.penalty,0))"
        );

        for (Map<String, Object> rent : rents) {
            try {
                Long rentId = toLong(rent.get("rent_id"));
                Long orgId  = toLong(rent.get("organization_id"));
                LocalDate dueDate = toLocalDate(rent.get("rent_month"));
                if (dueDate == null) continue;

                long daysUntil = today.until(dueDate, java.time.temporal.ChronoUnit.DAYS);

                // Trigger only on: 5 days before, 1 day before, due date, or overdue (daily)
                if (daysUntil > 5 || (daysUntil > 0 && daysUntil != 5 && daysUntil != 1)) continue;

                if (notificationService.alreadySentToday(orgId, "RENT_REMINDER", "RENT", rentId)) continue;

                String name     = str(rent.get("full_name"));
                String room     = str(rent.get("room_name"));
                String bed      = str(rent.get("bed_name"));
                String location = room.isEmpty() ? (bed.isEmpty() ? "your room" : bed) : room;
                String amount   = str(rent.get("monthly_rent"));
                String dateStr  = dueDate.format(DATE_FMT);

                String title, message;
                boolean important;

                if (daysUntil > 0) {
                    title   = String.format("Rent Due in %d Day%s — %s", daysUntil, daysUntil > 1 ? "s" : "", name);
                    message = String.format(
                            "Dear %s, your PG rent of ₹%s for %s is due on %s. Please make the payment to avoid late charges.",
                            name, amount, location, dateStr);
                    important = daysUntil == 1;
                } else {
                    title   = String.format("Rent Overdue — %s", name);
                    message = String.format(
                            "Dear %s, your PG rent of ₹%s for %s was due on %s. Please make the payment immediately to avoid additional charges.",
                            name, amount, location, dateStr);
                    important = true;
                }

                notificationService.notifyOwners(orgId, "RENT_REMINDER", title, message, "RENT", rentId, important);
            } catch (Exception e) {
                log.warn("Rent reminder failed for rent_id={}: {}", rent.get("rent_id"), e.getMessage());
            }
        }
    }

    // ─── Checkout Reminders ───────────────────────────────────────────────────

    void sendCheckoutReminders() {
        LocalDate today = LocalDate.now();

        List<Map<String, Object>> upcoming = jdbc.queryForList(
                "SELECT fp.facility_party_id, fp.organization_id, fp.party_id, fp.expected_checkout_date, " +
                "       p.full_name, " +
                "       COALESCE(froom.facility_name, '') AS room_name, " +
                "       COALESCE(fbed.facility_name, '')  AS bed_name " +
                "FROM facility_party fp " +
                "JOIN person p ON p.party_id = fp.party_id " +
                "JOIN facility fbed ON fbed.facility_id = fp.facility_id " +
                "LEFT JOIN facility_group_member fgm " +
                "       ON fgm.child_facility_id = fbed.facility_id AND fgm.thru_date IS NULL " +
                "LEFT JOIN facility froom ON froom.facility_id = fgm.parent_facility_id " +
                "WHERE fp.role_type_id = 'OCCUPANT' AND fp.thru_date IS NULL " +
                "  AND fp.expected_checkout_date IS NOT NULL " +
                "  AND DATEDIFF(fp.expected_checkout_date, ?) IN (5, 1, 0)",
                today
        );

        for (Map<String, Object> row : upcoming) {
            try {
                Long fpId  = toLong(row.get("facility_party_id"));
                Long orgId = toLong(row.get("organization_id"));
                LocalDate checkoutDate = toLocalDate(row.get("expected_checkout_date"));
                if (checkoutDate == null) continue;

                if (notificationService.alreadySentToday(orgId, "CHECKOUT_REMINDER", "FACILITY_PARTY", fpId)) continue;

                String name      = str(row.get("full_name"));
                String room      = str(row.get("room_name"));
                String bed       = str(row.get("bed_name"));
                String location  = room.isEmpty() ? bed : (room + (bed.isEmpty() ? "" : " / " + bed));
                String dateStr   = checkoutDate.format(DATE_FMT);
                long daysUntil   = today.until(checkoutDate, java.time.temporal.ChronoUnit.DAYS);

                String title = daysUntil == 0
                        ? String.format("Checkout Today — %s", name)
                        : String.format("Checkout in %d Day%s — %s", daysUntil, daysUntil > 1 ? "s" : "", name);
                String message = String.format(
                        "Dear %s, your checkout date is %s. Please complete room clearance and deposit settlement procedures.%s",
                        name, dateStr, location.isEmpty() ? "" : " Room: " + location + ".");

                notificationService.notifyOwners(orgId, "CHECKOUT_REMINDER", title, message, "FACILITY_PARTY", fpId, daysUntil <= 1);
            } catch (Exception e) {
                log.warn("Checkout reminder failed for facility_party_id={}: {}", row.get("facility_party_id"), e.getMessage());
            }
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private LocalDate toLocalDate(Object obj) {
        if (obj == null) return null;
        if (obj instanceof LocalDate d) return d;
        if (obj instanceof Date d) return d.toLocalDate();
        if (obj instanceof java.util.Date d) return d.toInstant().atZone(java.time.ZoneId.systemDefault()).toLocalDate();
        return null;
    }

    private Long toLong(Object obj) {
        if (obj == null) return null;
        return ((Number) obj).longValue();
    }

    private String str(Object obj) {
        return obj == null ? "" : obj.toString();
    }
}
