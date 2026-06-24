package com.pgmanager.auth;

import com.pgmanager.audit.AuditService;
import com.pgmanager.auth.dto.AuthDtos.AuthResponse;
import com.pgmanager.auth.dto.AuthDtos.LoginRequest;
import com.pgmanager.auth.dto.AuthDtos.RefreshTokenRequest;
import com.pgmanager.auth.dto.AuthDtos.RegisterOwnerRequest;
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
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Base64;

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
    private final SecureRandom secureRandom = new SecureRandom();
    private static final Logger log = LoggerFactory.getLogger(AuthService.class);

    @Value("${app.security.refresh-token-days}")
    private long refreshTokenDays;

    @Transactional
    public AuthResponse registerOwner(RegisterOwnerRequest request) {
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
        return issueTokens((AppUserPrincipal) userDetailsService.loadUserByUsername(user.getUsername()));
    }

    @Transactional
    public AuthResponse login(LoginRequest request) {

        try {

            authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(
                            request.username(),
                            request.password()));

            AppUserPrincipal principal =
                    (AppUserPrincipal) userDetailsService.loadUserByUsername(
                            request.username());

            auditService.log(
                    principal.organizationId(),
                    principal.userLoginId(),
                    "LOGIN",
                    "USER_LOGIN",
                    principal.userLoginId(),
                    "User logged in");

            return issueTokens(principal);

        } catch (BadCredentialsException e) {

            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Invalid username or password");

        } catch (Exception e) {

            throw new ResponseStatusException(
                    HttpStatus.INTERNAL_SERVER_ERROR,
                    "Login failed");
        }
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
        return issueTokens(principal);
    }

    @Transactional
    public void logout(RefreshTokenRequest request) {
        refreshTokenRepository.findByTokenHashAndRevokedFalse(HashUtil.sha256(request.refreshToken()))
                .ifPresent(token -> token.setRevoked(true));
    }

    private AuthResponse issueTokens(AppUserPrincipal principal) {
        String accessToken = jwtService.createAccessToken(principal);
        String refreshTokenValue = randomToken();

        RefreshToken refreshToken = new RefreshToken();
        refreshToken.setUserLoginId(principal.userLoginId());
        refreshToken.setTokenHash(HashUtil.sha256(refreshTokenValue));
        refreshToken.setExpiresAt(LocalDateTime.now().plusDays(refreshTokenDays));
        refreshTokenRepository.save(refreshToken);

        return new AuthResponse(accessToken, refreshTokenValue, principal.organizationId(), principal.roleTypeId(), principal.fullName());
    }

    private String randomToken() {
        byte[] bytes = new byte[48];
        secureRandom.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}
