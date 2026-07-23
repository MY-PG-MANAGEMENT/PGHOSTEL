package com.pgmanager.tenantportal;

import com.pgmanager.auth.UserLogin;
import com.pgmanager.auth.UserLoginRepository;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.complaint.Complaint;
import com.pgmanager.complaint.ComplaintService;
import com.pgmanager.notice.NoticeService;
import com.pgmanager.tenant.TenantService;
import com.pgmanager.tenant.dto.TenantDtos.TenantResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Read/write surface for the tenant self-service portal. Every method is scoped to a single
 * tenant by {@code (organizationId, partyId)} taken from the authenticated principal — a tenant
 * can never see another tenant's or another org's data. Aggregate reads use JdbcTemplate;
 * complaint/notice writes delegate to the shared services.
 */
@Service
@RequiredArgsConstructor
public class TenantPortalService {

    private final JdbcTemplate jdbc;
    private final TenantService tenantService;
    private final ComplaintService complaintService;
    private final NoticeService noticeService;
    private final UserLoginRepository userLoginRepository;
    private final PasswordEncoder passwordEncoder;

    // ─── Profile ─────────────────────────────────────────────────────────────────

    public Map<String, Object> profile(Long organizationId, Long partyId) {
        TenantResponse t = tenantService.get(organizationId, partyId);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("tenantId", t.tenantId());
        m.put("fullName", t.fullName());
        m.put("mobileNumber", t.mobileNumber());
        m.put("email", t.email());
        m.put("gender", t.gender());
        m.put("dateOfBirth", t.dateOfBirth());
        m.put("emergencyContactName", t.emergencyContactName());
        m.put("emergencyContactMobile", t.emergencyContactMobile());
        m.put("emergencyContactRelation", t.emergencyContactRelation());
        m.put("propertyId", t.currentPropertyId());
        m.put("propertyName", propertyName(t.currentPropertyId()));
        m.put("roomName", t.currentRoomName());
        m.put("bedName", t.currentBedName());
        m.put("sharingType", t.currentSharingType());
        m.put("joiningDate", t.moveInDate());
        m.put("agreementStart", t.moveInDate());
        m.put("agreementEnd", t.expectedCheckoutDate());
        m.put("monthlyRent", t.monthlyRent());
        m.put("securityDeposit", t.securityDeposit());
        m.put("hasActiveAdmission", t.hasActiveAdmission());
        m.put("status", t.hasActiveAdmission() ? "ACTIVE" : "PENDING_ALLOCATION");
        return m;
    }

    // ─── Payments ────────────────────────────────────────────────────────────────

    public Map<String, Object> payments(Long organizationId, Long partyId) {
        TenantResponse t = tenantService.get(organizationId, partyId);
        BigDecimal outstanding = outstanding(organizationId, partyId);
        LocalDate dueDate = nextDueDate(organizationId, partyId);

        List<Map<String, Object>> history = jdbc.queryForList(
                "SELECT payment_id,amount,payment_mode,payment_date,reference_number,status " +
                "FROM payment WHERE organization_id=? AND party_id=? ORDER BY payment_date DESC, payment_id DESC LIMIT 100",
                organizationId, partyId);

        List<Map<String, Object>> invoices = jdbc.queryForList(
                "SELECT i.invoice_id,i.invoice_number,i.invoice_month,i.due_date,i.total_amount,i.paid_amount," +
                "(i.total_amount-i.paid_amount) balance,i.status " +
                "FROM invoice i JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "WHERE i.organization_id=? AND ba.party_id=? ORDER BY i.due_date DESC LIMIT 100",
                organizationId, partyId);

        BigDecimal paidTotal = history.stream()
                .filter(p -> "RECEIVED".equals(p.get("status")))
                .map(p -> (BigDecimal) p.get("amount"))
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        Map<String, Object> m = new LinkedHashMap<>();
        m.put("monthlyRent", t.monthlyRent());
        m.put("securityDeposit", t.securityDeposit());
        m.put("outstandingAmount", outstanding);
        m.put("dueDate", dueDate);
        m.put("paidAmount", paidTotal);
        m.put("paymentStatus", outstanding.compareTo(BigDecimal.ZERO) > 0 ? "DUE" : "CLEAR");
        m.put("history", history);
        m.put("invoices", invoices);
        return m;
    }

    // ─── Dashboard ─────────────────────────────────────────────────────────────────

    public Map<String, Object> dashboard(Long organizationId, Long partyId) {
        TenantResponse t = tenantService.get(organizationId, partyId);

        Map<String, Object> property = new LinkedHashMap<>();
        property.put("propertyName", propertyName(t.currentPropertyId()));
        property.put("roomName", t.currentRoomName());
        property.put("bedName", t.currentBedName());
        property.put("staySince", t.moveInDate());
        property.put("hasActiveAdmission", t.hasActiveAdmission());

        Map<String, Object> due = new LinkedHashMap<>();
        due.put("amount", outstanding(organizationId, partyId));
        due.put("dueDate", nextDueDate(organizationId, partyId));

        List<Map<String, Object>> recent = jdbc.queryForList(
                "SELECT payment_id,amount,payment_mode,payment_date FROM payment " +
                "WHERE organization_id=? AND party_id=? AND status='RECEIVED' ORDER BY payment_date DESC, payment_id DESC LIMIT 1",
                organizationId, partyId);

        Map<String, Object> latestComplaint = latestComplaint(organizationId, partyId);
        Map<String, Object> latestNotice = noticeService.latestForTenant(organizationId, partyId, t.currentPropertyId());

        Map<String, Object> m = new LinkedHashMap<>();
        m.put("greetingName", t.fullName());
        m.put("property", property);
        m.put("outstanding", due);
        m.put("recentPayment", recent.isEmpty() ? null : recent.get(0));
        m.put("latestComplaint", latestComplaint);
        m.put("latestNotice", latestNotice);
        m.put("unreadNotifications", unreadNotifications(partyId));
        m.put("unreadNotices", noticeService.unreadCountForTenant(organizationId, partyId, t.currentPropertyId()));
        return m;
    }

    // ─── Complaints ────────────────────────────────────────────────────────────────

    public List<Map<String, Object>> listComplaints(Long organizationId, Long partyId) {
        return complaintService.listForTenant(organizationId, partyId);
    }

    public Map<String, Object> complaintDetail(Long organizationId, Long partyId, Long complaintId) {
        return complaintService.detail(organizationId, complaintId, partyId);
    }

    @Transactional
    public Map<String, Object> raiseComplaint(Long organizationId, Long partyId, String category,
                                              String title, String description, String priority) {
        Complaint c = complaintService.create(organizationId, partyId, category, title, description, priority);
        return complaintService.detail(organizationId, c.getComplaintId(), partyId);
    }

    // ─── Notices ───────────────────────────────────────────────────────────────────

    public List<Map<String, Object>> listNotices(Long organizationId, Long partyId) {
        return noticeService.listForTenant(organizationId, partyId, tenantPropertyId(organizationId, partyId));
    }

    public Map<String, Object> noticeDetail(Long organizationId, Long partyId, Long noticeId) {
        return noticeService.detailForTenant(organizationId, partyId, noticeId);
    }

    // ─── Notifications ───────────────────────────────────────────────────────────────

    public List<Map<String, Object>> listNotifications(Long partyId, int limit) {
        return jdbc.queryForList(
                "SELECT n.notification_id,n.category_id,n.title,n.message,n.priority,n.created_at," +
                "nr.read_at,nr.important FROM notification n " +
                "JOIN notification_recipient nr ON nr.notification_id=n.notification_id " +
                "WHERE nr.party_id=? AND nr.archived_at IS NULL ORDER BY n.created_at DESC LIMIT ?",
                partyId, Math.min(Math.max(limit, 1), 200));
    }

    @Transactional
    public void markNotificationRead(Long partyId, Long notificationId) {
        jdbc.update("UPDATE notification_recipient SET read_at=? WHERE notification_id=? AND party_id=? AND read_at IS NULL",
                LocalDateTime.now(), notificationId, partyId);
    }

    // ─── Change password (forced on first login) ─────────────────────────────────────

    @Transactional
    public void changePassword(Long userLoginId, String oldPassword, String newPassword) {
        if (newPassword == null || newPassword.length() < 6) {
            throw new BadRequestException("New password must be at least 6 characters");
        }
        UserLogin user = userLoginRepository.findById(userLoginId)
                .orElseThrow(() -> new BadRequestException("User not found"));
        if (oldPassword == null || !passwordEncoder.matches(oldPassword, user.getPasswordHash())) {
            throw new BadRequestException("Current password is incorrect");
        }
        user.setPasswordHash(passwordEncoder.encode(newPassword));
        user.setMustChangePassword(false);
        userLoginRepository.save(user);
    }

    // ─── helpers ─────────────────────────────────────────────────────────────────

    private BigDecimal outstanding(Long organizationId, Long partyId) {
        BigDecimal v = jdbc.queryForObject(
                "SELECT COALESCE(SUM(i.total_amount-i.paid_amount),0) FROM invoice i " +
                "JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "WHERE i.organization_id=? AND ba.party_id=? AND i.status IN ('PENDING','PARTIAL','OVERDUE')",
                BigDecimal.class, organizationId, partyId);
        return v == null ? BigDecimal.ZERO : v;
    }

    private LocalDate nextDueDate(Long organizationId, Long partyId) {
        List<java.sql.Date> d = jdbc.queryForList(
                "SELECT MIN(i.due_date) FROM invoice i " +
                "JOIN billing_account ba ON ba.billing_account_id=i.billing_account_id " +
                "WHERE i.organization_id=? AND ba.party_id=? AND i.status IN ('PENDING','PARTIAL','OVERDUE')",
                java.sql.Date.class, organizationId, partyId);
        return d.isEmpty() || d.get(0) == null ? null : d.get(0).toLocalDate();
    }

    private Map<String, Object> latestComplaint(Long organizationId, Long partyId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT complaint_id,title,status,priority,created_at FROM complaint " +
                "WHERE organization_id=? AND party_id=? ORDER BY created_at DESC LIMIT 1",
                organizationId, partyId);
        return rows.isEmpty() ? null : rows.get(0);
    }

    private int unreadNotifications(Long partyId) {
        Integer c = jdbc.queryForObject(
                "SELECT COUNT(*) FROM notification_recipient WHERE party_id=? AND read_at IS NULL AND archived_at IS NULL",
                Integer.class, partyId);
        return c == null ? 0 : c;
    }

    private String propertyName(Long propertyId) {
        if (propertyId == null) return null;
        List<String> names = jdbc.queryForList("SELECT facility_name FROM facility WHERE facility_id=?", String.class, propertyId);
        return names.isEmpty() ? null : names.get(0);
    }

    private Long tenantPropertyId(Long organizationId, Long partyId) {
        return tenantService.get(organizationId, partyId).currentPropertyId();
    }
}
