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

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Full-stack integration test against a real MySQL via Testcontainers + Flyway.
 *
 * <p>Requires Docker. {@code disabledWithoutDocker = true} makes the whole class
 * skip cleanly on machines without Docker (e.g. local dev here) while still
 * running in CI where Docker is available. Use this as the template for adding
 * more DB-backed endpoint tests (tenant create, bed assign, billing, etc.).
 */
@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest
@AutoConfigureMockMvc
class AuthFlowIntegrationTest {

    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.0")
            .withDatabaseName("pg_manager");

    @DynamicPropertySource
    static void datasourceProps(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
    }

    @Autowired MockMvc mvc;
    private final ObjectMapper json = new ObjectMapper();

    @Test
    void ownerCanRegisterThenLogin() throws Exception {
        String register = "{\"fullName\":\"Asha Rao\",\"mobileNumber\":\"9811122233\"," +
                "\"username\":\"asha_owner\",\"password\":\"secret123\",\"organizationName\":\"Asha PG\"}";

        String body = mvc.perform(post("/api/auth/register-owner")
                        .contentType(MediaType.APPLICATION_JSON).content(register))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.accessToken").isNotEmpty())
                .andReturn().getResponse().getContentAsString();

        JsonNode node = json.readTree(body);
        assert node.path("data").path("organizationId").asLong() > 0;

        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"asha_owner\",\"password\":\"secret123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.roleTypeId").value("OWNER"));
    }

    @Test
    void loginWithWrongPasswordFails() throws Exception {
        mvc.perform(post("/api/auth/register-owner").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fullName\":\"Ben Roy\",\"mobileNumber\":\"9811199999\"," +
                                "\"username\":\"ben_owner\",\"password\":\"secret123\",\"organizationName\":\"Ben PG\"}"))
                .andExpect(status().isOk());

        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"ben_owner\",\"password\":\"wrongpass\"}"))
                .andExpect(status().is4xxClientError());
    }
}
