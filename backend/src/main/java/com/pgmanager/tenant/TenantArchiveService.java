package com.pgmanager.tenant;

import com.pgmanager.audit.AuditService;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.occupancy.OccupancyRole;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Owns the {@code tenant_archive} table (V28): the owner-facing "Delete tenant" that
 * hides a departed tenant from the Inactive list <em>without</em> deleting anything.
 *
 * <p>Nothing is removed from {@code party} / {@code person} / {@code facility_party} /
 * {@code invoice} / {@code payment} — archiving writes one row here and the tenant lists
 * ({@link TenantService#list} / {@link TenantService#listByProperty}) filter the party out.
 * A tenant who rejoins is restored onto the <b>same partyId</b>, so their whole billing
 * history comes back with them.
 *
 * <p>Deliberately JdbcTemplate-based (like {@code BillingController} /
 * {@code TemporaryStayController}): the table is not a JPA entity, so {@code ddl-auto:
 * validate} does not track it, and the archived-list read model is a plain join.
 *
 * <p>This service never depends on {@link TenantService} — restore orchestration
 * (person fields, memberships, login) lives there and calls back into
 * {@link #unarchive} — which keeps the two beans free of a circular dependency.
 */
@Service
@RequiredArgsConstructor
public class TenantArchiveService {

    private static final Logger log = LoggerFactory.getLogger(TenantArchiveService.class);

    /** Outcome codes from {@link #tryArchive} — also the bulk-summary counter keys. */
    private static final String OK = "archived";
    private static final String NOT_A_TENANT = "skippedNotFound";
    private static final String STILL_ACTIVE = "skippedActive";
    private static final String ALREADY_ARCHIVED = "skippedAlreadyArchived";

    private final JdbcTemplate jdbc;
    private final AuditService auditService;
    private final TenantLoginService tenantLoginService;

    // ─── Reads ────────────────────────────────────────────────────────────────

    /** Party ids hidden from this org's tenant lists. Empty set when nothing is archived. */
    public Set<Long> archivedPartyIds(Long organizationId) {
        if (organizationId == null) return Set.of();
        return new HashSet<>(jdbc.queryForList(
                "SELECT party_id FROM tenant_archive WHERE organization_id = ?",
                Long.class, organizationId));
    }

    /**
     * The archived party in this org holding {@code mobile}, if any — the rejoin hook.
     * Most recently archived wins when a mobile was archived more than once.
     */
    public Optional<Long> findArchivedPartyByMobile(Long organizationId, String mobile) {
        if (organizationId == null || mobile == null || mobile.isBlank()) return Optional.empty();
        List<Long> ids = jdbc.queryForList(
                "SELECT ta.party_id FROM tenant_archive ta " +
                "LEFT JOIN person pr ON pr.party_id = ta.party_id " +
                "WHERE ta.organization_id = ? AND (pr.mobile_number = ? OR ta.mobile_number = ?) " +
                "ORDER BY ta.archived_at DESC, ta.tenant_archive_id DESC LIMIT 1",
                Long.class, organizationId, mobile, mobile);
        return ids.isEmpty() ? Optional.empty() : Optional.of(ids.get(0));
    }

    /**
     * Archived tenants for the org, newest first — the read model behind the Archived
     * Tenants screen. Optionally scoped to a property and filtered by name / mobile.
     */
    public List<Map<String, Object>> list(Long organizationId, Long propertyId, String query) {
        StringBuilder sql = new StringBuilder(
                "SELECT ta.tenant_archive_id, ta.party_id, ta.property_facility_id, ta.archived_at, " +
                "       COALESCE(pr.full_name, ta.full_name)          AS full_name, " +
                "       COALESCE(pr.mobile_number, ta.mobile_number)  AS mobile_number, " +
                "       pr.gender, pr.email, " +
                "       prop.facility_name AS property_name, " +
                "       (SELECT MAX(occ.thru_date) FROM facility_party occ " +
                "          WHERE occ.organization_id = ta.organization_id AND occ.party_id = ta.party_id " +
                "            AND occ.role_type_id = '" + OccupancyRole.OCCUPANT + "') AS last_checkout_date " +
                "FROM tenant_archive ta " +
                "LEFT JOIN person pr     ON pr.party_id = ta.party_id " +
                "LEFT JOIN facility prop ON prop.facility_id = ta.property_facility_id " +
                "WHERE ta.organization_id = ? ");
        List<Object> args = new ArrayList<>();
        args.add(organizationId);
        if (propertyId != null) {
            sql.append("AND ta.property_facility_id = ? ");
            args.add(propertyId);
        }
        if (query != null && !query.isBlank()) {
            // ILIKE, not LIKE: MySQL's ai_ci collation made LIKE case-insensitive, so searching
            // "raj" matched "Raj Kumar". PostgreSQL's LIKE is case-sensitive and would quietly
            // return nothing for the same query.
            sql.append("AND (COALESCE(pr.full_name, ta.full_name) ILIKE ? " +
                       "  OR COALESCE(pr.mobile_number, ta.mobile_number) ILIKE ?) ");
            String like = "%" + query.trim() + "%";
            args.add(like);
            args.add(like);
        }
        sql.append("ORDER BY ta.archived_at DESC, ta.tenant_archive_id DESC");

        return jdbc.query(sql.toString(), (rs, i) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("archiveId", rs.getLong("tenant_archive_id"));
            m.put("tenantId", rs.getLong("party_id"));
            m.put("fullName", rs.getString("full_name"));
            m.put("mobileNumber", rs.getString("mobile_number"));
            m.put("gender", rs.getString("gender"));
            m.put("email", rs.getString("email"));
            long prop = rs.getLong("property_facility_id");
            m.put("propertyId", rs.wasNull() ? null : prop);
            m.put("propertyName", rs.getString("property_name"));
            m.put("archivedAt", rs.getTimestamp("archived_at") == null
                    ? null : rs.getTimestamp("archived_at").toLocalDateTime().toString());
            java.sql.Date lastOut = rs.getDate("last_checkout_date");
            m.put("lastCheckoutDate", lastOut == null ? null : lastOut.toLocalDate().toString());
            return m;
        }, args.toArray());
    }

    // ─── Archive ──────────────────────────────────────────────────────────────

    /**
     * Archives one tenant, failing loudly — the single "Delete Tenant" action on the
     * tenant profile screen.
     */
    @Transactional
    public void archiveOne(Long organizationId, Long userLoginId, Long partyId) {
        switch (tryArchive(organizationId, userLoginId, partyId)) {
            case OK, ALREADY_ARCHIVED -> { /* idempotent */ }
            case STILL_ACTIVE -> throw new BadRequestException(
                    "This tenant is still occupying a bed. Check them out before deleting.");
            default -> throw new NotFoundException("Tenant not found in current organization");
        }
    }

    /**
     * Bulk archive for the Inactive list's multi-select. Never fails on one bad id:
     * active / unknown / already-archived tenants are counted as skips so the app can
     * report exactly what happened.
     */
    @Transactional
    public Map<String, Object> archiveMany(Long organizationId, Long userLoginId, List<Long> partyIds) {
        List<Long> ids = partyIds == null ? List.of()
                : partyIds.stream().filter(java.util.Objects::nonNull).distinct().toList();
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("total", ids.size());
        int archived = 0, notFound = 0, active = 0, already = 0;
        for (Long partyId : ids) {
            switch (tryArchive(organizationId, userLoginId, partyId)) {
                case OK -> archived++;
                case STILL_ACTIVE -> active++;
                case ALREADY_ARCHIVED -> already++;
                default -> notFound++;
            }
        }
        summary.put(OK, archived);
        summary.put(STILL_ACTIVE, active);
        summary.put(ALREADY_ARCHIVED, already);
        summary.put(NOT_A_TENANT, notFound);
        log.info("Tenant archive: org={} requested={} archived={} skippedActive={} skippedAlready={} skippedNotFound={}",
                organizationId, ids.size(), archived, active, already, notFound);
        return summary;
    }

    /**
     * Writes the archive row for one party. Returns an outcome code instead of throwing so
     * the bulk path can tally reasons.
     *
     * <p>Guards: the party must be an org-level TENANT of this org, and must not hold a bed
     * (an active {@code OCCUPANT} or {@code TEMP_OCCUPANT} row) — an occupied tenant has to
     * be checked out first, which is what settles their dues and deposit refund.
     */
    private String tryArchive(Long organizationId, Long userLoginId, Long partyId) {
        if (organizationId == null || partyId == null) return NOT_A_TENANT;
        if (!isOrgTenant(organizationId, partyId)) return NOT_A_TENANT;
        if (hasActiveAdmission(organizationId, partyId)) return STILL_ACTIVE;
        if (isArchived(partyId)) return ALREADY_ARCHIVED;

        Map<String, Object> person = personSnapshot(partyId);
        LocalDateTime now = LocalDateTime.now();
        jdbc.update("INSERT INTO tenant_archive(organization_id, property_facility_id, party_id, full_name, " +
                "mobile_number, archived_at, archived_by_user_login_id, created_at, updated_at) " +
                "VALUES(?,?,?,?,?,?,?,?,?)",
                organizationId, resolveLastPropertyId(organizationId, partyId), partyId,
                person.get("full_name"), person.get("mobile_number"), now, userLoginId, now, now);

        // A tenant who is gone must not keep a working portal login. Checkout already
        // disables it; this covers tenants archived without ever holding a bed.
        tenantLoginService.disableForArchive(organizationId, partyId);
        auditService.log(organizationId, userLoginId, "TENANT_ARCHIVED", "PARTY", partyId,
                "Tenant archived (hidden from tenant lists; data retained)");
        return OK;
    }

    // ─── Restore ──────────────────────────────────────────────────────────────

    /**
     * Clears the archive row so the tenant is visible again. Called by
     * {@link TenantService#restoreFromArchive} (owner "Restore" action) and by
     * {@link TenantService#create} when a rejoining tenant's mobile matches an archived one.
     *
     * @return true when a row was actually removed
     */
    @Transactional
    public boolean unarchive(Long organizationId, Long userLoginId, Long partyId) {
        if (organizationId == null || partyId == null) return false;
        int removed = jdbc.update("DELETE FROM tenant_archive WHERE organization_id = ? AND party_id = ?",
                organizationId, partyId);
        if (removed == 0) return false;
        auditService.log(organizationId, userLoginId, "TENANT_RESTORED", "PARTY", partyId,
                "Tenant restored from archive");
        log.info("Tenant restore: org={} party={} removed from archive", organizationId, partyId);
        return true;
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    public boolean isArchived(Long partyId) {
        if (partyId == null) return false;
        Long count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM tenant_archive WHERE party_id = ?", Long.class, partyId);
        return count != null && count > 0;
    }

    private boolean isOrgTenant(Long organizationId, Long partyId) {
        Long count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM facility_party WHERE organization_id = ? AND facility_id = ? " +
                "AND party_id = ? AND role_type_id = ? AND thru_date IS NULL",
                Long.class, organizationId, organizationId, partyId, OccupancyRole.TENANT);
        return count != null && count > 0;
    }

    /** True while the tenant holds a bed — permanent occupancy or an active temporary stay. */
    private boolean hasActiveAdmission(Long organizationId, Long partyId) {
        Long count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM facility_party WHERE organization_id = ? AND party_id = ? " +
                "AND role_type_id IN (?, ?) AND thru_date IS NULL",
                Long.class, organizationId, partyId, OccupancyRole.OCCUPANT, OccupancyRole.TEMP_OCCUPANT);
        return count != null && count > 0;
    }

    private Map<String, Object> personSnapshot(Long partyId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT full_name, mobile_number FROM person WHERE party_id = ?", partyId);
        return rows.isEmpty() ? Map.of() : rows.get(0);
    }

    /**
     * The tenant's last known property: their property-level TENANT membership if there is
     * one, else the property owning their most recent bed (bed → room → floor → property).
     * Null when they were only ever org-scoped and never assigned.
     */
    private Long resolveLastPropertyId(Long organizationId, Long partyId) {
        List<Long> viaMembership = jdbc.queryForList(
                "SELECT facility_id FROM facility_party WHERE organization_id = ? AND party_id = ? " +
                "AND role_type_id = ? AND facility_id <> ? ORDER BY facility_party_id DESC LIMIT 1",
                Long.class, organizationId, partyId, OccupancyRole.TENANT, organizationId);
        if (!viaMembership.isEmpty()) return viaMembership.get(0);

        List<Long> viaBed = jdbc.queryForList(
                "SELECT prop.parent_facility_id FROM facility_party occ " +
                "JOIN facility_group_member room  ON room.child_facility_id  = occ.facility_id       AND room.thru_date IS NULL " +
                "JOIN facility_group_member floor ON floor.child_facility_id = room.parent_facility_id  AND floor.thru_date IS NULL " +
                "JOIN facility_group_member prop  ON prop.child_facility_id  = floor.parent_facility_id AND prop.thru_date IS NULL " +
                "WHERE occ.organization_id = ? AND occ.party_id = ? AND occ.role_type_id IN (?, ?) " +
                "ORDER BY occ.from_date DESC, occ.facility_party_id DESC LIMIT 1",
                Long.class, organizationId, partyId, OccupancyRole.OCCUPANT, OccupancyRole.TEMP_OCCUPANT);
        return viaBed.isEmpty() ? null : viaBed.get(0);
    }
}
