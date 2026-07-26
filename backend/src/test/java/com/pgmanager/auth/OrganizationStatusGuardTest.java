package com.pgmanager.auth;

import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

/** The login gate for a super-admin-deactivated organization. */
class OrganizationStatusGuardTest {

    private FacilityRepository facilityRepository;
    private OrganizationStatusGuard guard;

    @BeforeEach
    void setUp() {
        facilityRepository = mock(FacilityRepository.class);
        guard = new OrganizationStatusGuard(facilityRepository);
    }

    private void orgWithStatus(String status) {
        Facility org = new Facility();
        org.setStatus(status);
        when(facilityRepository.findById(10L)).thenReturn(Optional.of(org));
    }

    @Test
    void activeOrganizationPasses() {
        orgWithStatus("ACTIVE");
        assertThatCode(() -> guard.assertActive(10L)).doesNotThrowAnyException();
    }

    @Test
    void inactiveOrganizationForbidden() {
        orgWithStatus("INACTIVE");
        assertThatThrownBy(() -> guard.assertActive(10L))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("deactivated")
                .extracting(e -> ((ResponseStatusException) e).getStatusCode())
                .isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void suspendedOrganizationForbiddenWithItsOwnMessage() {
        orgWithStatus("SUSPENDED");
        assertThatThrownBy(() -> guard.assertActive(10L))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("suspended");
    }

    @Test
    void missingOrganizationForbidden() {
        when(facilityRepository.findById(10L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> guard.assertActive(10L)).isInstanceOf(ResponseStatusException.class);
    }

    /** Super admins have no organization and must stay able to sign in and undo a deactivation. */
    @Test
    void nullOrganizationPassesWithoutALookup() {
        assertThatCode(() -> guard.assertActive(null)).doesNotThrowAnyException();
        verifyNoInteractions(facilityRepository);
    }
}
