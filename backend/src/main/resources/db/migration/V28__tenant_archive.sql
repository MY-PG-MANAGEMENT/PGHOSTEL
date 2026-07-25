-- V28: tenant archive — the owner-facing "Delete tenant" that never loses data.
--
-- Orgs accumulate a very long Inactive tenant list (everyone who ever left), but the
-- rows must be kept because tenants routinely rejoin a month or two later and their
-- invoice / payment history has to survive. So "delete" in the app is an ARCHIVE:
-- nothing is removed from party / person / facility_party / invoice / payment — a row
-- is written here and the tenant is filtered out of the tenant lists.
--
-- Shape is org → property → tenant, as the owner thinks about it: `property_facility_id`
-- is the tenant's last known property (their property-level TENANT membership, else the
-- property of their most recent bed), NULL when they were never scoped to one. It has no
-- FK because a property can be removed while its archived tenants remain.
--
-- `full_name` / `mobile_number` are a display snapshot so the archived list renders
-- without depending on `person` rows staying untouched.
--
-- Exactly ONE live row per party (uk_tenant_archive_party): restoring DELETES the row
-- rather than flagging it, which keeps the "is this tenant hidden?" test a plain
-- existence check. The archive/restore history lives in audit_log
-- (TENANT_ARCHIVED / TENANT_RESTORED).
--
-- Read/written via JdbcTemplate (TenantArchiveService) — deliberately not a JPA @Entity,
-- so `ddl-auto: validate` does not track it (same call as organization_billing_config).
CREATE TABLE tenant_archive (
    tenant_archive_id         BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id           BIGINT       NOT NULL,
    property_facility_id      BIGINT       NULL,
    party_id                  BIGINT       NOT NULL,
    full_name                 VARCHAR(150) NULL,
    mobile_number             VARCHAR(20)  NULL,
    archived_at               DATETIME(6)  NOT NULL,
    archived_by_user_login_id BIGINT       NULL,
    created_at                DATETIME(6)  NOT NULL,
    updated_at                DATETIME(6)  NOT NULL,
    UNIQUE KEY uk_tenant_archive_party (party_id),
    INDEX idx_tenant_archive_org_property (organization_id, property_facility_id),
    CONSTRAINT fk_tenant_archive_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_tenant_archive_party FOREIGN KEY (party_id) REFERENCES party (party_id)
);
