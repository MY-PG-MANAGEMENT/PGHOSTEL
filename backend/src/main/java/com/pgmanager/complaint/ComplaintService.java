package com.pgmanager.complaint;

import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Complaint lifecycle shared by the tenant portal (raise + track) and the owner console
 * (triage + resolve). JPA for writes/detail; JdbcTemplate for enriched list joins (tenant
 * name, room) — same split as the rest of the codebase.
 */
@Service
@RequiredArgsConstructor
public class ComplaintService {

    private final ComplaintRepository complaints;
    private final ComplaintStatusHistoryRepository history;
    private final NotificationService notificationService;
    private final JdbcTemplate jdbc;

    /** Tenant raises a complaint. Resolves the tenant's current property, records OPEN history, notifies owners. */
    @Transactional
    public Complaint create(Long organizationId, Long partyId, String category, String title,
                            String description, String priority) {
        String cat = category == null ? "OTHER" : category.trim().toUpperCase();
        String prio = priority == null || priority.isBlank() ? ComplaintStatus.PRIORITY_MEDIUM : priority.trim().toUpperCase();
        if (!ComplaintStatus.PRIORITIES.contains(prio)) prio = ComplaintStatus.PRIORITY_MEDIUM;

        Complaint c = new Complaint();
        c.setOrganizationId(organizationId);
        c.setPartyId(partyId);
        c.setPropertyFacilityId(resolvePropertyForTenant(organizationId, partyId));
        c.setCategory(cat);
        c.setTitle(title);
        c.setDescription(description);
        c.setPriority(prio);
        c.setStatus(ComplaintStatus.OPEN);
        c = complaints.save(c);

        recordHistory(c.getComplaintId(), null, ComplaintStatus.OPEN, "Complaint raised", null);

        String tenantName = tenantName(partyId);
        notificationService.notifyOwners(organizationId, "COMPLAINT",
                "New complaint: " + title,
                tenantName + " raised a " + prio + " priority complaint (" + cat + ").",
                "COMPLAINT", c.getComplaintId(), ComplaintStatus.PRIORITY_HIGH.equals(prio));
        return c;
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> listForOwner(Long organizationId, Long propertyId, String status) {
        StringBuilder sql = new StringBuilder(
                "SELECT c.complaint_id,c.category,c.title,c.description,c.priority,c.status,c.created_at,c.updated_at," +
                "c.party_id,pr.full_name tenant_name,pr.mobile_number tenant_mobile " +
                "FROM complaint c JOIN person pr ON pr.party_id=c.party_id WHERE c.organization_id=?");
        List<Object> args = new java.util.ArrayList<>();
        args.add(organizationId);
        if (propertyId != null) { sql.append(" AND c.property_facility_id=?"); args.add(propertyId); }
        if (status != null && !status.isBlank()) { sql.append(" AND c.status=?"); args.add(status.trim().toUpperCase()); }
        sql.append(" ORDER BY c.created_at DESC");
        List<Map<String, Object>> rows = jdbc.queryForList(sql.toString(), args.toArray());
        // Enrich each complaint with the raiser's current bed/room/floor (from their active
        // occupancy) — resolved for all raisers in a single query instead of one per complaint.
        List<Long> partyIds = rows.stream()
                .map(r -> ((Number) r.get("party_id")).longValue()).toList();
        Map<Long, Map<String, String>> locations = tenantLocations(organizationId, partyIds);
        for (Map<String, Object> row : rows) {
            Long partyId = ((Number) row.get("party_id")).longValue();
            Map<String, String> loc = locations.getOrDefault(partyId, Map.of());
            row.put("bed_name", loc.get("bed"));
            row.put("room_name", loc.get("room"));
            row.put("floor_name", loc.get("floor"));
        }
        return rows;
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> listForTenant(Long organizationId, Long partyId) {
        return complaints.findByOrganizationIdAndPartyIdOrderByCreatedAtDesc(organizationId, partyId)
                .stream().map(ComplaintService::toMap).toList();
    }

    /** Detail + status timeline. Tenant callers pass their partyId to enforce ownership; owners pass null. */
    @Transactional(readOnly = true)
    public Map<String, Object> detail(Long organizationId, Long complaintId, Long partyIdOrNull) {
        Complaint c = (partyIdOrNull != null
                ? complaints.findByComplaintIdAndOrganizationIdAndPartyId(complaintId, organizationId, partyIdOrNull)
                : complaints.findByComplaintIdAndOrganizationId(complaintId, organizationId))
                .orElseThrow(() -> new NotFoundException("Complaint not found"));
        Map<String, Object> map = toMap(c);
        map.put("tenantName", tenantName(c.getPartyId()));
        Map<String, String> loc = tenantLocation(organizationId, c.getPartyId());
        map.put("bedName", loc.get("bed"));
        map.put("roomName", loc.get("room"));
        map.put("floorName", loc.get("floor"));
        map.put("history", history.findByComplaintIdOrderByCreatedAtAsc(complaintId).stream().map(h -> {
            Map<String, Object> hm = new LinkedHashMap<>();
            hm.put("fromStatus", h.getFromStatus());
            hm.put("toStatus", h.getToStatus());
            hm.put("note", h.getNote());
            hm.put("createdAt", h.getCreatedAt());
            return hm;
        }).toList());
        return map;
    }

    /** Owner transitions a complaint's status, records history, and notifies the tenant. */
    @Transactional
    public Map<String, Object> updateStatus(Long organizationId, Long userLoginId, Long complaintId,
                                            String status, String note) {
        String to = status == null ? "" : status.trim().toUpperCase();
        if (!ComplaintStatus.ALL.contains(to)) {
            throw new BadRequestException("status must be one of " + ComplaintStatus.ALL);
        }
        Complaint c = complaints.findByComplaintIdAndOrganizationId(complaintId, organizationId)
                .orElseThrow(() -> new NotFoundException("Complaint not found"));
        String from = c.getStatus();
        if (!from.equals(to)) {
            c.setStatus(to);
            complaints.save(c);
            recordHistory(complaintId, from, to, note, userLoginId);
            notificationService.notifyTenant(organizationId, c.getPartyId(), "COMPLAINT",
                    "Complaint update: " + c.getTitle(),
                    "Your complaint is now " + to.replace('_', ' ') + (note != null && !note.isBlank() ? ". Note: " + note : "."),
                    "COMPLAINT", complaintId);
        }
        return detail(organizationId, complaintId, null);
    }

    private void recordHistory(Long complaintId, String from, String to, String note, Long userLoginId) {
        ComplaintStatusHistory h = new ComplaintStatusHistory();
        h.setComplaintId(complaintId);
        h.setFromStatus(from);
        h.setToStatus(to);
        h.setNote(note);
        h.setChangedByUserLoginId(userLoginId);
        history.save(h);
    }

    private String tenantName(Long partyId) {
        List<String> names = jdbc.queryForList("SELECT full_name FROM person WHERE party_id=?", String.class, partyId);
        return names.isEmpty() ? "Tenant" : names.get(0);
    }

    /**
     * Resolves the raiser's current bed/room/floor names from their active OCCUPANT assignment,
     * walking bed → room → floor via the dated {@code facility_group_member} tree. Returns a map
     * with keys {@code bed}, {@code room}, {@code floor} (values null when not assigned).
     */
    private Map<String, String> tenantLocation(Long organizationId, Long partyId) {
        Map<String, String> loc = new LinkedHashMap<>();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT bed.facility_name AS bed_name, room.facility_name AS room_name, floor.facility_name AS floor_name " +
                "FROM facility_party occ " +
                "JOIN facility bed ON bed.facility_id = occ.facility_id " +
                "LEFT JOIN facility_group_member rgm ON rgm.child_facility_id = bed.facility_id AND rgm.thru_date IS NULL " +
                "LEFT JOIN facility room ON room.facility_id = rgm.parent_facility_id " +
                "LEFT JOIN facility_group_member fgm ON fgm.child_facility_id = room.facility_id AND fgm.thru_date IS NULL " +
                "LEFT JOIN facility floor ON floor.facility_id = fgm.parent_facility_id " +
                "WHERE occ.organization_id=? AND occ.party_id=? AND occ.role_type_id='OCCUPANT' AND occ.thru_date IS NULL " +
                "LIMIT 1",
                organizationId, partyId);
        if (!rows.isEmpty()) {
            Map<String, Object> r = rows.get(0);
            loc.put("bed", str(r.get("bed_name")));
            loc.put("room", str(r.get("room_name")));
            loc.put("floor", str(r.get("floor_name")));
        }
        return loc;
    }

    /**
     * Batched variant of {@link #tenantLocation}: resolves bed/room/floor names for many
     * raisers in one query keyed by {@code party_id}. Used by the owner complaint list so
     * enrichment costs one query total rather than one per complaint.
     */
    private Map<Long, Map<String, String>> tenantLocations(Long organizationId, Collection<Long> partyIds) {
        Map<Long, Map<String, String>> byParty = new HashMap<>();
        List<Long> ids = partyIds.stream().distinct().toList();
        if (ids.isEmpty()) return byParty;
        String placeholders = ids.stream().map(x -> "?").collect(Collectors.joining(","));
        List<Object> args = new ArrayList<>();
        args.add(organizationId);
        args.addAll(ids);
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT occ.party_id AS party_id, bed.facility_name AS bed_name, room.facility_name AS room_name, floor.facility_name AS floor_name " +
                "FROM facility_party occ " +
                "JOIN facility bed ON bed.facility_id = occ.facility_id " +
                "LEFT JOIN facility_group_member rgm ON rgm.child_facility_id = bed.facility_id AND rgm.thru_date IS NULL " +
                "LEFT JOIN facility room ON room.facility_id = rgm.parent_facility_id " +
                "LEFT JOIN facility_group_member fgm ON fgm.child_facility_id = room.facility_id AND fgm.thru_date IS NULL " +
                "LEFT JOIN facility floor ON floor.facility_id = fgm.parent_facility_id " +
                "WHERE occ.organization_id=? AND occ.role_type_id='OCCUPANT' AND occ.thru_date IS NULL " +
                "AND occ.party_id IN (" + placeholders + ")",
                args.toArray());
        for (Map<String, Object> r : rows) {
            Long pid = ((Number) r.get("party_id")).longValue();
            // A party has at most one active OCCUPANT row; keep the first if data ever has more.
            byParty.computeIfAbsent(pid, k -> {
                Map<String, String> loc = new LinkedHashMap<>();
                loc.put("bed", str(r.get("bed_name")));
                loc.put("room", str(r.get("room_name")));
                loc.put("floor", str(r.get("floor_name")));
                return loc;
            });
        }
        return byParty;
    }

    private static String str(Object o) {
        return o == null ? null : o.toString();
    }

    /** Walks bed → room → floor → property for the tenant's active OCCUPANT assignment. */
    private Long resolvePropertyForTenant(Long organizationId, Long partyId) {
        List<Long> ids = jdbc.queryForList(
                "SELECT ppp.parent_facility_id FROM facility_party fp " +
                "JOIN facility_group_member rm ON rm.child_facility_id=fp.facility_id AND rm.thru_date IS NULL " +
                "JOIN facility_group_member fm ON fm.child_facility_id=rm.parent_facility_id AND fm.thru_date IS NULL " +
                "JOIN facility_group_member ppp ON ppp.child_facility_id=fm.parent_facility_id AND ppp.thru_date IS NULL " +
                "WHERE fp.organization_id=? AND fp.party_id=? AND fp.role_type_id='OCCUPANT' AND fp.thru_date IS NULL " +
                "LIMIT 1",
                Long.class, organizationId, partyId);
        return ids.isEmpty() ? null : ids.get(0);
    }

    static Map<String, Object> toMap(Complaint c) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("complaintId", c.getComplaintId());
        m.put("category", c.getCategory());
        m.put("title", c.getTitle());
        m.put("description", c.getDescription());
        m.put("priority", c.getPriority());
        m.put("status", c.getStatus());
        m.put("propertyFacilityId", c.getPropertyFacilityId());
        m.put("createdAt", c.getCreatedAt());
        m.put("updatedAt", c.getUpdatedAt());
        return m;
    }
}
