package com.pgmanager.apilog;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * Binds {@code logging.api.*} into {@link ApiLogProperties}.
 *
 * <p>Kept as its own unconditional configuration so the properties bean exists even when
 * {@code logging.api.async=false} switches {@link ApiLogAsyncConfig} off — the filter, the
 * interceptor and the cleanup job all need it regardless of the write mode.
 */
@Configuration
@EnableConfigurationProperties(ApiLogProperties.class)
public class ApiLogConfig {
}
