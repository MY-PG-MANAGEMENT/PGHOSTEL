package com.pgmanager.settings;

import com.pgmanager.auth.UserLogin;
import com.pgmanager.auth.UserLoginRepository;
import com.pgmanager.common.api.ApiResponse;
import com.pgmanager.common.exception.BadRequestException;
import com.pgmanager.common.util.HashUtil;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Base64;

@RestController
@RequestMapping("/api/auth/password")
@RequiredArgsConstructor
public class PublicAccountController {
    private final UserLoginRepository users;
    private final PasswordEncoder passwordEncoder;
    private final JdbcTemplate jdbc;

    @PostMapping("/forgot")
    ApiResponse<DeliveryStatus> forgot(@Valid @RequestBody ForgotRequest request) {
        users.findByUsername(request.username()).ifPresent(user -> {
            String raw = randomToken();
            jdbc.update("INSERT INTO password_reset_token(user_login_id,token_hash,expires_at,created_at) VALUES(?,?,?,?)",
                    user.getUserLoginId(), HashUtil.sha256(raw), LocalDateTime.now().plusMinutes(30), LocalDateTime.now());
            // Delivery is intentionally provider-neutral. A future WhatsApp adapter consumes the audit/outbox event.
        });
        return ApiResponse.ok("If the account exists, reset instructions will be sent when a delivery provider is configured",
                new DeliveryStatus(false, "WHATSAPP_NOT_CONFIGURED"));
    }

    @PostMapping("/reset")
    ApiResponse<Void> reset(@Valid @RequestBody ResetRequest request) {
        if (!request.newPassword().equals(request.confirmPassword()) || request.newPassword().length() < 8) {
            throw new BadRequestException("Password confirmation is invalid");
        }
        var rows = jdbc.queryForList("SELECT password_reset_token_id,user_login_id FROM password_reset_token " +
                "WHERE token_hash=? AND used_at IS NULL AND expires_at>?", HashUtil.sha256(request.token()), LocalDateTime.now());
        if (rows.isEmpty()) throw new BadRequestException("Reset token is invalid or expired");
        Long tokenId = ((Number) rows.getFirst().get("password_reset_token_id")).longValue();
        Long userId = ((Number) rows.getFirst().get("user_login_id")).longValue();
        UserLogin user = users.findById(userId).orElseThrow(() -> new BadRequestException("User is unavailable"));
        user.setPasswordHash(passwordEncoder.encode(request.newPassword()));
        users.save(user);
        jdbc.update("UPDATE password_reset_token SET used_at=? WHERE password_reset_token_id=?", LocalDateTime.now(), tokenId);
        jdbc.update("UPDATE refresh_token SET revoked=TRUE,updated_at=? WHERE user_login_id=?", LocalDateTime.now(), userId);
        return ApiResponse.ok("Password reset", null);
    }

    private String randomToken() {
        byte[] value = new byte[48];
        new SecureRandom().nextBytes(value);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(value);
    }

    public record ForgotRequest(@NotBlank String username) {}
    public record ResetRequest(@NotBlank String token, @NotBlank String newPassword, @NotBlank String confirmPassword) {}
    public record DeliveryStatus(boolean deliveryConfigured, String status) {}
}
