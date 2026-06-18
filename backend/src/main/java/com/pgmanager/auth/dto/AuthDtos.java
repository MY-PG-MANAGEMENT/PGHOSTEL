package com.pgmanager.auth.dto;

import jakarta.validation.constraints.NotBlank;

public final class AuthDtos {
    private AuthDtos() {
    }

    public record RegisterOwnerRequest(
            @NotBlank String fullName,
            @NotBlank String mobileNumber,
            @NotBlank String username,
            @NotBlank String password,
            @NotBlank String organizationName
    ) {
    }

    public record LoginRequest(@NotBlank String username, @NotBlank String password) {
    }

    public record RefreshTokenRequest(@NotBlank String refreshToken) {
    }

    public record AuthResponse(String accessToken, String refreshToken, Long organizationId, String roleTypeId) {
    }
}
