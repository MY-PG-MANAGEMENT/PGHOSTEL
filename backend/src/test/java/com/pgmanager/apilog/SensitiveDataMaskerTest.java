package com.pgmanager.apilog;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The masker is the one component whose failure is a security incident rather than a missing log
 * row, so it carries the heaviest test coverage.
 */
class SensitiveDataMaskerTest {

    private final SensitiveDataMasker masker = new SensitiveDataMasker(new ObjectMapper());

    @Test
    void masksSensitiveJsonFieldsAndKeepsTheRest() {
        String json = """
                {"username":"owner@pg.com","password":"hunter2","otp":"123456","rent":8500}""";

        String masked = masker.maskPayload(json);

        assertThat(masked).contains("\"password\":\"***MASKED***\"");
        assertThat(masked).contains("\"otp\":\"***MASKED***\"");
        assertThat(masked).doesNotContain("hunter2").doesNotContain("123456");
        // The non-sensitive fields are what make the log useful; they must survive intact.
        assertThat(masked).contains("owner@pg.com").contains("8500");
    }

    @Test
    void masksAcrossEveryNamingConvention() {
        String json = """
                {"confirmPassword":"a","confirm_password":"b","Confirm-Password":"c","UPI_PIN":"d"}""";

        String masked = masker.maskPayload(json);

        assertThat(masked).doesNotContain("\"a\"").doesNotContain("\"b\"")
                .doesNotContain("\"c\"").doesNotContain("\"d\"");
    }

    @Test
    void masksNestedObjectsAndArrays() {
        String json = """
                {"user":{"cvv":"999","card":{"creditCardNumber":"4111111111111111"}},
                 "payments":[{"upiPin":"1234"},{"amount":500}]}""";

        String masked = masker.maskPayload(json);

        assertThat(masked).doesNotContain("999")
                .doesNotContain("4111111111111111")
                .doesNotContain("1234");
        assertThat(masked).contains("500");
    }

    @Test
    void preservesJsonStructureSoRowsStayQueryable() throws Exception {
        String masked = masker.maskPayload("""
                {"aadhaarNumber":"123412341234","name":"Asha"}""");

        // Re-parsing is the assertion: a regex-only masker would mangle the document.
        var tree = new ObjectMapper().readTree(masked);
        assertThat(tree.get("aadhaarNumber").asText()).isEqualTo(SensitiveDataMasker.MASK);
        assertThat(tree.get("name").asText()).isEqualTo("Asha");
    }

    @Test
    void fallsBackToTextMaskingForMalformedJson() {
        // A truncated body must not slip through unmasked just because it will not parse.
        String masked = masker.maskPayload("{\"password\":\"hunter2\", \"trunc");

        assertThat(masked).doesNotContain("hunter2");
    }

    @Test
    void masksAKeyedAuthorizationValueWholesale() {
        String masked = masker.maskText("Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abc.def");

        // The scheme word goes with the token — one mask, not "Bearer ***MASKED*** ***MASKED***".
        assertThat(masked).isEqualTo("Authorization: ***MASKED***");
    }

    @Test
    void masksABareBearerTokenWithNoKeyInFrontOfIt() {
        String masked = masker.maskText("request failed for Bearer eyJhbGciOiJIUzI1NiJ9.abc.def");

        assertThat(masked).doesNotContain("eyJhbGciOiJIUzI1NiJ9");
        assertThat(masked).isEqualTo("request failed for Bearer ***MASKED***");
    }

    @Test
    void masksHeadersByName() {
        Map<String, String> headers = new LinkedHashMap<>();
        headers.put("Authorization", "Bearer secret-token");
        headers.put("Cookie", "session=abc");
        headers.put("App-Version", "1.4.2");

        Map<String, String> masked = masker.maskHeaders(headers);

        assertThat(masked.get("Authorization")).isEqualTo(SensitiveDataMasker.MASK);
        assertThat(masked.get("Cookie")).isEqualTo(SensitiveDataMasker.MASK);
        // Device headers are the whole point of capturing headers — they must not be masked.
        assertThat(masked.get("App-Version")).isEqualTo("1.4.2");
    }

    @Test
    void masksQueryParametersByName() {
        String masked = masker.maskQueryString("propertyId=12&otp=998877&month=2026-07");

        assertThat(masked).isEqualTo("propertyId=12&otp=***MASKED***&month=2026-07");
    }

    @Test
    void leavesNonSensitiveNumbersAlone() {
        // Guards against the tempting "mask any long digit run" rule, which would redact
        // mobile numbers, ids and amounts and make the logs useless.
        String masked = masker.maskPayload("""
                {"mobileNumber":"9876543210","amount":1250000,"invoiceId":880123}""");

        assertThat(masked).contains("9876543210").contains("1250000").contains("880123");
    }

    @Test
    void handlesNullAndBlankSafely() {
        assertThat(masker.maskPayload(null)).isNull();
        assertThat(masker.maskPayload("")).isEmpty();
        assertThat(masker.maskQueryString(null)).isNull();
        assertThat(masker.maskText(null)).isNull();
    }

    @Test
    void isSensitiveIsNullSafe() {
        assertThat(masker.isSensitive(null)).isFalse();
        assertThat(masker.isSensitive("password")).isTrue();
        assertThat(masker.isSensitive("propertyId")).isFalse();
    }
}
