package com.pgmanager.apilog;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Filter behaviour with no Spring context and no database — the writer is a collecting stub, which
 * is exactly what the {@link ApiLogWriter} abstraction exists to make possible.
 */
class ApiLogFilterTest {

    private ApiLogProperties properties;
    private CollectingWriter writer;
    private ApiLogFilter filter;

    /** Stand-in for the event publisher; keeps assertions on plain objects. */
    private static class CollectingWriter implements ApiLogWriter {
        private final List<ApiRequestLog> entries = new ArrayList<>();
        @Override public void write(ApiRequestLog entry) { entries.add(entry); }
        ApiRequestLog only() {
            assertThat(entries).hasSize(1);
            return entries.get(0);
        }
    }

    @BeforeEach
    void setUp() {
        properties = new ApiLogProperties();
        writer = new CollectingWriter();
        ObjectMapper mapper = new ObjectMapper();
        filter = new ApiLogFilter(properties, new SensitiveDataMasker(mapper), writer, mapper);
    }

    private MockHttpServletRequest postJson(String uri, String body) {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", uri);
        request.setContentType("application/json");
        request.setContent(body.getBytes());
        return request;
    }

    @Test
    void logsOneRowPerRequestWithTheCoreFields() throws Exception {
        MockHttpServletRequest request = postJson("/api/tenants", "{\"fullName\":\"Asha\"}");
        request.setQueryString("propertyId=4");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        ApiRequestLog entry = writer.only();
        assertThat(entry.getRequestUri()).isEqualTo("/api/tenants");
        assertThat(entry.getHttpMethod()).isEqualTo("POST");
        assertThat(entry.getQueryParameters()).isEqualTo("propertyId=4");
        assertThat(entry.getStatus()).isEqualTo(ApiLogStatus.SUCCESS);
        assertThat(entry.getResponseStatusCode()).isEqualTo(200);
        assertThat(entry.getRequestStartTime()).isNotNull();
        assertThat(entry.getRequestEndTime()).isNotNull();
        assertThat(entry.getExecutionTimeMs()).isNotNull().isGreaterThanOrEqualTo(0L);
        assertThat(entry.getCreatedDate()).isNotNull();
    }

    @Test
    void capturesFlutterDeviceHeaders() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/dashboard");
        request.addHeader("App-Version", "1.4.2");
        request.addHeader("Build-Number", "142");
        request.addHeader("Platform", "android");
        request.addHeader("OS-Name", "Android");
        request.addHeader("OS-Version", "14");
        request.addHeader("Device-Model", "Pixel 7");
        request.addHeader("Manufacturer", "Google");
        request.addHeader("Network-Type", "wifi");
        request.addHeader("User-Agent", "Dart/3.5 (dart:io)");

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        ApiRequestLog entry = writer.only();
        assertThat(entry.getAppVersion()).isEqualTo("1.4.2");
        assertThat(entry.getBuildNumber()).isEqualTo("142");
        assertThat(entry.getPlatform()).isEqualTo("android");
        assertThat(entry.getOsName()).isEqualTo("Android");
        assertThat(entry.getOsVersion()).isEqualTo("14");
        assertThat(entry.getDeviceModel()).isEqualTo("Pixel 7");
        assertThat(entry.getManufacturer()).isEqualTo("Google");
        assertThat(entry.getNetworkType()).isEqualTo("wifi");
        assertThat(entry.getUserAgent()).isEqualTo("Dart/3.5 (dart:io)");
    }

    @Test
    void honoursClientRequestIdAndEchoesItBack() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/dashboard");
        request.addHeader("X-Request-Id", "flutter-abc-123");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        assertThat(writer.only().getRequestId()).isEqualTo("flutter-abc-123");
        // Echoing it is what lets a user quote an id off a failure screen.
        assertThat(response.getHeader("X-Request-Id")).isEqualTo("flutter-abc-123");
    }

    @Test
    void generatesARequestIdWhenTheClientSendsNone() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(new MockHttpServletRequest("GET", "/api/dashboard"), response, new MockFilterChain());

        assertThat(writer.only().getRequestId()).isNotBlank();
        assertThat(response.getHeader("X-Request-Id")).isNotBlank();
    }

    @Test
    void masksRequestBodyAndAuthorizationHeader() throws Exception {
        MockHttpServletRequest request = postJson("/api/auth/login",
                "{\"username\":\"owner\",\"password\":\"hunter2\"}");
        request.addHeader("Authorization", "Bearer real-token-value");

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        ApiRequestLog entry = writer.only();
        assertThat(entry.getRequestBody()).doesNotContain("hunter2").contains("***MASKED***");
        assertThat(entry.getRequestHeaders()).doesNotContain("real-token-value").contains("***MASKED***");
    }

    @Test
    void capturesResponseBodyAndStillDeliversItToTheClient() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = (req, res) -> {
            res.setContentType("application/json");
            res.getWriter().write("{\"success\":true}");
        };

        filter.doFilter(new MockHttpServletRequest("GET", "/api/dashboard"), response, chain);

        assertThat(writer.only().getResponseBody()).contains("\"success\":true");
        // The regression that matters: forgetting copyBodyToResponse() empties every response.
        assertThat(response.getContentAsString()).isEqualTo("{\"success\":true}");
    }

    /**
     * The chain sees the {@link ApiLogResponseWrapper}, not the mock — casting to
     * MockHttpServletResponse here would be casting to the wrong type. The wrapper delegates
     * {@code setStatus} to the real response, which is what the filter reads back.
     */
    private static FilterChain respondWith(int status) {
        return (req, res) -> ((jakarta.servlet.http.HttpServletResponse) res).setStatus(status);
    }

    @Test
    void mapsUnauthorizedAndForbiddenAheadOfEverythingElse() throws Exception {
        filter.doFilter(new MockHttpServletRequest("GET", "/api/tenants"),
                new MockHttpServletResponse(), respondWith(401));
        assertThat(writer.entries.get(0).getStatus()).isEqualTo(ApiLogStatus.UNAUTHORIZED);

        filter.doFilter(new MockHttpServletRequest("GET", "/api/tenants"),
                new MockHttpServletResponse(), respondWith(403));
        assertThat(writer.entries.get(1).getStatus()).isEqualTo(ApiLogStatus.FORBIDDEN);
    }

    @Test
    void mapsPlainErrorStatusToFailed() throws Exception {
        filter.doFilter(new MockHttpServletRequest("GET", "/api/nope"),
                new MockHttpServletResponse(), respondWith(404));

        assertThat(writer.only().getStatus()).isEqualTo(ApiLogStatus.FAILED);
    }

    @Test
    void recordsExceptionDetailsWhenTheAdviceFiledThem() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/tenants/9");
        FilterChain chain = (req, res) -> {
            // Stands in for GlobalExceptionHandler: the advice handled it, so the filter only
            // sees a 404 and must learn the cause from the context.
            ApiLogContext.recordError((jakarta.servlet.http.HttpServletRequest) req,
                    "NotFoundException", "Tenant not found");
            ((jakarta.servlet.http.HttpServletResponse) res).setStatus(404);
        };

        filter.doFilter(request, new MockHttpServletResponse(), chain);

        ApiRequestLog entry = writer.only();
        assertThat(entry.getStatus()).isEqualTo(ApiLogStatus.EXCEPTION);
        assertThat(entry.getErrorCode()).isEqualTo("NotFoundException");
        assertThat(entry.getErrorMessage()).isEqualTo("Tenant not found");
    }

    @Test
    void logsThenRethrowsAnUnhandledException() {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/boom");
        FilterChain chain = (req, res) -> { throw new IllegalStateException("kaboom"); };

        // The original exception must reach the container untouched — the logger may never
        // change what the client receives.
        assertThatThrownBy(() -> filter.doFilter(request, new MockHttpServletResponse(), chain))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("kaboom");

        ApiRequestLog entry = writer.only();
        assertThat(entry.getStatus()).isEqualTo(ApiLogStatus.EXCEPTION);
        assertThat(entry.getErrorCode()).isEqualTo("IllegalStateException");
        assertThat(entry.getErrorMessage()).isEqualTo("kaboom");
    }

    @Test
    void skipsBodiesFarLargerThanTheBufferLimit() throws Exception {
        properties.setMaxPayloadChars(200);   // buffer limit becomes 800 bytes
        MockHttpServletRequest request = postJson("/api/notes", "{\"note\":\"" + "x".repeat(5_000) + "\"}");

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        // Well past the limit: never buffered, but the hit is still on record.
        assertThat(writer.only().getRequestBody()).isEqualTo(ApiLogRequestWrapper.OMITTED_TOO_LARGE);
    }

    @Test
    void skipsMultipartBodiesButStillLogsTheHit() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/super-admin/upload/tenants/1");
        request.setContentType("multipart/form-data; boundary=----x");
        request.setContent("pretend this is a 40 MB CSV".getBytes());

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        ApiRequestLog entry = writer.only();
        assertThat(entry.getRequestUri()).isEqualTo("/api/super-admin/upload/tenants/1");
        assertThat(entry.getRequestBody()).isEqualTo(ApiLogRequestWrapper.OMITTED_BINARY);
    }

    @Test
    void truncatesOversizedPayloadsWithinTheColumnBudget() throws Exception {
        properties.setMaxPayloadChars(200);   // buffer limit becomes 800 bytes
        // Over the 200-char cap but inside the 800-byte buffer limit: buffered, then truncated.
        MockHttpServletRequest request = postJson("/api/notes", "{\"note\":\"" + "x".repeat(500) + "\"}");

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        String body = writer.only().getRequestBody();
        // The marker has to fit inside the cap, not extend past it, or the insert fails.
        assertThat(body).hasSizeLessThanOrEqualTo(200);
        assertThat(body).endsWith("...[truncated]");
    }

    @Test
    void prefersTheFirstForwardedForHop() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/dashboard");
        request.addHeader("X-Forwarded-For", "203.0.113.7, 10.0.0.1, 10.0.0.2");

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        assertThat(writer.only().getClientIpAddress()).isEqualTo("203.0.113.7");
    }

    @Test
    void writesNothingWhenDisabled() throws Exception {
        properties.setEnabled(false);

        filter.doFilter(new MockHttpServletRequest("GET", "/api/dashboard"),
                new MockHttpServletResponse(), new MockFilterChain());

        assertThat(writer.entries).isEmpty();
    }

    @Test
    void storesRawPayloadWhenMaskingIsTurnedOff() throws Exception {
        properties.setMaskSensitiveData(false);
        MockHttpServletRequest request = postJson("/api/auth/login", "{\"password\":\"hunter2\"}");

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        assertThat(writer.only().getRequestBody()).contains("hunter2");
    }

    @Test
    void omitsBodiesWhenBodyCaptureIsTurnedOff() throws Exception {
        properties.setStoreRequestBody(false);
        properties.setStoreResponseBody(false);
        MockHttpServletRequest request = postJson("/api/tenants", "{\"fullName\":\"Asha\"}");

        filter.doFilter(request, new MockHttpServletResponse(), (req, res) -> res.getWriter().write("{}"));

        ApiRequestLog entry = writer.only();
        assertThat(entry.getRequestBody()).isNull();
        assertThat(entry.getResponseBody()).isNull();
        // The hit itself is still recorded — the switch controls payloads, not coverage.
        assertThat(entry.getRequestUri()).isEqualTo("/api/tenants");
    }

    @Test
    void neverCreatesAnHttpSession() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/dashboard");

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        // The app is STATELESS; a logger that quietly starts creating sessions would change that.
        assertThat(request.getSession(false)).isNull();
        assertThat(writer.only().getSessionId()).isNull();
    }
}
