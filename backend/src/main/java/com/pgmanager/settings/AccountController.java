package com.pgmanager.settings;

import com.pgmanager.auth.UserLogin;
import com.pgmanager.auth.UserLoginRepository;
import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.party.Person;
import com.pgmanager.party.PersonRepository;
import com.pgmanager.security.AppUserPrincipal;
import com.pgmanager.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/account")
@RequiredArgsConstructor
public class AccountController {
    private final CurrentUser currentUser;
    private final PersonRepository personRepository;
    private final UserLoginRepository userLoginRepository;
    private final PasswordEncoder passwordEncoder;
    private final JdbcTemplate jdbc;

    @GetMapping("/profile")
    ApiResponse<Map<String, Object>> profile() {
        AppUserPrincipal principal = currentUser.principal();
        Person person = personRepository.findById(principal.partyId())
                .orElseThrow(() -> new BadRequestException("Profile is unavailable"));
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("partyId", person.getPartyId());
        result.put("fullName", person.getFullName());
        result.put("mobileNumber", person.getMobileNumber());
        result.put("gender", person.getGender());
        result.put("dateOfBirth", person.getDateOfBirth());
        result.put("email", principal.username());
        result.put("roleTypeId", principal.roleTypeId());
        result.put("organizationId", principal.organizationId());
        return ApiResponse.ok(result);
    }

    @PatchMapping("/profile")
    ApiResponse<Map<String, Object>> updateProfile(@Valid @RequestBody ProfileRequest request) {
        Person person = personRepository.findById(currentUser.principal().partyId())
                .orElseThrow(() -> new BadRequestException("Profile is unavailable"));
        person.setFullName(request.fullName());
        person.setMobileNumber(request.mobileNumber());
        person.setGender(request.gender());
        person.setDateOfBirth(request.dateOfBirth());
        personRepository.save(person);
        return profile();
    }

    @PostMapping("/change-password")
    ApiResponse<Void> changePassword(@Valid @RequestBody ChangePasswordRequest request) {
        if (!request.newPassword().equals(request.confirmPassword())) {
            throw new BadRequestException("New password and confirmation do not match");
        }
        validatePassword(request.newPassword());
        UserLogin user = userLoginRepository.findById(currentUser.userLoginId())
                .orElseThrow(() -> new BadRequestException("User is unavailable"));
        if (!passwordEncoder.matches(request.currentPassword(), user.getPasswordHash())) {
            throw new BadRequestException("Current password is incorrect");
        }
        user.setPasswordHash(passwordEncoder.encode(request.newPassword()));
        userLoginRepository.save(user);
        jdbc.update("UPDATE refresh_token SET revoked=TRUE, updated_at=? WHERE user_login_id=?", LocalDateTime.now(), user.getUserLoginId());
        return ApiResponse.ok("Password updated; other sessions were signed out", null);
    }

    @GetMapping("/preferences")
    ApiResponse<Map<String, String>> preferences() {
        Map<String, String> values = new LinkedHashMap<>();
        jdbc.query("SELECT preference_key, preference_value FROM user_preference WHERE user_login_id=?",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> values.put(rs.getString(1), rs.getString(2)), currentUser.userLoginId());
        values.putIfAbsent("theme", "LIGHT");
        values.putIfAbsent("accentColor", "PURPLE");
        values.putIfAbsent("fontSize", "MEDIUM");
        values.putIfAbsent("language", "en");
        values.putIfAbsent("currency", "INR");
        values.putIfAbsent("dateFormat", "dd MMM yyyy");
        values.putIfAbsent("timeFormat", "12_HOUR");
        values.putIfAbsent("defaultDashboard", "OVERVIEW");
        values.putIfAbsent("notificationSound", "true");
        values.putIfAbsent("notificationVibration", "true");
        return ApiResponse.ok(values);
    }

    @PatchMapping("/preferences")
    ApiResponse<Map<String, String>> updatePreferences(@RequestBody Map<String, String> updates) {
        List<String> allowed = List.of("theme", "accentColor", "fontSize", "language", "currency", "dateFormat",
                "timeFormat", "defaultDashboard", "notificationSound", "notificationVibration");
        updates.forEach((key, value) -> {
            if (!allowed.contains(key)) throw new BadRequestException("Unsupported preference: " + key);
            jdbc.update("INSERT INTO user_preference(user_login_id,preference_key,preference_value,updated_at) VALUES(?,?,?,?) " +
                            "ON DUPLICATE KEY UPDATE preference_value=VALUES(preference_value),updated_at=VALUES(updated_at)",
                    currentUser.userLoginId(), key, value, LocalDateTime.now());
        });
        return preferences();
    }

    @GetMapping("/sessions")
    ApiResponse<List<Map<String, Object>>> sessions() {
        return ApiResponse.ok(jdbc.queryForList("SELECT user_device_id,platform,biometric_enabled,last_seen_at,revoked_at " +
                "FROM user_device WHERE user_login_id=? ORDER BY last_seen_at DESC", currentUser.userLoginId()));
    }

    @PostMapping("/devices")
    ApiResponse<Map<String, Object>> registerDevice(@Valid @RequestBody DeviceRequest request) {
        jdbc.update("INSERT INTO user_device(user_login_id,device_identifier_hash,platform,biometric_enabled,push_token,last_seen_at) " +
                        "VALUES(?,?,?,?,?,?) ON DUPLICATE KEY UPDATE platform=VALUES(platform),biometric_enabled=VALUES(biometric_enabled)," +
                        "push_token=VALUES(push_token),last_seen_at=VALUES(last_seen_at),revoked_at=NULL",
                currentUser.userLoginId(), request.deviceIdentifierHash(), request.platform(), request.biometricEnabled(),
                request.pushToken(), LocalDateTime.now());
        return ApiResponse.ok(Map.of("registered", true, "biometricEnabled", request.biometricEnabled()));
    }

    private void validatePassword(String password) {
        if (password.length() < 8 || password.chars().noneMatch(Character::isUpperCase)
                || password.chars().noneMatch(Character::isLowerCase) || password.chars().noneMatch(Character::isDigit)
                || password.chars().allMatch(Character::isLetterOrDigit)) {
            throw new BadRequestException("Password must have 8 characters with upper, lower, number and special character");
        }
    }

    public record ProfileRequest(@NotBlank String fullName, @NotBlank String mobileNumber, String gender, LocalDate dateOfBirth) {}
    public record ChangePasswordRequest(@NotBlank String currentPassword, @NotBlank String newPassword, @NotBlank String confirmPassword) {}
    public record DeviceRequest(@NotBlank String deviceIdentifierHash, @NotBlank String platform, boolean biometricEnabled, String pushToken) {}
}

