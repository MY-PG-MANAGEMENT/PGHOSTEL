package com.pgmanager.apilog;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pgmanager.common.exception.GlobalExceptionHandler;
import com.pgmanager.security.AppUserPrincipal;
import com.pgmanager.security.RoleType;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Filter + interceptor + advice together through a real dispatch, using the sample controller.
 *
 * <p>This is the test that proves the architecture rather than the parts: {@code controllerName} /
 * {@code methodName} can only be populated by the interceptor, identity can only be read while the
 * dispatch is in flight, and {@code errorCode} can only come from the advice. If any one of the
 * three were removed, a column here would go null.
 *
 * <p>MockMvc's standalone setup is used (no Spring context, no database) so the whole path runs in
 * milliseconds; the write side is the same collecting stub as the filter unit test.
 */
class ApiLogEndToEndTest {

    private MockMvc mvc;
    private ApiLogProperties properties;
    private final List<ApiRequestLog> written = new ArrayList<>();

    @BeforeEach
    void setUp() {
        properties = new ApiLogProperties();
        ObjectMapper mapper = new ObjectMapper();
        ApiLogWriter writer = written::add;

        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();

        mvc = MockMvcBuilders
                .standaloneSetup(new ApiLogDemoController(mock(ApiRequestLogRepository.class)))
                .setControllerAdvice(new GlobalExceptionHandler())
                .setValidator(validator)
                .addFilters(new ApiLogFilter(properties, new SensitiveDataMasker(mapper), writer, mapper))
                .addInterceptors(new ApiLogHandlerInterceptor(properties))
                .build();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private void authenticateAs(String role, Long orgId, Long userLoginId, Long partyId) {
        AppUserPrincipal principal = new AppUserPrincipal(
                userLoginId, partyId, orgId, "user@pg.com", "hash", role, "ACTIVE", "Test User");
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(principal, null, principal.getAuthorities()));
    }

    private ApiRequestLog only() {
        assertThat(written).hasSize(1);
        return written.get(0);
    }

    @Test
    void logsAnAuthenticatedOwnerCallWithHandlerAndIdentityResolved() throws Exception {
        authenticateAs(RoleType.OWNER, 42L, 7L, 99L);

        mvc.perform(post("/api/api-logs/demo/echo")
                        .contentType("application/json")
                        .header("App-Version", "1.4.2")
                        .header("Platform", "android")
                        .content("{\"username\":\"owner\",\"password\":\"hunter2\",\"otp\":\"445566\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        ApiRequestLog entry = only();
        // Only the interceptor can supply these two.
        assertThat(entry.getControllerName()).isEqualTo("ApiLogDemoController");
        assertThat(entry.getMethodName()).isEqualTo("echo");
        // Identity would be null here if it were read after the chain unwound.
        assertThat(entry.getOrganizationId()).isEqualTo(42L);
        assertThat(entry.getUserLoginId()).isEqualTo(7L);
        // An OWNER is not a resident, so tenantId stays null.
        assertThat(entry.getTenantId()).isNull();
        assertThat(entry.getStatus()).isEqualTo(ApiLogStatus.SUCCESS);
        assertThat(entry.getAppVersion()).isEqualTo("1.4.2");
        assertThat(entry.getRequestBody()).doesNotContain("hunter2").doesNotContain("445566");
        assertThat(entry.getExecutionTimeMs()).isNotNull();
    }

    @Test
    void populatesTenantIdOnlyForATenantLogin() throws Exception {
        authenticateAs(RoleType.TENANT, 42L, 300L, 555L);

        mvc.perform(post("/api/api-logs/demo/echo")
                        .contentType("application/json")
                        .content("{\"username\":\"tenant\",\"password\":\"x1234567\"}"))
                .andExpect(status().isOk());

        // partyId doubles as the tenant id, but only when the login is a TENANT.
        assertThat(only().getTenantId()).isEqualTo(555L);
    }

    @Test
    void logsAnonymousTrafficWithNullIdentity() throws Exception {
        mvc.perform(get("/api/api-logs/demo/boom")).andExpect(status().isBadRequest());

        ApiRequestLog entry = only();
        assertThat(entry.getOrganizationId()).isNull();
        assertThat(entry.getUserLoginId()).isNull();
        assertThat(entry.getTenantId()).isNull();
    }

    @Test
    void recordsExceptionDetailsAndStillReturnsTheOriginalErrorResponse() throws Exception {
        mvc.perform(get("/api/api-logs/demo/boom"))
                .andExpect(status().isBadRequest())
                // The client contract is untouched — the logger observes, it does not intervene.
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.message").value("Demonstration failure - this request is logged as EXCEPTION"));

        ApiRequestLog entry = only();
        assertThat(entry.getStatus()).isEqualTo(ApiLogStatus.EXCEPTION);
        // Only the advice can supply these — the filter sees just a 400.
        assertThat(entry.getErrorCode()).isEqualTo("BadRequestException");
        assertThat(entry.getErrorMessage()).isEqualTo("Demonstration failure - this request is logged as EXCEPTION");
        assertThat(entry.getResponseStatusCode()).isEqualTo(400);
    }

    @Test
    void logsValidationFailuresWithTheAggregatedFieldMessage() throws Exception {
        mvc.perform(post("/api/api-logs/demo/echo")
                        .contentType("application/json")
                        .content("{\"username\":\"\",\"password\":\"\"}"))
                .andExpect(status().isBadRequest());

        ApiRequestLog entry = only();
        assertThat(entry.getStatus()).isEqualTo(ApiLogStatus.EXCEPTION);
        assertThat(entry.getErrorCode()).isEqualTo("MethodArgumentNotValidException");
        assertThat(entry.getErrorMessage()).contains("username");
    }

    @Test
    void capturesTheResponseBodyWithoutBreakingIt() throws Exception {
        authenticateAs(RoleType.OWNER, 1L, 1L, 1L);

        String body = mvc.perform(post("/api/api-logs/demo/echo")
                        .contentType("application/json")
                        .content("{\"username\":\"owner\",\"password\":\"secret12\"}"))
                .andReturn().getResponse().getContentAsString();

        // The client got a complete body...
        assertThat(body).contains("\"username\":\"owner\"");
        // ...and the same bytes were logged.
        assertThat(only().getResponseBody()).contains("\"username\":\"owner\"");
    }

    @Test
    void writesExactlyOneRowPerRequest() throws Exception {
        mvc.perform(get("/api/api-logs/demo/boom")).andExpect(status().isBadRequest());
        mvc.perform(get("/api/api-logs/demo/boom")).andExpect(status().isBadRequest());

        // OncePerRequestFilter plus a single write call site — no double logging.
        assertThat(written).hasSize(2);
    }
}
