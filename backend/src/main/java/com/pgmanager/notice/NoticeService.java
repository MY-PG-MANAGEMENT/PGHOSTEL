package com.pgmanager.notice;

import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.notification.NotificationService;
import com.pgmanager.notification.OrganizationChannelService;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Notices published by owners and read by tenants. JPA for CRUD; JdbcTemplate for the
 * tenant unread-join and recipient fan-out. An org-wide notice targets every active tenant;
 * a property-scoped notice targets tenants with an active bed in that property.
 */
@Service
@RequiredArgsConstructor
public class NoticeService {

    private static final Logger log = LoggerFactory.getLogger(NoticeService.class);

    private final NoticeRepository notices;
    private final NotificationService notificationService;
    private final OrganizationChannelService channelService;
    private final JdbcTemplate jdbc;

    @Transactional
    public Notice create(Long organizationId, Long userLoginId, Long propertyFacilityId, String type,
                         String title, String body, LocalDateTime expiresAt) {
        String t = type == null || type.isBlank() ? NoticeType.ANNOUNCEMENT : type.trim().toUpperCase();
        if (!NoticeType.ALL.contains(t)) throw new BadRequestException("notice type must be one of " + NoticeType.ALL);

        Notice n = new Notice();
        n.setOrganizationId(organizationId);
        n.setPropertyFacilityId(propertyFacilityId);
        n.setNoticeType(t);
        n.setTitle(title);
        n.setBody(body);
        n.setPublishedAt(LocalDateTime.now());
        n.setExpiresAt(expiresAt);
        n.setCreatedByUserLoginId(userLoginId);
        n.setActive(true);
        n = notices.save(n);

        // Fan out an in-app notification to affected tenants (best-effort; never fails the publish).
        // Resolve the EMAIL-channel gate once and pass it down, rather than per recipient.
        try {
            boolean emailEnabled = channelService.enabled(organizationId, "EMAIL");
            for (Long partyId : targetTenantPartyIds(organizationId, propertyFacilityId)) {
                notificationService.notifyTenant(organizationId, partyId, "NOTICE", title, body, "NOTICE",
                        n.getNoticeId(), emailEnabled);
            }
        } catch (Exception e) {
            log.warn("Notice fan-out failed for notice {}: {}", n.getNoticeId(), e.getMessage());
        }
        return n;
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> listForOwner(Long organizationId, Long propertyId) {
        return notices.findByOrganizationIdOrderByPublishedAtDesc(organizationId).stream()
                .filter(n -> propertyId == null || propertyId.equals(n.getPropertyFacilityId()))
                .map(NoticeService::toMap).toList();
    }

    @Transactional
    public void deactivate(Long organizationId, Long noticeId) {
        Notice n = notices.findByNoticeIdAndOrganizationId(noticeId, organizationId)
                .orElseThrow(() -> new NotFoundException("Notice not found"));
        n.setActive(false);
        notices.save(n);
    }

    // ─── Tenant-facing ──────────────────────────────────────────────────────────

    /** Active, non-expired notices for the tenant's org/property, each flagged read/unread. */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> listForTenant(Long organizationId, Long partyId, Long propertyId) {
        return jdbc.queryForList(
                "SELECT n.notice_id,n.notice_type,n.title,n.body,n.published_at,n.expires_at," +
                "(nr.notice_read_id IS NOT NULL) AS read_flag " +
                "FROM notice n " +
                "LEFT JOIN notice_read nr ON nr.notice_id=n.notice_id AND nr.party_id=? " +
                "WHERE n.organization_id=? AND n.active=TRUE " +
                "AND (n.expires_at IS NULL OR n.expires_at > LOCALTIMESTAMP(6)) " +
                "AND (n.property_facility_id IS NULL OR n.property_facility_id=?) " +
                "ORDER BY n.published_at DESC",
                partyId, organizationId, propertyId);
    }

    public int unreadCountForTenant(Long organizationId, Long partyId, Long propertyId) {
        Integer c = jdbc.queryForObject(
                "SELECT COUNT(*) FROM notice n " +
                "LEFT JOIN notice_read nr ON nr.notice_id=n.notice_id AND nr.party_id=? " +
                "WHERE n.organization_id=? AND n.active=TRUE AND nr.notice_read_id IS NULL " +
                "AND (n.expires_at IS NULL OR n.expires_at > LOCALTIMESTAMP(6)) " +
                "AND (n.property_facility_id IS NULL OR n.property_facility_id=?)",
                Integer.class, partyId, organizationId, propertyId);
        return c == null ? 0 : c;
    }

    /** Returns notice detail for a tenant and marks it read (idempotent upsert). */
    @Transactional
    public Map<String, Object> detailForTenant(Long organizationId, Long partyId, Long noticeId) {
        Notice n = notices.findByNoticeIdAndOrganizationId(noticeId, organizationId)
                .orElseThrow(() -> new NotFoundException("Notice not found"));
        LocalDateTime now = LocalDateTime.now();
        jdbc.update("INSERT INTO notice_read(notice_id,party_id,read_at,created_at,updated_at) VALUES(?,?,?,?,?) ON CONFLICT DO NOTHING",
                noticeId, partyId, now, now, now);
        Map<String, Object> map = toMap(n);
        map.put("read", true);
        return map;
    }

    /** Latest active notice preview for the tenant dashboard, or null. */
    public Map<String, Object> latestForTenant(Long organizationId, Long partyId, Long propertyId) {
        List<Map<String, Object>> rows = listForTenant(organizationId, partyId, propertyId);
        return rows.isEmpty() ? null : rows.get(0);
    }

    private List<Long> targetTenantPartyIds(Long organizationId, Long propertyId) {
        if (propertyId == null) {
            return jdbc.queryForList(
                    "SELECT DISTINCT party_id FROM facility_party " +
                    "WHERE organization_id=? AND facility_id=? AND role_type_id='TENANT' AND thru_date IS NULL",
                    Long.class, organizationId, organizationId);
        }
        return jdbc.queryForList(
                "SELECT DISTINCT fp.party_id FROM facility_party fp " +
                "JOIN facility_group_member rm ON rm.child_facility_id=fp.facility_id AND rm.thru_date IS NULL " +
                "JOIN facility_group_member fm ON fm.child_facility_id=rm.parent_facility_id AND fm.thru_date IS NULL " +
                "JOIN facility_group_member pm ON pm.child_facility_id=fm.parent_facility_id AND pm.thru_date IS NULL " +
                "WHERE fp.organization_id=? AND fp.role_type_id='OCCUPANT' AND fp.thru_date IS NULL AND pm.parent_facility_id=?",
                Long.class, organizationId, propertyId);
    }

    static Map<String, Object> toMap(Notice n) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("noticeId", n.getNoticeId());
        m.put("noticeType", n.getNoticeType());
        m.put("title", n.getTitle());
        m.put("body", n.getBody());
        m.put("publishedAt", n.getPublishedAt());
        m.put("expiresAt", n.getExpiresAt());
        m.put("propertyFacilityId", n.getPropertyFacilityId());
        m.put("active", n.isActive());
        return m;
    }
}
