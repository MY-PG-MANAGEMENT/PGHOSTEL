package com.pgmanager.apilog;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.util.StreamUtils;
import org.springframework.web.util.ContentCachingRequestWrapper;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;

/**
 * Wraps the request so its body can be read twice — once by the controller, once by the logger.
 *
 * <p>Built on Spring's {@link ContentCachingRequestWrapper} rather than a hand-rolled wrapper:
 * getting {@code getInputStream}/{@code getReader}/{@code getParameter} mutually consistent is
 * subtle, and Spring's version is the battle-tested one. What it does <em>not</em> do is decide
 * <em>whether</em> to buffer, which is the part that matters in production — that is this
 * subclass.
 *
 * <p><b>The multipart problem.</b> This codebase has CSV bulk-upload endpoints
 * ({@code /api/super-admin/upload/**}). Caching those would pull an entire uploaded file into
 * heap on top of the copy Spring already makes, for a body that is unreadable as a log entry
 * anyway. So a body is buffered only when the content type is text-ish and the declared length
 * fits the cap. The hit is still logged either way — only the payload is swapped for a
 * placeholder, which honours "log every request" without the memory blowup.
 */
public class ApiLogRequestWrapper extends ContentCachingRequestWrapper {

    static final String OMITTED_BINARY = "[body not logged: binary or multipart content]";
    static final String OMITTED_TOO_LARGE = "[body not logged: exceeds configured max size]";

    private final boolean bodyCaptured;
    private final String skipReason;

    ApiLogRequestWrapper(HttpServletRequest request, ApiLogProperties properties) {
        // contentCacheLimit bounds what Spring retains, so a chunked or under-declared body
        // cannot grow past the ceiling either — Content-Length alone is not trustworthy.
        super(request, (int) properties.maxBufferedBytes());
        String contentType = request.getContentType();
        if (!isLoggableContentType(contentType, properties)) {
            this.bodyCaptured = false;
            this.skipReason = OMITTED_BINARY;
        } else if (request.getContentLengthLong() > properties.maxBufferedBytes()) {
            // Far past the cap: skip entirely rather than pull it into heap to throw most away.
            this.bodyCaptured = false;
            this.skipReason = OMITTED_TOO_LARGE;
        } else {
            this.bodyCaptured = true;
            this.skipReason = null;
        }
    }

    static boolean isLoggableContentType(String contentType, ApiLogProperties properties) {
        if (contentType == null || contentType.isBlank()) {
            // No body declared (typical GET/DELETE). Nothing to skip.
            return true;
        }
        String lower = contentType.toLowerCase();
        return properties.getLoggableContentTypes().stream()
                .anyMatch(allowed -> lower.startsWith(allowed.toLowerCase()));
    }

    /**
     * The buffered body as text, or a placeholder explaining why it was skipped.
     *
     * <p>Must be called <b>after</b> the filter chain has run: {@code ContentCachingRequestWrapper}
     * fills its buffer as the application reads the stream, so calling this first returns empty.
     */
    String bodyAsText() {
        if (!bodyCaptured) return skipReason;
        byte[] bytes = getContentAsByteArray();
        if (bytes.length == 0) {
            // The handler never read the body — drain what is left so a payload sent to an
            // endpoint that ignores it is still logged rather than silently lost.
            try {
                bytes = StreamUtils.copyToByteArray(getInputStream());
            } catch (Exception ignored) {
                return null;
            }
        }
        return bytes.length == 0 ? null : new String(bytes, charset());
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
