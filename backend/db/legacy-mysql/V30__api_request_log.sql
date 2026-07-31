-- Centralised API request/response log. One row per incoming HTTP hit, written by
-- com.pgmanager.apilog.ApiLogFilter and purged after logging.api.retention-days by
-- ApiLogCleanupScheduler.
--
-- Column types must stay in step with the ApiRequestLog entity: ddl-auto is `validate`, so any
-- drift fails startup rather than silently misbehaving.
--
-- BIGINT AUTO_INCREMENT rather than a UUID primary key: this is the highest-insert-rate table in
-- the schema and InnoDB clusters on the PK, so a monotonic key appends to the rightmost page
-- instead of scattering writes (and splitting pages) across the whole index.

CREATE TABLE api_request_log (
    id                   BIGINT PRIMARY KEY AUTO_INCREMENT,

    -- Identity. All three are NULL for anonymous/rejected traffic, which is a meaningful value
    -- here (it is how you find unauthenticated probing), not a defect.
    organization_id      BIGINT       NULL,
    user_login_id        BIGINT       NULL,
    tenant_id            BIGINT       NULL,

    -- Correlation. request_id is the client's X-Request-Id when supplied, else a server UUID.
    request_id           VARCHAR(64)  NULL,
    session_id           VARCHAR(128) NULL,

    request_uri          VARCHAR(512) NOT NULL,
    http_method          VARCHAR(10)  NOT NULL,
    controller_name      VARCHAR(160) NULL,
    method_name          VARCHAR(120) NULL,

    -- Payloads are masked, then truncated to logging.api.max-payload-chars (default 8000), so
    -- TEXT (65,535 bytes) has ample headroom even for 4-byte utf8mb4 characters.
    request_body         TEXT         NULL,
    query_parameters     TEXT         NULL,
    request_headers      TEXT         NULL,

    response_status_code INT          NULL,
    response_body        TEXT         NULL,

    request_start_time   DATETIME(6)  NOT NULL,
    request_end_time     DATETIME(6)  NULL,
    execution_time_ms    BIGINT       NULL,

    -- Flutter device headers (App-Version, Build-Number, Platform, OS-Name, OS-Version,
    -- Device-Model, Manufacturer).
    platform             VARCHAR(40)  NULL,
    app_version          VARCHAR(40)  NULL,
    build_number         VARCHAR(40)  NULL,
    device_model         VARCHAR(120) NULL,
    manufacturer         VARCHAR(80)  NULL,
    os_name              VARCHAR(40)  NULL,
    os_version           VARCHAR(40)  NULL,

    -- 64 chars covers IPv6; only the first X-Forwarded-For hop is stored.
    client_ip_address    VARCHAR(64)  NULL,
    network_type         VARCHAR(40)  NULL,
    user_agent           VARCHAR(512) NULL,

    -- SUCCESS | FAILED | EXCEPTION | UNAUTHORIZED | FORBIDDEN | TIMEOUT.
    -- Stored as a string, not an ordinal, so adding a value cannot reinterpret old rows.
    status               VARCHAR(20)  NOT NULL,
    error_code           VARCHAR(120) NULL,
    error_message        VARCHAR(1000) NULL,

    created_date         DATETIME(6)  NOT NULL
);

-- Deliberately no foreign keys to facility/user_login. This table is append-only diagnostic data
-- written on every request, including for principals that may later be deleted; an FK would add a
-- lock and a lookup to the hottest insert path and could block a legitimate delete elsewhere.

-- Retention sweep and every time-bounded query. This is the one index that must exist.
CREATE INDEX idx_arl_created_date ON api_request_log (created_date);

-- Composite, not single-column, for the two dimensions that are always sliced by time as well
-- ("this org's traffic yesterday", "what did this user do this morning"). A lone organization_id
-- index would be near-useless: low cardinality, and the planner would still filter the date range
-- row by row.
CREATE INDEX idx_arl_org_created  ON api_request_log (organization_id, created_date);
CREATE INDEX idx_arl_user_created ON api_request_log (user_login_id, created_date);

-- Endpoint-level analysis: slowest/most-hit URIs.
CREATE INDEX idx_arl_request_uri ON api_request_log (request_uri);

-- Error triage. Both are low cardinality, so they only earn their keep combined with the date —
-- kept single-column here because the spec asks for them, and they are still selective for the
-- rare values (EXCEPTION, 500) that anyone actually searches for.
CREATE INDEX idx_arl_status               ON api_request_log (status);
CREATE INDEX idx_arl_response_status_code ON api_request_log (response_status_code);

-- "Is the crash only on build 42?" — release-adoption and per-version failure rates.
CREATE INDEX idx_arl_app_version ON api_request_log (app_version);

-- Support flow: user reports a failure, quotes the X-Request-Id from the response header.
CREATE INDEX idx_arl_request_id ON api_request_log (request_id);
