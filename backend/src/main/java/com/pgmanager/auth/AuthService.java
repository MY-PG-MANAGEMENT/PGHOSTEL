package com.pgmanager.auth;

import com.pgmanager.audit.AuditService;
import com.pgmanager.auth.dto.AuthDtos.AuthResponse;
import com.pgmanager.auth.dto.AuthDtos.LoginRequest;
import com.pgmanager.auth.dto.AuthDtos.RefreshTokenRequest;
import com.pgmanager.auth.dto.AuthDtos.RegisterOwnerRequest;
import com.pgmanager.auth.dto.AuthDtos.RegisterSuperAdminRequest;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.util.HashUtil;
import com.pgmanager.facility.Facility;
import com.pgmanager.facility.FacilityRepository;
import com.pgmanager.facility.FacilityType;
import com.pgmanager.party.*;
import com.pgmanager.security.AppUserDetailsService;
import com.pgmanager.security.AppUserPrincipal;
import com.pgmanager.security.JwtService;
import com.pgmanager.security.RoleType;
import org.springframework.jdbc.core.JdbcTemplate;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.authentication.LockedException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.List;

@Service
@RequiredArgsConstructor
public class AuthService {
    private final UserLoginRepository userLoginRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final PartyRepository partyRepository;
    private final PersonRepository personRepository;
    private final FacilityRepository facilityRepository;
    private final PasswordEncoder passwordEncoder;
    private final AuthenticationManager authenticationManager;
    private final AppUserDetailsService userDetailsService;
    private final JwtService jwtService;
    private final AuditService auditService;
    private final OrganizationStatusGuard organizationStatusGuard;
    private final JdbcTemplate jdbc;
    private final SecureRandom secureRandom = new SecureRandom();
    private static final Logger log = LoggerFactory.getLogger(AuthService.class);

    @Value("${app.security.refresh-token-days}")
    private long refreshTokenDays;

    @Transactional
    public AuthResponse registerSuperAdmin(RegisterSuperAdminRequest request) {
        if (userLoginRepository.existsByRoleTypeId(RoleType.SUPER_ADMIN)) {
            throw new BadRequestException("Super admin already exists. Use the admin panel to manage accounts.");
        }
        if (userLoginRepository.existsByUsername(request.username())) {
            throw new BadRequestException("Username already exists");
        }
        Party party = new Party();
        party.setPartyTypeId(PartyType.PERSON);
        party = partyRepository.save(party);

        Person person = new Person();
        person.setPartyId(party.getPartyId());
        person.setFullName(request.fullName());
        person.setMobileNumber(request.mobileNumber());
        personRepository.save(person);

        UserLogin user = new UserLogin();
        user.setPartyId(party.getPartyId());
        user.setUsername(request.username());
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setRoleTypeId(RoleType.SUPER_ADMIN);
        user.setOrganizationId(null);
        user = userLoginRepository.save(user);

        log.info("Super admin created: {}", user.getUsername());
        return issueTokens((AppUserPrincipal) userDetailsService.loadUserByUsername(user.getUsername()));
    }

    @Transactional
    public AuthResponse registerOwner(RegisterOwnerRequest request) {
        OwnerAccount account = createOwnerAccount(request);
        return issueTokens((AppUserPrincipal) userDetailsService.loadUserByUsername(account.username()));
    }

    /**
     * Creates the Party → Person → Facility(ORGANIZATION) → UserLogin(OWNER) graph for a new
     * organization without logging the caller in. Used by the super-admin panel to provision an
     * organization and its owner login. {@link #registerOwner} wraps this and issues tokens.
     */
    @Transactional
    public OwnerAccount createOwnerAccount(RegisterOwnerRequest request) {
        if (userLoginRepository.existsByUsername(request.username())) {
            throw new BadRequestException("Username already exists");
        }

        Party party = new Party();
        party.setPartyTypeId(PartyType.PERSON);
        party = partyRepository.save(party);

        Person person = new Person();
        person.setPartyId(party.getPartyId());
        person.setFullName(request.fullName());
        person.setMobileNumber(request.mobileNumber());
        personRepository.save(person);

        Facility organization = new Facility();
        organization.setFacilityTypeId(FacilityType.ORGANIZATION);
        organization.setFacilityName(request.organizationName());
        organization.setEmail(request.organizationEmail());
        organization = facilityRepository.save(organization);
        organization.setFacilityCode("ORG_" + organization.getFacilityId());
        organization = facilityRepository.save(organization);

        UserLogin user = new UserLogin();
        user.setPartyId(party.getPartyId());
        user.setUsername(request.username());
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setRoleTypeId(RoleType.OWNER);
        user.setOrganizationId(organization.getFacilityId());
        user = userLoginRepository.save(user);

        auditService.log(organization.getFacilityId(), user.getUserLoginId(), "OWNER_REGISTERED", "USER_LOGIN", user.getUserLoginId(), "Owner registered");
        return new OwnerAccount(organization.getFacilityId(), organization.getFacilityName(), user.getUserLoginId(), user.getUsername());
    }

    public record OwnerAccount(Long organizationId, String organizationName, Long userLoginId, String username) {}

    @Transactional
    public AuthResponse login(LoginRequest request) {
        AppUserPrincipal principal = authenticate(request);

        // Credentials are good, but a deactivated/suspended organization has no access at all.
        // Deliberately outside authenticate()'s catch-all, which would mask the 403 as a 500.
        organizationStatusGuard.assertActive(principal.organizationId());

        auditService.log(
                principal.organizationId(),
                principal.userLoginId(),
                "LOGIN",
                "USER_LOGIN",
                principal.userLoginId(),
                "User logged in");

        return issueTokens(principal);
    }

    private AppUserPrincipal authenticate(LoginRequest request) {
        String username = resolveStaffMobile(request.username());
        try {

            authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(
                            username,
                            request.password()));

            return (AppUserPrincipal) userDetailsService.loadUserByUsername(username);

        } catch (BadCredentialsException e) {

            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Invalid username or password");

        } catch (DisabledException | LockedException e) {

            // A non-ACTIVE user_login row: a real 401, not the 500 the catch-all used to return.
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "This account is inactive. Contact your administrator.");

        } catch (Exception e) {

            log.error("Login failed for {}", request.username(), e);
            throw new ResponseStatusException(
                    HttpStatus.INTERNAL_SERVER_ERROR,
                    "Login failed");
        }
    }

    /**
     * Lets a property manager sign in with just their <b>mobile number</b>.
     *
     * <p>{@code user_login.username} is globally unique, so a manager's login is stored as
     * {@code {mobile}@m{orgId}} — necessary, but not something an owner should have to dictate over
     * the phone. This resolves a bare 10-digit entry to that stored username, so the credential the
     * owner hands over is simply the mobile number.
     *
     * <p>Order is load-bearing: an <b>exact</b> username match always wins, so an owner whose chosen
     * username happens to be ten digits is unaffected and authenticates exactly as before. Only
     * PROPERTY_MANAGER logins are resolved this way — the narrowest blast radius, since they are the
     * only ones minted with the suffixed scheme.
     *
     * <p>Ambiguity (the same person managing properties for two different organizations) is left
     * alone rather than guessed at: the input passes through unchanged and fails, and the message
     * below tells them to use the full username. Guessing an organization at the login boundary
     * would be the wrong kind of helpful.
     */
    private String resolveStaffMobile(String input) {
        String candidate = input == null ? "" : input.trim();
        if (!candidate.matches("\\d{10}")) return input;
        if (userLoginRepository.existsByUsername(candidate)) return input;

        List<String> matches = jdbc.queryForList(
                "SELECT ul.username FROM user_login ul " +
                "JOIN person p ON p.party_id = ul.party_id " +
                "WHERE ul.role_type_id = ? AND ul.status = 'ACTIVE' AND p.mobile_number = ?",
                String.class, RoleType.PROPERTY_MANAGER, candidate);
        if (matches.size() == 1) return matches.get(0);
        if (matches.size() > 1) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                    "This mobile number has manager logins in more than one organization. "
                            + "Sign in with the full username your owner gave you.");
        }
        return input;
    }


    @Transactional
    public AuthResponse refresh(RefreshTokenRequest request) {
        String tokenHash = HashUtil.sha256(request.refreshToken());
        RefreshToken refreshToken = refreshTokenRepository.findByTokenHashAndRevokedFalse(tokenHash)
                .orElseThrow(() -> new BadRequestException("Invalid refresh token"));
        if (refreshToken.getExpiresAt().isBefore(LocalDateTime.now())) {
            refreshToken.setRevoked(true);
            throw new BadRequestException("Refresh token expired");
        }
        UserLogin user = userLoginRepository.findById(refreshToken.getUserLoginId())
                .orElseThrow(() -> new BadRequestException("User not found"));
        refreshToken.setRevoked(true);
        AppUserPrincipal principal = (AppUserPrincipal) userDetailsService.loadUserByUsername(user.getUsername());
        // Re-checked on every rotation, so deactivating an org also stops sessions already running.
        organizationStatusGuard.assertActive(principal.organizationId());
        return issueTokens(principal);
    }

    @Transactional
    public void logout(RefreshTokenRequest request) {
        refreshTokenRepository.findByTokenHashAndRevokedFalse(HashUtil.sha256(request.refreshToken()))
                .ifPresent(token -> token.setRevoked(true));
    }

    /** Issues an access + refresh token pair for an already-authenticated principal. */
    public AuthResponse issueTokensFor(AppUserPrincipal principal) {
        return issueTokens(principal);
    }

    private AuthResponse issueTokens(AppUserPrincipal principal) {
        String accessToken = jwtService.createAccessToken(principal);
        String refreshTokenValue = randomToken();

        RefreshToken refreshToken = new RefreshToken();
        refreshToken.setUserLoginId(principal.userLoginId());
        refreshToken.setTokenHash(HashUtil.sha256(refreshTokenValue));
        refreshToken.setExpiresAt(LocalDateTime.now().plusDays(refreshTokenDays));
        refreshTokenRepository.save(refreshToken);

        return new AuthResponse(accessToken, refreshTokenValue, principal.organizationId(),
                principal.roleTypeId(), principal.fullName(), false, principal.partyId());
    }

    private String randomToken() {
        byte[] bytes = new byte[48];
        secureRandom.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}
