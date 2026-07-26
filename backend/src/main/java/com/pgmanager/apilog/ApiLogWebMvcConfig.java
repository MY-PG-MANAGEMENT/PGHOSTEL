package com.pgmanager.apilog;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Registers the identity/handler interceptor for every path.
 *
 * <p>{@code addPathPatterns("/**")} with no exclusions is intentional: the requirement is to log
 * every hit. Filtering belongs in one place — {@link ApiLogProperties#isEnabled()} — not spread
 * across a pattern list that drifts from the filter's own view of what counts.
 */
@Configuration
@RequiredArgsConstructor
public class ApiLogWebMvcConfig implements WebMvcConfigurer {

    private final ApiLogHandlerInterceptor apiLogHandlerInterceptor;

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(apiLogHandlerInterceptor).addPathPatterns("/**");
    }
}
