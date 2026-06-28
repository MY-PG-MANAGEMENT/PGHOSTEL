package com.pgmanager.integration;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Verifies the role guard on /api/super-admin/** through the real Spring Security
 * filter chain: an OWNER token is forbidden (403) and an anonymous request is
 * unauthorized (401). Requires Docker; auto-skips when unavailable.
 */
@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest
@AutoConfigureMockMvc
class SuperAdminAccessIntegrationTest {

    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.0").withDatabaseName("pg_manager");

    @DynamicPropertySource
    static void datasourceProps(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
    }

    @Autowired MockMvc mvc;
    private final ObjectMapper json = new ObjectMapper();

    private String registerOwnerToken() throws Exception {
        long n = System.nanoTime();
        String username = "owner_" + Long.toUnsignedString(n);
        String mobile = "9" + String.format("%09d", Math.abs(n % 1_000_000_000L));
        String body = "{\"fullName\":\"Test Owner\",\"mobileNumber\":\"" + mobile + "\"," +
                "\"username\":\"" + username + "\",\"password\":\"secret123\",\"organizationName\":\"Test PG\"}";
        String resp = mvc.perform(post("/api/auth/register-owner")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        JsonNode data = json.readTree(resp).path("data");
        return data.path("accessToken").asText();
    }

    @Test
    void ownerTokenIsForbiddenFromSuperAdmin() throws Exception {
        String token = registerOwnerToken();
        mvc.perform(get("/api/super-admin/dashboard").header("Authorization", "Bearer " + token))
                .andExpect(status().isForbidden());
    }

    @Test
    void anonymousIsUnauthorizedFromSuperAdmin() throws Exception {
        mvc.perform(get("/api/super-admin/dashboard"))
                .andExpect(status().isUnauthorized());
    }
}
