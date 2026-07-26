package com.pgmanager.dashboard;

import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.occupancy.FacilityPartyRepository;
import com.pgmanager.occupancy.OccupancyRole;
import com.pgmanager.payment.PaymentRepository;
import com.pgmanager.rent.RentRepository;
import com.pgmanager.security.PropertyAccessGuard;
import com.pgmanager.security.PropertyScope;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

@Service
@RequiredArgsConstructor
public class DashboardService {
    private final FacilityRepository facilityRepository;
    private final FacilityPartyRepository facilityPartyRepository;
    private final RentRepository rentRepository;
    private final PaymentRepository paymentRepository;
    private final PropertyAccessGuard propertyAccessGuard;
    private final JdbcTemplate jdbc;

    /**
     * Headline numbers for the home screen.
     *
     * <p>Two code paths on purpose. An owner keeps the original JPA counts untouched — no risk of
     * the numbers they have been looking at for months shifting because of a refactor. A
     * property-scoped login gets the SQL path below, which confines every figure to their assigned
     * properties; without it a manager's dashboard reported organization-wide beds, tenants and
     * revenue, silently disclosing the size of properties they were never given.
     */
    public DashboardResponse ownerDashboard(Long organizationId) {
        PropertyScope scope = propertyAccessGuard.scope();
        if (!scope.unrestricted()) {
            return scopedDashboard(organizationId, scope.propertyIds());
        }
        long totalBeds = facilityRepository.countByOrganizationIdAndFacilityTypeIdAndStatus(organizationId, FacilityType.BED, "ACTIVE");
        long occupiedBeds = facilityPartyRepository.countByOrganizationIdAndRoleTypeIdAndThruDateIsNull(organizationId, OccupancyRole.OCCUPANT);
        long totalTenants = facilityPartyRepository.countByOrganizationIdAndRoleTypeIdAndThruDateIsNull(organizationId, OccupancyRole.TENANT);
        return new DashboardResponse(
                totalBeds,
                occupiedBeds,
                Math.max(totalBeds - occupiedBeds, 0),
                totalTenants,
                pendingRent(organizationId),
                revenue(organizationId)
        );
    }

    /**
     * The same six figures, restricted to {@code propertyIds}.
     *
     * <p>Beds are reached by walking bed → room → floor → property through
     * {@code facility_group_member} (the same join FacilityController's vacant-beds query uses).
     * Rent and payments carry no facility id at all, so they are scoped through the tenant instead:
     * the set of parties holding a property-level {@code TENANT} membership in those properties.
     */
    private DashboardResponse scopedDashboard(Long organizationId, Set<Long> propertyIds) {
        if (propertyIds.isEmpty()) {
            // Assigned nothing: report zeroes rather than the organization's totals.
            return new DashboardResponse(0, 0, 0, 0, BigDecimal.ZERO, BigDecimal.ZERO);
        }
        String in = placeholders(propertyIds.size());
        List<Object> propertyArgs = new ArrayList<>(propertyIds);

        String bedJoin =
                "FROM facility bed " +
                "JOIN facility_group_member bgm ON bgm.child_facility_id = bed.facility_id AND bgm.thru_date IS NULL " +
                "JOIN facility_group_member rgm ON rgm.child_facility_id = bgm.parent_facility_id AND rgm.thru_date IS NULL " +
                "JOIN facility_group_member fgm ON fgm.child_facility_id = rgm.parent_facility_id AND fgm.thru_date IS NULL " +
                "WHERE bed.organization_id = ? AND bed.facility_type_id = 'BED' AND bed.status = 'ACTIVE' " +
                "  AND fgm.parent_facility_id IN (" + in + ")";

        long totalBeds = count("SELECT COUNT(*) " + bedJoin, args(organizationId, propertyArgs));

        long occupiedBeds = count(
                "SELECT COUNT(*) FROM facility_party fp " +
                "WHERE fp.organization_id = ? AND fp.role_type_id = 'OCCUPANT' AND fp.thru_date IS NULL " +
                "  AND fp.facility_id IN (SELECT bed.facility_id " + bedJoin + ")",
                args(organizationId, List.of(organizationId), propertyArgs));

        // The property-level TENANT row is the one that names a property; the org-level row does not.
        long totalTenants = count(
                "SELECT COUNT(DISTINCT fp.party_id) FROM facility_party fp " +
                "WHERE fp.organization_id = ? AND fp.role_type_id = 'TENANT' AND fp.thru_date IS NULL " +
                "  AND fp.facility_id IN (" + in + ")",
                args(organizationId, propertyArgs));

        String tenantParties =
                "SELECT fp.party_id FROM facility_party fp " +
                "WHERE fp.organization_id = ? AND fp.role_type_id = 'TENANT' AND fp.facility_id IN (" + in + ")";

        BigDecimal pendingRent = amount(
                "SELECT COALESCE(SUM(GREATEST(" +
                "  (r.monthly_rent + r.deposit + r.advance + r.penalty - r.discount) - r.paid_amount, 0)), 0) " +
                "FROM rent r WHERE r.organization_id = ? AND r.party_id IN (" + tenantParties + ")",
                args(organizationId, List.of(organizationId), propertyArgs));

        BigDecimal revenue = amount(
                "SELECT COALESCE(SUM(p.amount), 0) FROM payment p " +
                "WHERE p.organization_id = ? AND p.party_id IN (" + tenantParties + ")",
                args(organizationId, List.of(organizationId), propertyArgs));

        return new DashboardResponse(
                totalBeds,
                occupiedBeds,
                Math.max(totalBeds - occupiedBeds, 0),
                totalTenants,
                pendingRent,
                revenue
        );
    }

    private static String placeholders(int n) {
        return String.join(",", java.util.Collections.nCopies(n, "?"));
    }

    /** Flattens scalars and lists into one positional argument array, in order. */
    private static Object[] args(Object first, Object... rest) {
        List<Object> flat = new ArrayList<>();
        flat.add(first);
        for (Object o : rest) {
            if (o instanceof List<?> list) flat.addAll(list);
            else flat.add(o);
        }
        return flat.toArray();
    }

    private long count(String sql, Object[] args) {
        Long value = jdbc.queryForObject(sql, Long.class, args);
        return value == null ? 0 : value;
    }

    private BigDecimal amount(String sql, Object[] args) {
        BigDecimal value = jdbc.queryForObject(sql, BigDecimal.class, args);
        return value == null ? BigDecimal.ZERO : value;
    }

    private BigDecimal pendingRent(Long organizationId) {
        return rentRepository.findByOrganizationId(organizationId).stream()
                .map(rent -> rent.totalDue().subtract(rent.getPaidAmount()).max(BigDecimal.ZERO))
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    private BigDecimal revenue(Long organizationId) {
        BigDecimal total = paymentRepository.sumAmountByOrganizationId(organizationId);
        return total == null ? BigDecimal.ZERO : total;
    }
}
