package com.pgmanager.apilog;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Redacts secrets out of payloads, headers and query strings before anything is persisted.
 *
 * <p>Matching is <b>key-based and naming-agnostic</b>: a key is normalised by lowercasing and
 * dropping every non-alphanumeric character, so {@code confirmPassword},
 * {@code confirm_password}, {@code Confirm-Password} and {@code CONFIRMPASSWORD} all collapse
 * to {@code confirmpassword} and all match. This beats a regex-per-field list, which silently
 * misses the casing variant nobody thought of.
 *
 * <p>Value-pattern matching is deliberately <b>not</b> used for the numeric fields
 * ({@code creditCardNumber}, {@code aadhaarNumber}): a "12+ digit run" rule would also redact
 * invoice totals, mobile numbers and ids, making the logs useless for the debugging they exist
 * for. Bearer tokens in free text are the one exception — they are unambiguous.
 *
 * <p>Stateless and therefore thread-safe; a single bean is shared by every request thread.
 */
@Component
public class SensitiveDataMasker {

    public static final String MASK = "***MASKED***";

    /** Already normalised (lowercase, alphanumeric only). Add new secrets here only. */
    private static final Set<String> SENSITIVE_KEYS = Set.of(
            "password",
            "confirmpassword",
            "currentpassword",
            "newpassword",
            "oldpassword",
            "passwordhash",
            "otp",
            "authorization",
            "accesstoken",
            "refreshtoken",
            "token",
            "upipin",
            "pin",
            "cvv",
            "creditcardnumber",
            "cardnumber",
            "aadhaarnumber",
            "aadhaar",
            "cookie",
            "setcookie",
            "secret",
            "clientsecret",
            "apikey",
            "jwtsecret"
    );

    /** Key fragments used by the text-mode fallback patterns below. */
    private static final String SECRET_KEY_FRAGMENT =
            "[A-Za-z0-9_\\-]*(?:password|token|otp|secret|cvv|pin|aadhaar|cardnumber|authorization)[A-Za-z0-9_\\-]*";

    /**
     * Quoted JSON pair — {@code "password":"hunter2"}. Needed for the malformed-JSON path: a
     * truncated body still looks like JSON, so the unquoted pattern below never matches it
     * (the character after the key is {@code "}, not {@code :}) and the secret would survive.
     */
    private static final Pattern JSON_KEY_VALUE = Pattern.compile(
            "(?i)(\"" + SECRET_KEY_FRAGMENT + "\"\\s*:\\s*)(\"[^\"]*\"|[^,}\\s]+)");

    /**
     * Unquoted pair — {@code password=hunter2}, {@code otp: 123456}, {@code Authorization: Bearer x}.
     * The value class allows spaces so a whole {@code Bearer <token>} is consumed as one value,
     * and stops at {@code & , ; " }} and newline so it cannot run past the end of one field.
     */
    private static final Pattern KEY_VALUE = Pattern.compile(
            "(?i)(" + SECRET_KEY_FRAGMENT + ")(\\s*[=:]\\s*)([^&,;\\n\"}]+)");

    /**
     * A bare {@code Bearer eyJ...} with no key in front of it — a token pasted into a log line or
     * a stack trace. Applied <em>after</em> {@link #KEY_VALUE}, so a keyed header is already
     * reduced to {@code Authorization: ***MASKED***} and is not masked twice.
     */
    private static final Pattern BEARER = Pattern.compile("(?i)(bearer\\s+)[A-Za-z0-9._\\-+/=]{8,}");

    private final ObjectMapper objectMapper;

    public SensitiveDataMasker(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    /** True when this key names a secret, under any casing or separator convention. */
    public boolean isSensitive(String key) {
        return key != null && SENSITIVE_KEYS.contains(normalise(key));
    }

    private static String normalise(String key) {
        StringBuilder out = new StringBuilder(key.length());
        for (int i = 0; i < key.length(); i++) {
            char c = key.charAt(i);
            if (Character.isLetterOrDigit(c)) out.append(Character.toLowerCase(c));
        }
        return out.toString();
    }

    /**
     * Masks a request or response payload. JSON is masked <b>structurally</b> (parse, walk,
     * re-serialise) so the stored row stays valid JSON and stays queryable; anything that does
     * not parse falls back to regex redaction, which is lossier but never leaks a known key.
     */
    public String maskPayload(String payload) {
        if (payload == null || payload.isBlank()) return payload;
        String trimmed = payload.stripLeading();
        if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
            try {
                JsonNode masked = maskNode(objectMapper.readTree(payload));
                return objectMapper.writeValueAsString(masked);
            } catch (Exception ignored) {
                // Malformed or truncated JSON — fall through to the text path rather than
                // storing it unmasked.
            }
        }
        return maskText(payload);
    }

    /** Recursively replaces the value of every sensitive key, preserving structure. */
    private JsonNode maskNode(JsonNode node) {
        if (node instanceof ObjectNode object) {
            object.fieldNames().forEachRemaining(field -> {
                if (isSensitive(field)) {
                    object.put(field, MASK);
                } else {
                    maskNode(object.get(field));
                }
            });
        } else if (node instanceof ArrayNode array) {
            array.forEach(this::maskNode);
        }
        return node;
    }

    /**
     * Regex fallback for anything the structural masker cannot parse: form bodies, query strings,
     * truncated JSON, stack-trace-ish blobs.
     *
     * <p>Order is load-bearing. Keyed pairs go first so {@code Authorization: Bearer <token>}
     * collapses to one mask; running the bare-token pattern first would leave the key pattern to
     * mask the literal word "Bearer" and produce a double mask.
     */
    public String maskText(String text) {
        if (text == null || text.isBlank()) return text;
        String masked = JSON_KEY_VALUE.matcher(text).replaceAll(match ->
                Matcher.quoteReplacement(match.group(1) + "\"" + MASK + "\""));
        masked = KEY_VALUE.matcher(masked).replaceAll(match ->
                Matcher.quoteReplacement(match.group(1) + match.group(2) + MASK));
        return BEARER.matcher(masked).replaceAll(match -> Matcher.quoteReplacement(match.group(1)) + MASK);
    }

    /** Masks header values by header name. {@code Authorization} and {@code Cookie} always go. */
    public Map<String, String> maskHeaders(Map<String, String> headers) {
        Map<String, String> masked = new LinkedHashMap<>(headers.size());
        headers.forEach((name, value) -> masked.put(name, isSensitive(name) ? MASK : value));
        return masked;
    }

    /** Masks a raw query string ({@code a=1&password=x}) by parameter name. */
    public String maskQueryString(String queryString) {
        if (queryString == null || queryString.isBlank()) return queryString;
        String[] pairs = queryString.split("&");
        StringBuilder out = new StringBuilder(queryString.length());
        for (int i = 0; i < pairs.length; i++) {
            if (i > 0) out.append('&');
            int eq = pairs[i].indexOf('=');
            if (eq <= 0) {
                out.append(pairs[i]);
                continue;
            }
            String name = pairs[i].substring(0, eq);
            out.append(name).append('=').append(isSensitive(name) ? MASK : pairs[i].substring(eq + 1));
        }
        return out.toString();
    }
}
