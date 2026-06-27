package com.pgmanager.notification;

import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class NotificationService {

    private static final Logger log = LoggerFactory.getLogger(NotificationService.class);
    private final JdbcTemplate jdbc;

    // ─── Core send ────────────────────────────────────────────────────────────

    public void notifyOwners(Long organizationId, String categoryId, String title, String message,
                             String entityType, Long entityId, boolean important) {
        List<Long> partyIds = jdbc.queryForList(
                "SELECT party_id FROM user_login WHERE organization_id = ? AND role_type_id IN ('OWNER','PROPERTY_MANAGER','MANAGER')",
                Long.class, organizationId);
        if (partyIds.isEmpty()) return;

        jdbc.update(
                "INSERT INTO notification(organization_id,category_id,title,message,entity_type,entity_id,priority,created_at) VALUES(?,?,?,?,?,?,?,?)",
                organizationId, categoryId, title, message, entityType, entityId,
                important ? "HIGH" : "NORMAL", LocalDateTime.now());
        Long notifId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        if (notifId == null) return;

        for (Long partyId : partyIds) {
            try {
                jdbc.update("INSERT IGNORE INTO notification_recipient(notification_id,party_id,important) VALUES(?,?,?)",
                        notifId, partyId, important);
            } catch (Exception e) {
                log.warn("Could not create notification_recipient for party {}: {}", partyId, e.getMessage());
            }
        }
    }

    public boolean alreadySentToday(Long organizationId, String categoryId, String entityType, Long entityId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM notification WHERE organization_id=? AND category_id=? AND entity_type=? AND entity_id=? AND DATE(created_at)=CURDATE()",
                Integer.class, organizationId, categoryId, entityType, entityId);
        return count != null && count > 0;
    }

    // ─── Check-in Welcome ─────────────────────────────────────────────────────

    public void notifyCheckIn(Long organizationId, Long partyId, Long bedFacilityId) {
        try {
            String tenantName = queryString(
                    "SELECT full_name FROM person WHERE party_id = ?", partyId);
            String bedName = queryString(
                    "SELECT facility_name FROM facility WHERE facility_id = ?", bedFacilityId);
            String roomName = queryString(
                    "SELECT f.facility_name FROM facility f " +
                    "JOIN facility_group_member fgm ON fgm.parent_facility_id = f.facility_id AND fgm.thru_date IS NULL " +
                    "WHERE fgm.child_facility_id = ?", bedFacilityId);
            String orgName = queryString(
                    "SELECT facility_name FROM facility WHERE facility_id = ?", organizationId);
            String managerPhone = queryString(
                    "SELECT p.mobile_number FROM person p " +
                    "JOIN user_login ul ON ul.party_id = p.party_id " +
                    "WHERE ul.organization_id = ? AND ul.role_type_id = 'OWNER' LIMIT 1", organizationId);

            String title = String.format("New Check-in — %s", tenantName);
            String message = String.format(
                    "Welcome to %s. Room: %s, Bed: %s. Contact manager: %s.",
                    orDefault(orgName, "PG"), orDefault(roomName, "—"), orDefault(bedName, "—"),
                    orDefault(managerPhone, "N/A"));

            notifyOwners(organizationId, "CHECK_IN", title, message, "FACILITY_PARTY", bedFacilityId, false);
        } catch (Exception e) {
            log.warn("Failed to send check-in notification for org={} party={}: {}", organizationId, partyId, e.getMessage());
        }
    }

    // ─── Payment Receipt ──────────────────────────────────────────────────────

    public void notifyPaymentReceipt(Long organizationId, Long partyId, Long paymentId, BigDecimal amount) {
        try {
            String tenantName = queryString("SELECT full_name FROM person WHERE party_id = ?", partyId);
            String receiptNo = String.format("PG%s%05d",
                    LocalDate.now().format(DateTimeFormatter.ofPattern("yyyyMM")), paymentId);

            String title = String.format("Payment Received — %s", orDefault(tenantName, "Tenant"));
            String message = String.format(
                    "Payment received successfully. Amount: ₹%s. Receipt No: %s.",
                    amount.toPlainString(), receiptNo);

            notifyOwners(organizationId, "PAYMENT_RECEIPT", title, message, "PAYMENT", paymentId, false);
        } catch (Exception e) {
            log.warn("Failed to send payment receipt notification for paymentId={}: {}", paymentId, e.getMessage());
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private String queryString(String sql, Object... args) {
        List<Map<String, Object>> rows = jdbc.queryForList(sql, args);
        if (rows.isEmpty()) return null;
        Object val = rows.getFirst().values().iterator().next();
        return val == null ? null : val.toString();
    }

    private String orDefault(String value, String fallback) {
        return (value == null || value.isBlank()) ? fallback : value;
    }
}
