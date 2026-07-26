package com.pgmanager.apilog;

import jakarta.servlet.http.HttpServletResponse;
import org.springframework.web.util.ContentCachingResponseWrapper;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;

/**
 * Wraps the response so the outgoing body can be logged and still reach the client.
 *
 * <p><b>The one rule that must never be broken:</b> {@link #copyBodyToResponse()} has to be
 * called before the filter returns. {@code ContentCachingResponseWrapper} buffers everything the
 * application writes instead of passing it through, so skipping the copy ships an empty body to
 * every caller — the classic way this pattern breaks an entire API in production. The filter
 * calls it from a {@code finally}, so even an exception on the way out cannot lose it.
 *
 * <p>Body capture is content-type gated for the same reason as the request side: this app
 * streams generated HTML (tenant self check-in) and can return non-text payloads, and buffering
 * a large binary response to store an unreadable blob is pure cost.
 */
public class ApiLogResponseWrapper extends ContentCachingResponseWrapper {

    private final ApiLogProperties properties;

    ApiLogResponseWrapper(HttpServletResponse response, ApiLogProperties properties) {
        super(response);
        this.properties = properties;
    }

    /** The captured body as text, a placeholder for non-text content, or null if empty. */
    String bodyAsText() {
        if (!ApiLogRequestWrapper.isLoggableContentType(getContentType(), properties)) {
            return ApiLogRequestWrapper.OMITTED_BINARY;
        }
        byte[] bytes = getContentAsByteArray();
        if (bytes.length == 0) return null;
        // Cap the decode itself: a 50 MB export should not become a 50 MB String on the way to
        // being truncated to 8 KB.
        int limit = (int) Math.min(bytes.length, properties.maxBufferedBytes());
        return new String(bytes, 0, limit, charset());
    }

    private Charset charset() {
        String encoding = getCharacterEncoding();
        if (encoding == null) return StandardCharsets.UTF_8;
        try {
            return Charset.forName(encoding);
        } catch (Exception ignored) {
            return StandardCharsets.UTF_8;
        }
    }
}
