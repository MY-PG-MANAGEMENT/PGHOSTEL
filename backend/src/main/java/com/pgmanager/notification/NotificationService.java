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
    private final OrganizationChannelService channelService;

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

    // ─── Tenant-facing notifications (email via outbox) ─────────────────────────

    private static final String CH_EMAIL = "EMAIL";
    private static final DateTimeFormatter D = DateTimeFormatter.ofPattern("dd-MMM-yyyy");
    private static final DateTimeFormatter MONTH = DateTimeFormatter.ofPattern("MMMM yyyy");

    /**
     * Records a notification addressed to a tenant and queues it for external
     * delivery (email) via {@code notification_outbox}. The {@link OutboxDispatcher}
     * sends it asynchronously; failures never affect the calling operation.
     * Skips the email enqueue when the tenant has no address or has opted out.
     */
    public void notifyTenant(Long organizationId, Long tenantPartyId, String categoryId,
                             String subject, String body, String entityType, Long entityId) {
        notifyTenant(organizationId, tenantPartyId, categoryId, subject, body, entityType, entityId, null);
    }

    /**
     * Fan-out-friendly variant: pass a precomputed {@code emailChannelEnabled} flag to skip the
     * per-recipient EMAIL-channel lookup when sending to many tenants in a loop; pass {@code null}
     * to resolve it here (single-recipient callers).
     */
    public void notifyTenant(Long organizationId, Long tenantPartyId, String categoryId,
                             String subject, String body, String entityType, Long entityId,
                             Boolean emailChannelEnabled) {
        if (tenantPartyId == null || organizationId == null) return;
        try {
            String safeSubject = subject != null && subject.length() > 160 ? subject.substring(0, 160) : subject;
            jdbc.update(
                    "INSERT INTO notification(organization_id,category_id,title,message,entity_type,entity_id,priority,created_at) VALUES(?,?,?,?,?,?,?,?)",
                    organizationId, categoryId, safeSubject, body, entityType, entityId, "NORMAL", LocalDateTime.now());
            Long notifId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
            if (notifId == null) return;
            jdbc.update("INSERT IGNORE INTO notification_recipient(notification_id,party_id,important) VALUES(?,?,?)",
                    notifId, tenantPartyId, false);

            String email = queryString("SELECT email FROM person WHERE party_id = ?", tenantPartyId);
            if (email == null || email.isBlank()) return;
            if (optedOut(tenantPartyId, categoryId, CH_EMAIL)) return;
            // Per-org channel gate: skip the email enqueue unless a super admin has enabled
            // the EMAIL channel for this org. Use the precomputed flag during fan-out.
            boolean emailEnabled = emailChannelEnabled != null
                    ? emailChannelEnabled : channelService.enabled(organizationId, CH_EMAIL);
            if (!emailEnabled) return;

            LocalDateTime now = LocalDateTime.now();
            jdbc.update(
                    "INSERT INTO notification_outbox(notification_id,party_id,channel_type_id,status,attempt_count,next_attempt_at,created_at,updated_at) " +
                    "VALUES(?,?,?,?,?,?,?,?)",
                    notifId, tenantPartyId, CH_EMAIL, "PENDING", 0, now, now, now);
        } catch (Exception e) {
            log.warn("Failed to queue tenant notification (org={}, party={}, category={}): {}",
                    organizationId, tenantPartyId, categoryId, e.getMessage());
        }
    }

    private boolean optedOut(Long partyId, String categoryId, String channel) {
        Integer c = jdbc.queryForObject(
                "SELECT COUNT(*) FROM notification_preference WHERE party_id=? AND category_id=? AND channel_type_id=? AND enabled=FALSE",
                Integer.class, partyId, categoryId, channel);
        return c != null && c > 0;
    }

    /** Registration completed (before any bed is assigned). */
    public void notifyTenantWelcome(Long organizationId, Long partyId) {
        String name = personName(partyId);
        String org = orgName(organizationId);
        String subject = "Welcome to " + org;
        String body = "Dear " + name + ",\n\n"
                + "Your registration at " + org + " has been completed successfully. "
                + "We're delighted to have you with us.\n\n"
                + "Your room and move-in details will be shared with you shortly. "
                + "If you have any questions in the meantime, please reach out to the PG management.\n\n"
                + "Warm regards,\n" + org;
        notifyTenant(organizationId, partyId, "GENERAL", subject, body, "PARTY", partyId);
    }

    /** Bed assigned / check-in confirmed. */
    public void notifyTenantCheckIn(Long organizationId, Long partyId, Long bedFacilityId,
                                    LocalDate moveInDate, BigDecimal monthlyRent, BigDecimal securityDeposit) {
        String name = personName(partyId);
        String org = orgName(organizationId);
        String[] rb = roomAndBed(bedFacilityId);
        StringBuilder body = new StringBuilder("Dear ").append(name).append(",\n\n")
                .append("Your check-in at ").append(org).append(" is confirmed. Here are your stay details:\n\n")
                .append("• Room: ").append(rb[0]).append('\n')
                .append("• Bed: ").append(rb[1]).append('\n');
        if (moveInDate != null) body.append("• Move-in date: ").append(moveInDate.format(D)).append('\n');
        if (monthlyRent != null) body.append("• Monthly rent: ").append(inr(monthlyRent)).append('\n');
        if (securityDeposit != null) body.append("• Security deposit: ").append(inr(securityDeposit)).append('\n');
        body.append("\nYour first invoice (including the security deposit) will be shared shortly.\n\n")
                .append("Welcome aboard!\n").append(org);
        notifyTenant(organizationId, partyId, "CHECK_IN", "Check-in Confirmed — " + org,
                body.toString(), "FACILITY_PARTY", bedFacilityId);
    }

    /** Payment received — receipt to the tenant. */
    public void notifyTenantPaymentReceipt(Long organizationId, Long partyId, Long paymentId,
                                           BigDecimal amount, String mode) {
        String name = personName(partyId);
        String org = orgName(organizationId);
        String receiptNo = String.format("PG%s%05d",
                LocalDate.now().format(DateTimeFormatter.ofPattern("yyyyMM")), paymentId);
        String body = "Dear " + name + ",\n\n"
                + "We have received your payment. Details:\n\n"
                + "• Amount: " + inr(amount) + "\n"
                + "• Payment mode: " + orDefault(mode, "—") + "\n"
                + "• Receipt No: " + receiptNo + "\n"
                + "• Date: " + LocalDate.now().format(D) + "\n\n"
                + "Thank you for your payment.\n\n"
                + "Regards,\n" + org;
        notifyTenant(organizationId, partyId, "PAYMENT_RECEIPT", "Payment Received — " + inr(amount),
                body, "PAYMENT", paymentId);
    }

    /** A new monthly rent invoice was generated. */
    public void notifyTenantInvoice(Long organizationId, Long partyId, Long invoiceId, String invoiceNumber,
                                    BigDecimal amount, LocalDate dueDate, LocalDate invoiceMonth) {
        String name = personName(partyId);
        String org = orgName(organizationId);
        String monthLabel = invoiceMonth == null ? "" : invoiceMonth.format(MONTH);
        String body = "Dear " + name + ",\n\n"
                + "A new rent invoice has been generated for " + monthLabel + ".\n\n"
                + "• Invoice No: " + orDefault(invoiceNumber, "—") + "\n"
                + "• Amount due: " + inr(amount) + "\n"
                + (dueDate != null ? "• Due date: " + dueDate.format(D) + "\n" : "")
                + "\nPlease make the payment on or before the due date to avoid late charges.\n\n"
                + "Regards,\n" + org;
        notifyTenant(organizationId, partyId, "RENT_REMINDER", "New Rent Invoice — " + monthLabel,
                body, "INVOICE", invoiceId);
    }

    /** Rent reminder (due soon or overdue), sent by the daily scheduler. */
    public void notifyTenantRentReminder(Long organizationId, Long partyId, Long rentId,
                                         BigDecimal amount, LocalDate dueDate, long daysUntil) {
        String name = personName(partyId);
        String org = orgName(organizationId);
        String dateStr = dueDate == null ? "" : dueDate.format(D);
        String subject, body;
        if (daysUntil > 0) {
            subject = "Rent Due on " + dateStr;
            body = "Dear " + name + ",\n\n"
                    + "This is a friendly reminder that your rent of " + inr(amount) + " is due on "
                    + dateStr + " (in " + daysUntil + " day" + (daysUntil > 1 ? "s" : "") + ").\n\n"
                    + "Please make the payment on time to avoid late charges.\n\n"
                    + "Regards,\n" + org;
        } else {
            subject = "Rent Overdue — Payment Required";
            body = "Dear " + name + ",\n\n"
                    + "Your rent of " + inr(amount) + " was due on " + dateStr + " and is now overdue.\n\n"
                    + "Please make the payment immediately to avoid additional charges.\n\n"
                    + "Regards,\n" + org;
        }
        notifyTenant(organizationId, partyId, "RENT_REMINDER", subject, body, "RENT", rentId);
    }

    /** Upcoming-checkout reminder, sent by the daily scheduler. */
    public void notifyTenantCheckoutReminder(Long organizationId, Long partyId, Long facilityPartyId,
                                             LocalDate checkoutDate, long daysUntil) {
        String name = personName(partyId);
        String org = orgName(organizationId);
        String dateStr = checkoutDate == null ? "" : checkoutDate.format(D);
        String subject = daysUntil == 0
                ? "Checkout Today"
                : "Checkout in " + daysUntil + " Day" + (daysUntil > 1 ? "s" : "");
        String body = "Dear " + name + ",\n\n"
                + "This is a reminder that your checkout date is " + dateStr + ".\n\n"
                + "Please complete room clearance and settle any pending dues so your security deposit "
                + "can be refunded promptly.\n\n"
                + "Regards,\n" + org;
        notifyTenant(organizationId, partyId, "CHECKOUT_REMINDER", subject, body, "FACILITY_PARTY", facilityPartyId);
    }

    /** Checkout processed. */
    public void notifyTenantCheckout(Long organizationId, Long partyId, LocalDate checkoutDate,
                                     BigDecimal refundAmount, String refundMethod) {
        String name = personName(partyId);
        String org = orgName(organizationId);
        StringBuilder body = new StringBuilder("Dear ").append(name).append(",\n\n")
                .append("Your checkout has been processed on ")
                .append(checkoutDate == null ? LocalDate.now().format(D) : checkoutDate.format(D))
                .append(".\n");
        if (refundAmount != null && refundAmount.compareTo(BigDecimal.ZERO) > 0) {
            body.append("\n• Security deposit refund: ").append(inr(refundAmount))
                    .append(" via ").append(orDefault(refundMethod, "CASH")).append('\n');
        }
        body.append("\nThank you for staying with us. We wish you all the best!\n\n")
                .append("Warm regards,\n").append(org);
        notifyTenant(organizationId, partyId, "GENERAL", "Checkout Confirmed — " + org,
                body.toString(), "PARTY", partyId);
    }

    /** Bed/room changed immediately (same sharing type). */
    public void notifyTenantTransferApplied(Long organizationId, Long partyId, Long newBedFacilityId) {
        String name = personName(partyId);
        String org = orgName(organizationId);
        String[] rb = roomAndBed(newBedFacilityId);
        String body = "Dear " + name + ",\n\n"
                + "Your accommodation has been updated. New details:\n\n"
                + "• Room: " + rb[0] + "\n"
                + "• Bed: " + rb[1] + "\n"
                + "• Effective: " + LocalDate.now().format(D) + "\n\n"
                + "Your billing cycle and rent remain unchanged.\n\n"
                + "Regards,\n" + org;
        notifyTenant(organizationId, partyId, "GENERAL", "Room/Bed Changed — " + org,
                body, "FACILITY_PARTY", newBedFacilityId);
    }

    /** Sharing-type change scheduled for the next billing anniversary. */
    public void notifyTenantTransferScheduled(Long organizationId, Long partyId, Long toBedFacilityId,
                                              LocalDate effectiveDate, BigDecimal newRent) {
        String name = personName(partyId);
        String org = orgName(organizationId);
        String[] rb = roomAndBed(toBedFacilityId);
        String body = "Dear " + name + ",\n\n"
                + "A change in your accommodation has been scheduled:\n\n"
                + "• New Room: " + rb[0] + "\n"
                + "• New Bed: " + rb[1] + "\n"
                + (effectiveDate != null ? "• Effective date: " + effectiveDate.format(D) + "\n" : "")
                + (newRent != null ? "• New monthly rent: " + inr(newRent) + "\n" : "")
                + "\nYour current room and rent stay the same until the effective date.\n\n"
                + "Regards,\n" + org;
        notifyTenant(organizationId, partyId, "GENERAL", "Upcoming Room Change — " + org,
                body, "FACILITY_PARTY", toBedFacilityId);
    }

    /** Temporary (no-billing) stay arranged. */
    public void notifyTenantTempStay(Long organizationId, Long partyId, Long bedFacilityId, LocalDate fromDate) {
        String name = personName(partyId);
        String org = orgName(organizationId);
        String[] rb = roomAndBed(bedFacilityId);
        String body = "Dear " + name + ",\n\n"
                + "A temporary stay has been arranged for you:\n\n"
                + "• Room: " + rb[0] + "\n"
                + "• Bed: " + rb[1] + "\n"
                + (fromDate != null ? "• From: " + fromDate.format(D) + "\n" : "")
                + "\nNo rent is billed for this temporary stay.\n\n"
                + "Regards,\n" + org;
        notifyTenant(organizationId, partyId, "GENERAL", "Temporary Stay Confirmed — " + org,
                body, "FACILITY_PARTY", bedFacilityId);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private String personName(Long partyId) {
        return orDefault(queryString("SELECT full_name FROM person WHERE party_id = ?", partyId), "Tenant");
    }

    private String orgName(Long organizationId) {
        return orDefault(queryString("SELECT facility_name FROM facility WHERE facility_id = ?", organizationId), "our PG");
    }

    /** Returns {@code [roomName, bedName]} for a bed facility, with em-dash fallbacks. */
    private String[] roomAndBed(Long bedFacilityId) {
        String bed = queryString("SELECT facility_name FROM facility WHERE facility_id = ?", bedFacilityId);
        String room = queryString(
                "SELECT f.facility_name FROM facility f " +
                "JOIN facility_group_member fgm ON fgm.parent_facility_id = f.facility_id AND fgm.thru_date IS NULL " +
                "WHERE fgm.child_facility_id = ?", bedFacilityId);
        return new String[]{orDefault(room, "—"), orDefault(bed, "—")};
    }

    private String inr(BigDecimal amount) {
        if (amount == null) amount = BigDecimal.ZERO;
        return "₹" + new java.text.DecimalFormat("#,##0.##").format(amount);
    }

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
