package com.pgmanager.auth;

import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

/**
 * Single gate for "may anyone in this organization sign in?".
 *
 * <p>A super admin can flip an organization to {@code INACTIVE}/{@code SUSPENDED}
 * (<code>PATCH /api/super-admin/organizations/{id}/status</code> → {@code facility.status} on the
 * {@code ORGANIZATION} row). That only ever changed a label: every login path checked
 * {@code user_login.status} but never the organization's, so a deactivated org's owner, staff and
 * tenants all kept signing in. Every entry point that mints tokens now calls
 * {@link #assertActive(Long)} — {@code AuthService.login}/{@code refresh} and
 * {@code TenantAuthService.login}.
 *
 * <p>A null {@code organizationId} passes: super admins belong to no organization, so they must
 * still be able to sign in and undo the deactivation.
 */
@Component
@RequiredArgsConstructor
public class OrganizationStatusGuard {

    public static final String ACTIVE = "ACTIVE";
    public static final String SUSPENDED = "SUSPENDED";

    private final FacilityRepository facilityRepository;

    /**
     * @throws ResponseStatusException 403 when the organization is not ACTIVE (or has vanished).
     */
    public void assertActive(Long organizationId) {
        if (organizationId == null) {
            return;
        }
        String status = facilityRepository.findById(organizationId)
                .map(Facility::getStatus)
                .orElse(null);
        if (!ACTIVE.equals(status)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, messageFor(status));
        }
    }

    /** Message for a non-ACTIVE status, phrased for the person staring at the login screen. */
    public static String messageFor(String status) {
        if (SUSPENDED.equals(status)) {
            return "This organization is suspended. Contact support to restore access.";
        }
        return "This organization has been deactivated. Contact support to restore access.";
    }
}
