package com.pgmanager.security;

import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.AuthenticationProvider;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

@Configuration
@EnableMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {
    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final AppUserDetailsService userDetailsService;

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http.csrf(csrf -> csrf.disable())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/api/auth/**", "/api/public/**", "/swagger-ui/**", "/swagger-ui.html", "/v3/api-docs/**").permitAll()
                        .requestMatchers("/api/super-admin/**").hasRole(RoleType.SUPER_ADMIN)
                        // Tenant portal — must precede the generic /api/** guard (which excludes TENANT).
                        .requestMatchers("/api/tenant/**").hasRole(RoleType.TENANT)
                        .requestMatchers("/api/**").hasAnyRole(
                                RoleType.OWNER, RoleType.PROPERTY_MANAGER, RoleType.MANAGER,
                                RoleType.ACCOUNTANT, RoleType.SUPPORT, RoleType.VIEWER)
                        .anyRequest().authenticated()
                )
                // Unauthenticated -> 401, not the Spring default 403.
                //
                // With no authentication mechanism registered (no formLogin, no httpBasic
                // — this is a stateless JWT API), Spring Security falls back to
                // Http403ForbiddenEntryPoint, so a request with a missing or expired token
                // came back 403. That is the wrong status, and it also silently disabled
                // the Flutter client's token refresh: ApiClient retries through
                // /auth/refresh on 401 only, so an expired access token surfaced as a hard
                // error instead of refreshing. 403 stays reserved for an authenticated
                // caller who lacks the role (see GlobalExceptionHandler.accessDenied),
                // which is the distinction the app relies on for a deactivated org.
                .exceptionHandling(ex -> ex.authenticationEntryPoint((req, res, authEx) -> {
                    res.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                    res.setContentType(MediaType.APPLICATION_JSON_VALUE);
                    // Same ApiResponse envelope every other error uses, so the client's
                    // JSON decode path does not have to special-case this one.
                    res.getWriter().write("{\"success\":false,\"message\":\"Unauthorized\",\"data\":null}");
                }))
                .authenticationProvider(authenticationProvider())
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    AuthenticationProvider authenticationProvider() {
        DaoAuthenticationProvider provider = new DaoAuthenticationProvider();
        provider.setUserDetailsService(userDetailsService);
        provider.setPasswordEncoder(passwordEncoder());
        return provider;
    }

    @Bean
    AuthenticationManager authenticationManager(AuthenticationConfiguration configuration) throws Exception {
        return configuration.getAuthenticationManager();
    }

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
