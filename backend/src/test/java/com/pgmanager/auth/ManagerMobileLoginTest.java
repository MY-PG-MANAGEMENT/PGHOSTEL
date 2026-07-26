package com.pgmanager.auth;

import com.pgmanager.audit.AuditService;
import com.pgmanager.auth.dto.AuthDtos.LoginRequest;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.party.PartyRepository;
import com.pgmanager.party.PersonRepository;
import com.pgmanager.security.AppUserDetailsService;
import com.pgmanager.security.AppUserPrincipal;
import com.pgmanager.security.JwtService;
import com.pgmanager.security.RoleType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * A property manager signs in with their <b>mobile number</b>, not the stored
 * {@code {mobile}@m{orgId}} username.
 *
 * <p>The suffix exists because {@code user_login.username} is globally unique and the same mobile can
 * appear in several organizations — but it is an implementation detail, and asking an owner to
 * dictate "9849520153 at m 103" over the phone was a bad handover. These tests pin the resolution
 * and, just as importantly, that it cannot change how an owner authenticates.
 */
class ManagerMobileLoginTest {

    private UserLoginRepository userLoginRepository;
    private AuthenticationManager authenticationManager;
    private AppUserDetailsService userDetailsService;
    private JdbcTemplate jdbc;
    private AuthService authService;

    @BeforeEach
    void setUp() {
        userLoginRepository = mock(UserLoginRepository.class);
        authenticationManager = mock(AuthenticationManager.class);
        userDetailsService = mock(AppUserDetailsService.class);
        jdbc = mock(JdbcTemplate.class);
        OrganizationStatusGuard organizationStatusGuard = mock(OrganizationStatusGuard.class);

        authService = new AuthService(
                userLoginRepository, mock(RefreshTokenRepository.class), mock(PartyRepository.class),
                mock(PersonRepository.class), mock(FacilityRepository.class), mock(PasswordEncoder.class),
                authenticationManager, userDetailsService, mock(JwtService.class),
                mock(AuditService.class), organizationStatusGuard, jdbc);
        ReflectionTestUtils.setField(authService, "refreshTokenDays", 14L);

        AppUserPrincipal principal = new AppUserPrincipal(
                10L, 55L, 103L, "9849520153@m103", "hash", RoleType.PROPERTY_MANAGER, "ACTIVE", "Ravi");
        lenient().when(userDetailsService.loadUserByUsername(anyString())).thenReturn(principal);
    }

    private void managerLoginsForMobile(String... usernames) {
        when(jdbc.queryForList(anyString(), eq(String.class), eq(RoleType.PROPERTY_MANAGER), anyString()))
                .thenReturn(List.of(usernames));
    }

    @Test
    void aBareMobileIsResolvedToTheOrgSuffixedUsername() {
        when(userLoginRepository.existsByUsername("9849520153")).thenReturn(false);
        managerLoginsForMobile("9849520153@m103");

        // Fails later (JwtService is a bare mock), but resolution has already happened by then and
        // that is what this test is about.
        try {
            authService.login(new LoginRequest("9849520153", "abc@123"));
        } catch (Exception ignored) {
            // not the subject of this assertion
        }

        // The manager typed ten digits; Spring Security was asked about the real username.
        verify(userDetailsService).loadUserByUsername("9849520153@m103");
    }

    @Test
    void anExactUsernameMatchAlwaysWins() {
        // An owner whose chosen username happens to be ten digits must be unaffected.
        when(userLoginRepository.existsByUsername("9849520153")).thenReturn(true);

        try {
            authService.login(new LoginRequest("9849520153", "secret"));
        } catch (Exception ignored) {
            // not the subject of this assertion
        }

        verify(userDetailsService).loadUserByUsername("9849520153");
        // No manager lookup at all when the username exists as given.
        verify(jdbc, never()).queryForList(anyString(), eq(String.class), anyString(), anyString());
    }

    @Test
    void aNonMobileUsernameIsNeverRewritten() {
        try {
            authService.login(new LoginRequest("owner@sunrisepg.com", "secret"));
        } catch (Exception ignored) {
            // not the subject of this assertion
        }

        verify(userDetailsService).loadUserByUsername("owner@sunrisepg.com");
        verify(jdbc, never()).queryForList(anyString(), eq(String.class), anyString(), anyString());
    }

    @Test
    void anUnknownMobilePassesThroughUnchanged() {
        when(userLoginRepository.existsByUsername("9999999999")).thenReturn(false);
        managerLoginsForMobile();   // no manager has this mobile

        try {
            authService.login(new LoginRequest("9999999999", "whatever"));
        } catch (Exception ignored) {
            // not the subject of this assertion
        }

        // Left alone so it fails as ordinary invalid credentials, not as a special case.
        verify(userDetailsService).loadUserByUsername("9999999999");
    }

    @Test
    void oneMobileInTwoOrganizationsAsksForTheFullUsername() {
        when(userLoginRepository.existsByUsername("9849520153")).thenReturn(false);
        managerLoginsForMobile("9849520153@m103", "9849520153@m204");

        // Guessing an organization at the login boundary would be the wrong kind of helpful.
        assertThatThrownBy(() -> authService.login(new LoginRequest("9849520153", "abc@123")))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("more than one organization");

        verify(userDetailsService, never()).loadUserByUsername(anyString());
    }

    @Test
    void resolutionIsLimitedToManagerLogins() {
        when(userLoginRepository.existsByUsername("9849520153")).thenReturn(false);
        managerLoginsForMobile("9849520153@m103");

        try {
            authService.login(new LoginRequest("9849520153", "abc@123"));
        } catch (Exception ignored) {
            // not the subject of this assertion
        }

        // Only PROPERTY_MANAGER - tenants have their own mobile-based endpoint, and owners must
        // keep authenticating purely by username.
        verify(jdbc).queryForList(anyString(), eq(String.class), eq(RoleType.PROPERTY_MANAGER), eq("9849520153"));
    }

    @Test
    void whitespaceAroundTheMobileIsTolerated() {
        when(userLoginRepository.existsByUsername("9849520153")).thenReturn(false);
        managerLoginsForMobile("9849520153@m103");

        try {
            authService.login(new LoginRequest("  9849520153  ", "abc@123"));
        } catch (Exception ignored) {
            // not the subject of this assertion
        }

        verify(userDetailsService).loadUserByUsername("9849520153@m103");
    }
}
