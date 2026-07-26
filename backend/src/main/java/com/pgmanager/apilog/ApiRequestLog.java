package com.pgmanager.apilog;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;

/**
 * One row per API hit.
 *
 * <p><b>Auto-increment BIGINT, not UUID.</b> This is the highest-insert-rate table in the
 * schema. InnoDB clusters rows on the primary key, so a monotonic key appends to the rightmost
 * page; a random UUID scatters inserts across the whole index, causing page splits, a much
 * larger index, and a worse buffer-pool hit rate. UUID would only pay off if rows had to be
 * generated across shards before insert, which they do not.
 *
 * <p><b>Deliberately does not extend {@code BaseEntity}.</b> Log rows are append-only and are
 * never updated, so the inherited {@code updated_at} would be dead weight on every insert. The
 * spec's single {@code createdDate} is the whole audit story here.
 *
 * <p>The {@code @Index} declarations are documentation only — {@code ddl-auto} is
 * {@code validate}, so the real indexes are created by {@code V30__api_request_log.sql} and
 * must be kept in step with this list.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@lombok.AllArgsConstructor
@Entity
@Table(name = "api_request_log", indexes = {
        @Index(name = "idx_arl_created_date", columnList = "created_date"),
        @Index(name = "idx_arl_org_created", columnList = "organization_id,created_date"),
        @Index(name = "idx_arl_user_created", columnList = "user_login_id,created_date"),
        @Index(name = "idx_arl_request_uri", columnList = "request_uri"),
        @Index(name = "idx_arl_status", columnList = "status"),
        @Index(name = "idx_arl_response_status_code", columnList = "response_status_code"),
        @Index(name = "idx_arl_app_version", columnList = "app_version"),
        @Index(name = "idx_arl_request_id", columnList = "request_id")
})
public class ApiRequestLog {

    // ─── Primary key ──────────────────────────────────────────────────────────
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    // ─── User information (all null for an anonymous hit) ─────────────────────
    @Column(name = "organization_id")
    private Long organizationId;

    @Column(name = "user_login_id")
    private Long userLoginId;

    /**
     * The resident's {@code party_id}. In this schema a "tenant" is a person occupying a bed,
     * so this is only populated for a TENANT-role login (where the JWT's {@code partyId} *is*
     * the tenant); it stays null for owner/staff and anonymous traffic.
     */
    @Column(name = "tenant_id")
    private Long tenantId;

    // ─── Request identification ───────────────────────────────────────────────
    /** Client-supplied {@code X-Request-Id}, else a server-generated UUID. Never null. */
    @Column(name = "request_id", length = 64)
    private String requestId;

    /** Usually null — the app is {@code STATELESS}, so no HTTP session is ever created. */
    @Column(name = "session_id", length = 128)
    private String sessionId;

    // ─── API information ──────────────────────────────────────────────────────
    @Column(name = "request_uri", nullable = false, length = 512)
    private String requestUri;

    @Column(name = "http_method", nullable = false, length = 10)
    private String httpMethod;

    /** Null when no handler was matched (404) or the security chain rejected the call first. */
    @Column(name = "controller_name", length = 160)
    private String controllerName;

    @Column(name = "method_name", length = 120)
    private String methodName;

    // ─── Request payload (masked, then truncated) ──────────────────────────────
    @Column(name = "request_body", columnDefinition = "TEXT")
    private String requestBody;

    @Column(name = "query_parameters", columnDefinition = "TEXT")
    private String queryParameters;

    @Column(name = "request_headers", columnDefinition = "TEXT")
    private String requestHeaders;

    // ─── Response ─────────────────────────────────────────────────────────────
    @Column(name = "response_status_code")
    private Integer responseStatusCode;

    @Column(name = "response_body", columnDefinition = "TEXT")
    private String responseBody;

    // ─── Performance ──────────────────────────────────────────────────────────
    @Column(name = "request_start_time", nullable = false)
    private LocalDateTime requestStartTime;

    @Column(name = "request_end_time")
    private LocalDateTime requestEndTime;

    /**
     * Measured with {@code System.nanoTime()} rather than by subtracting the two timestamps
     * above: those come from the wall clock, which NTP can step backwards mid-request.
     */
    @Column(name = "execution_time_ms")
    private Long executionTimeMs;

    // ─── Device information (Flutter headers) ─────────────────────────────────
    @Column(name = "platform", length = 40)
    private String platform;

    @Column(name = "app_version", length = 40)
    private String appVersion;

    @Column(name = "build_number", length = 40)
    private String buildNumber;

    @Column(name = "device_model", length = 120)
    private String deviceModel;

    @Column(name = "manufacturer", length = 80)
    private String manufacturer;

    @Column(name = "os_name", length = 40)
    private String osName;

    @Column(name = "os_version", length = 40)
    private String osVersion;

    // ─── Network ──────────────────────────────────────────────────────────────
    @Column(name = "client_ip_address", length = 64)
    private String clientIpAddress;

    @Column(name = "network_type", length = 40)
    private String networkType;

    @Column(name = "user_agent", length = 512)
    private String userAgent;

    // ─── Result ───────────────────────────────────────────────────────────────
    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    private ApiLogStatus status;

    @Column(name = "error_code", length = 120)
    private String errorCode;

    @Column(name = "error_message", length = 1000)
    private String errorMessage;

    // ─── Audit ────────────────────────────────────────────────────────────────
    @Column(name = "created_date", nullable = false)
    private LocalDateTime createdDate;
}
