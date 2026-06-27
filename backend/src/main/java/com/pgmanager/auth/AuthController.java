package com.pgmanager.auth;

import com.pgmanager.auth.dto.AuthDtos.AuthResponse;
import com.pgmanager.auth.dto.AuthDtos.LoginRequest;
import com.pgmanager.auth.dto.AuthDtos.RefreshTokenRequest;
import com.pgmanager.auth.dto.AuthDtos.RegisterOwnerRequest;
import com.pgmanager.auth.dto.AuthDtos.RegisterSuperAdminRequest;
import com.pgmanager.common.api.ApiResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {
    private final AuthService authService;

    @PostMapping("/register-super-admin")
    ApiResponse<AuthResponse> registerSuperAdmin(@Valid @RequestBody RegisterSuperAdminRequest request) {
        return ApiResponse.ok("Super admin created", authService.registerSuperAdmin(request));
    }

    @PostMapping("/register-owner")
    ApiResponse<AuthResponse> registerOwner(@Valid @RequestBody RegisterOwnerRequest request) {
        return ApiResponse.ok("Owner registered", authService.registerOwner(request));
    }

    @PostMapping("/login")
    ApiResponse<AuthResponse> login(@Valid @RequestBody LoginRequest request) {
        return ApiResponse.ok("Logged in", authService.login(request));
    }

    @PostMapping("/refresh")
    ApiResponse<AuthResponse> refresh(@Valid @RequestBody RefreshTokenRequest request) {
        return ApiResponse.ok(authService.refresh(request));
    }

    @PostMapping("/logout")
    ApiResponse<Void> logout(@Valid @RequestBody RefreshTokenRequest request) {
        authService.logout(request);
        return ApiResponse.ok("Logged out", null);
    }
}
