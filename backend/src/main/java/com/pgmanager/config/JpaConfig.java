package com.pgmanager.config;

import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * Spring Data JPA configuration
 * Explicitly enables repository scanning and entity scanning for pg-manager package
 */
@Configuration
@EnableJpaRepositories(basePackages = "com.pgmanager")
@EntityScan(basePackages = "com.pgmanager")
public class JpaConfig {
    // Explicit JPA configuration for repository and entity scanning
}
