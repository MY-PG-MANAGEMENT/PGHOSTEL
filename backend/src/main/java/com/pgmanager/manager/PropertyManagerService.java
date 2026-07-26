package com.pgmanager.manager;

import com.pgmanager.audit.AuditService;
import com.pgmanager.auth.UserLogin;
import com.pgmanager.auth.UserLoginRepository;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.exception.NotFoundException;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.party.Party;
import com.pgmanager.party.PartyRepository;
import com.pgmanager.party.PartyType;
import com.pgmanager.party.Person;
import com.pgmanager.party.PersonRepository;
import com.pgmanager.security.CurrentUser;
import com.pgmanager.security.PropertyAccessGuard;
import com.pgmanager.security.RoleType;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Owner-managed staff logins scoped to specific properties.
 *
 * <p>Fills the gap that made multi-property organizations unworkable: the only logins the system
 * could create were OWNER (whole organization) and TENANT (portal). There was no way to hand one
 * property to one person.
 *
 * <p><b>Model reuse, no new tables.</b> A manager is the same Party → Person → UserLogin graph an
 * owner is, with {@code role_type_id = 'PROPERTY_MANAGER'}. The assignment is a
 * {@code facility_party} row per property ({@code role_type_id = 'PROPERTY_MANAGER'}, null
 * {@code thru_date}) — the dated-membership pattern tenants already use, which means unassigning
 * is an end-date and history survives.
 *
 * <p><b>The manager signs in with their mobile number.</b> The stored username is
 * {@code {mobile}@m{orgId}} because {@code user_login.username} is globally unique and the same
 * mobile may exist in several organizations (the {@code m} prefix also keeps it from colliding with
 * a tenant's {@code {mobile}@{orgId}} for the same person). That suffix is an <b>implementation
 * detail nobody should have to type</b>: {@code AuthService.resolveStaffMobile} maps a bare 10-digit
 * entry back to it, so the credential an owner hands over is just the mobile. Temp password
 * {@link #TEMP_PASSWORD} with {@code must_change_password = 1}, exactly like
 * {@code TenantLoginService}.
 */
@Service
@RequiredArgsConstructor
public class PropertyManagerService {

    /** Same temporary password convention as the tenant portal. */
    public static final String TEMP_PASSWORD = "abc@123";

    private final JdbcTemplate jdbc;
    private final PartyRepository partyRepository;
    private final PersonRepository personRepository;
    private final UserLoginRepository userLoginRepository;
    private final PasswordEncoder passwordEncoder;
    private final AuditService auditService;
    private final CurrentUser currentUser;

    /** Every manager login in the org, each with the properties it can reach. */
    public List<Map<String, Object>> list(Long organizationId) {
        List<Map<String, Object>> logins = jdbc.queryForList(
                "SELECT u.user_login_id,u.username,u.status,u.must_change_password,u.last_login_at," +
                "u.party_id,p.full_name,p.mobile_number " +
                "FROM user_login u JOIN person p ON p.party_id = u.party_id " +
                "WHERE u.organization_id = ? AND u.role_type_id = ? " +
                "ORDER BY p.full_name",
                organizationId, RoleType.PROPERTY_MANAGER);
        if (logins.isEmpty()) return List.of();

        // One query for every assignment, then grouped in memory - avoids a per-manager query
        // (the N+1 pattern already stamped out elsewhere in this codebase).
        Map<Long, List<Map<String, Object>>> byParty = new LinkedHashMap<>();
        jdbc.query("SELECT fp.party_id,fp.facility_id,f.facility_name " +
                        "FROM facility_party fp " +
                        "JOIN facility f ON f.facility_id = fp.facility_id AND f.facility_type_id = 'PROPERTY' " +
                        "WHERE fp.organization_id = ? AND fp.role_type_id = ? AND fp.thru_date IS NULL " +
                        "ORDER BY f.facility_name",
                rs -> {
                    Map<String, Object> property = new LinkedHashMap<>();
                    property.put("propertyId", rs.getLong("facility_id"));
                    property.put("propertyName", rs.getString("facility_name"));
                    byParty.computeIfAbsent(rs.getLong("party_id"), k -> new ArrayList<>()).add(property);
                },
                organizationId, RoleType.PROPERTY_MANAGER);

        List<Map<String, Object>> result = new ArrayList<>(logins.size());
        for (Map<String, Object> login : logins) {
            Long partyId = ((Number) login.get("party_id")).longValue();
            Map<String, Object> row = new LinkedHashMap<>(login);
            row.put("properties", byParty.getOrDefault(partyId, List.of()));
            result.add(row);
        }
        return result;
    }

    /**
     * Creates the login and its assignments in one transaction. Returns the generated username and
     * the temporary password so the owner can hand them over — this is the only moment the password
     * is knowable, since only its hash is stored.
     */
    @Transactional
    public Map<String, Object> create(Long organizationId, String fullName, String mobileNumber,
                                      Set<Long> propertyIds) {
        String mobile = requireMobile(mobileNumber);
        if (fullName == null || fullName.isBlank()) throw new BadRequestException("Full name is required");
        Set<Long> properties = validateProperties(organizationId, propertyIds);

        String username = mobile + "@m" + organizationId;
        if (userLoginRepository.existsByUsername(username)) {
            throw new BadRequestException("A manager login already exists for this mobile number");
        }

        Party party = new Party();
        party.setPartyTypeId(PartyType.PERSON);
        party = partyRepository.save(party);

        Person person = new Person();
        person.setPartyId(party.getPartyId());
        person.setFullName(fullName.trim());
        person.setMobileNumber(mobile);
        personRepository.save(person);

        UserLogin login = new UserLogin();
        login.setPartyId(party.getPartyId());
        login.setUsername(username);
        login.setPasswordHash(passwordEncoder.encode(TEMP_PASSWORD));
        login.setRoleTypeId(RoleType.PROPERTY_MANAGER);
        login.setOrganizationId(organizationId);
        login = userLoginRepository.save(login);
        // Forces a password change on first sign-in; the column and the flow already exist (V22).
        jdbc.update("UPDATE user_login SET must_change_password = 1 WHERE user_login_id = ?",
                login.getUserLoginId());

        replaceAssignments(organizationId, party.getPartyId(), properties);

        auditService.log(organizationId, currentUser.userLoginId(), "PROPERTY_MANAGER_CREATED",
                "USER_LOGIN", login.getUserLoginId(),
                "Manager " + fullName + " created with " + properties.size() + " property assignment(s)");

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("userLoginId", login.getUserLoginId());
        result.put("partyId", party.getPartyId());
        // The stored username carries the org suffix because user_login.username is globally
        // unique. It is an implementation detail: the manager signs in with the bare mobile, which
        // AuthService.resolveStaffMobile maps back to this. So `loginId` is what the owner hands
        // over, and `username` is kept only for support/debugging.
        result.put("loginId", mobile);
        result.put("username", username);
        result.put("temporaryPassword", TEMP_PASSWORD);
        result.put("propertyIds", List.copyOf(properties));
        return result;
    }

    /** Replaces the manager's whole assignment set. An empty set leaves them able to see nothing. */
    @Transactional
    public void setProperties(Long organizationId, Long userLoginId, Set<Long> propertyIds) {
        Map<String, Object> login = loadManager(organizationId, userLoginId);
        Long partyId = ((Number) login.get("party_id")).longValue();
        Set<Long> properties = validateProperties(organizationId, propertyIds);

        replaceAssignments(organizationId, partyId, properties);
        auditService.log(organizationId, currentUser.userLoginId(), "PROPERTY_MANAGER_PROPERTIES_CHANGED",
                "USER_LOGIN", userLoginId,
                "Assigned properties set to " + properties);
    }

    /**
     * Activates or deactivates the login. Deactivating also revokes refresh tokens, so the session
     * dies with its access token instead of rolling on for the full refresh window — the same
     * reasoning as the organization-status change.
     */
    @Transactional
    public void setStatus(Long organizationId, Long userLoginId, boolean active) {
        loadManager(organizationId, userLoginId);
        LocalDateTime now = LocalDateTime.now();
        jdbc.update("UPDATE user_login SET status = ?, disabled_reason = ?, updated_at = ? WHERE user_login_id = ?",
                active ? "ACTIVE" : "INACTIVE", active ? null : "DEACTIVATED_BY_OWNER", now, userLoginId);
        if (!active) {
            jdbc.update("UPDATE refresh_token SET revoked = TRUE, updated_at = ? " +
                    "WHERE user_login_id = ? AND revoked = FALSE", now, userLoginId);
        }
        auditService.log(organizationId, currentUser.userLoginId(), "PROPERTY_MANAGER_STATUS_CHANGED",
                "USER_LOGIN", userLoginId, "Manager login " + (active ? "activated" : "deactivated"));
    }

    /** Resets the login back to the temporary password and forces a change on next sign-in. */
    @Transactional
    public String resetPassword(Long organizationId, Long userLoginId) {
        loadManager(organizationId, userLoginId);
        LocalDateTime now = LocalDateTime.now();
        jdbc.update("UPDATE user_login SET password_hash = ?, must_change_password = 1, updated_at = ? " +
                        "WHERE user_login_id = ?",
                passwordEncoder.encode(TEMP_PASSWORD), now, userLoginId);
        jdbc.update("UPDATE refresh_token SET revoked = TRUE, updated_at = ? " +
                "WHERE user_login_id = ? AND revoked = FALSE", now, userLoginId);
        auditService.log(organizationId, currentUser.userLoginId(), "PROPERTY_MANAGER_PASSWORD_RESET",
                "USER_LOGIN", userLoginId, "Manager password reset to the temporary password");
        return TEMP_PASSWORD;
    }

    /**
     * End-dates the current assignments and inserts the new ones. End-dating rather than deleting
     * keeps "who managed this property in March" answerable, matching how occupancy history works.
     */
    private void replaceAssignments(Long organizationId, Long partyId, Set<Long> propertyIds) {
        LocalDate today = LocalDate.now();
        LocalDateTime now = LocalDateTime.now();
        jdbc.update("UPDATE facility_party SET thru_date = ?, updated_at = ? " +
                        "WHERE organization_id = ? AND party_id = ? AND role_type_id = ? AND thru_date IS NULL",
                today, now, organizationId, partyId, RoleType.PROPERTY_MANAGER);
        for (Long propertyId : propertyIds) {
            jdbc.update("INSERT INTO facility_party" +
                            "(organization_id,facility_id,party_id,role_type_id,from_date,created_at,updated_at) " +
                            "VALUES(?,?,?,?,?,?,?)",
                    organizationId, propertyId, partyId, RoleType.PROPERTY_MANAGER, today, now, now);
        }
    }

    /** Every id must be a PROPERTY in this organization — otherwise this is a scope escape. */
    private Set<Long> validateProperties(Long organizationId, Set<Long> propertyIds) {
        if (propertyIds == null || propertyIds.isEmpty()) return Set.of();
        Set<Long> requested = new LinkedHashSet<>(propertyIds);
        List<Long> valid = jdbc.queryForList(
                "SELECT facility_id FROM facility WHERE organization_id = ? AND facility_type_id = ?",
                Long.class, organizationId, FacilityType.PROPERTY);
        for (Long propertyId : requested) {
            if (!valid.contains(propertyId)) {
                throw new BadRequestException("Property " + propertyId + " does not belong to this organization");
            }
        }
        return requested;
    }

    private Map<String, Object> loadManager(Long organizationId, Long userLoginId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT user_login_id,party_id FROM user_login " +
                "WHERE user_login_id = ? AND organization_id = ? AND role_type_id = ?",
                userLoginId, organizationId, RoleType.PROPERTY_MANAGER);
        if (rows.isEmpty()) throw new NotFoundException("Manager login not found");
        return rows.get(0);
    }

    private String requireMobile(String mobileNumber) {
        String mobile = mobileNumber == null ? "" : mobileNumber.trim();
        if (!mobile.matches("\\d{10}")) {
            throw new BadRequestException("Mobile number must be 10 digits");
        }
        return mobile;
    }

    /** Guard constant reused by the controller's docs/tests. */
    public static String assignmentRole() {
        return PropertyAccessGuard.ASSIGNMENT_ROLE;
    }
}
