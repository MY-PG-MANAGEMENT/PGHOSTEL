package com.pgmanager.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public final class AuthDtos {
    private AuthDtos() {
    }

    public record RegisterOwnerRequest(
            @NotBlank @Size(min = 2, max = 100) String fullName,
            @NotBlank @Pattern(regexp = "^[0-9]{10}$", message = "must be a 10-digit number") String mobileNumber,
            @NotBlank @Size(min = 4, max = 50)
            @Pattern(regexp = "^[a-zA-Z0-9_]+$", message = "only letters, digits, and underscores") String username,
            @NotBlank @Size(min = 8, message = "must be at least 8 characters") String password,
            @NotBlank @Size(min = 2, max = 100) String organizationName
    ) {
    }

    public record RegisterSuperAdminRequest(
            @NotBlank @Size(min = 2, max = 100) String fullName,
            @NotBlank @Pattern(regexp = "^[0-9]{10}$", message = "must be a 10-digit number") String mobileNumber,
            @NotBlank @Size(min = 4, max = 50)
            @Pattern(regexp = "^[a-zA-Z0-9_]+$", message = "only letters, digits, and underscores") String username,
            @NotBlank @Size(min = 8, message = "must be at least 8 characters") String password
    ) {
    }

    public record LoginRequest(@NotBlank String username, @NotBlank String password) {
    }

    public record RefreshTokenRequest(@NotBlank String refreshToken) {
    }

    public record AuthResponse(String accessToken, String refreshToken, Long organizationId, String roleTypeId, String fullName) {
    }
}
