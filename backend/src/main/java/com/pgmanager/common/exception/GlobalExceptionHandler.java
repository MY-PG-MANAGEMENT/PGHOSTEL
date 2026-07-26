package com.pgmanager.common.exception;

import com.pgmanager.apilog.ApiLogContext;
import com.pgmanager.common.api.ApiResponse;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

import java.util.stream.Collectors;

@RestControllerAdvice
public class GlobalExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private static String path(HttpServletRequest req) {
        return req == null ? "?" : req.getMethod() + " " + req.getRequestURI();
    }

    /**
     * Files the exception against this request's API log row.
     *
     * <p>This hook is why the advice is involved at all. Once a handler here has converted an
     * exception into a {@code ResponseEntity}, the exception is gone — the logging filter sees
     * only a 400 or a 500 and cannot tell a thrown {@code BadRequestException} from a controller
     * that simply chose to return 400. Recording it here is what populates {@code errorCode} /
     * {@code errorMessage} and marks the row {@code EXCEPTION}.
     *
     * <p>The error code is the exception's simple class name: stable, greppable, and it needs no
     * error-code registry to be invented and then kept in sync. It is a no-op when API logging is
     * disabled, so nothing here is conditional.
     */
    private static void record(HttpServletRequest req, Exception ex, String message) {
        ApiLogContext.recordError(req, ex.getClass().getSimpleName(), message);
    }

    @ExceptionHandler(BadRequestException.class)
    ResponseEntity<ApiResponse<Void>> badRequest(BadRequestException ex, HttpServletRequest req) {
        log.warn("400 Bad Request [{}]: {}", path(req), ex.getMessage());
        record(req, ex, ex.getMessage());
        return ResponseEntity.badRequest().body(ApiResponse.error(ex.getMessage()));
    }

    @ExceptionHandler(NotFoundException.class)
    ResponseEntity<ApiResponse<Void>> notFound(NotFoundException ex, HttpServletRequest req) {
        log.warn("404 Not Found [{}]: {}", path(req), ex.getMessage());
        record(req, ex, ex.getMessage());
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(ApiResponse.error(ex.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ApiResponse<Void>> validation(MethodArgumentNotValidException ex, HttpServletRequest req) {
        String message = ex.getBindingResult().getFieldErrors().stream()
                .map(error -> error.getField() + ": " + error.getDefaultMessage())
                .collect(Collectors.joining(", "));
        log.warn("400 Validation failed [{}]: {}", path(req), message);
        record(req, ex, message);
        return ResponseEntity.badRequest().body(ApiResponse.error(message));
    }

    @ExceptionHandler(AccessDeniedException.class)
    ResponseEntity<ApiResponse<Void>> accessDenied(AccessDeniedException ex, HttpServletRequest req) {
        log.warn("403 Access denied [{}]: {}", path(req), ex.getMessage());
        record(req, ex, ex.getMessage());
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(ApiResponse.error("Access denied"));
    }

    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<ApiResponse<Void>> responseStatus(ResponseStatusException ex, HttpServletRequest req) {
        String message = ex.getReason() != null ? ex.getReason() : "Request failed";
        log.warn("{} [{}]: {}", ex.getStatusCode(), path(req), message);
        record(req, ex, message);
        return ResponseEntity.status(ex.getStatusCode()).body(ApiResponse.error(message));
    }

    /** Catch-all so unexpected server errors are logged with a full stacktrace instead of vanishing. */
    @ExceptionHandler(Exception.class)
    ResponseEntity<ApiResponse<Void>> unexpected(Exception ex, HttpServletRequest req) {
        log.error("500 Unhandled exception [{}]: {}", path(req), ex.getMessage(), ex);
        // The client still gets the generic message; the log row keeps the real cause.
        record(req, ex, ex.getMessage());
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiResponse.error("Something went wrong. Please try again."));
    }
}
