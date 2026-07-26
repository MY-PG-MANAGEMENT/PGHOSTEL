-- Platform billing rate: what the PG Manager operator charges an organization per active
-- tenant per month. Backs the super-admin Active Tenants report and the per-org pricing
-- editor in Admin -> System Settings.
--
-- Two levels, matching how organization_billing_config (V26) already works: a global default
-- lives in system_setting, and this table holds per-org overrides only. A missing row means
-- "use the default", so onboarding a new org needs no backfill and the common case costs no
-- writes at all.
--
-- Read/written via OrganizationTenantRateService (JdbcTemplate, not a JPA entity - so
-- ddl-auto=validate does not track it), consistent with BillingConfigService and
-- TenantArchiveService.

CREATE TABLE organization_tenant_rate (
    organization_tenant_rate_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id             BIGINT        NOT NULL,
    -- Per active tenant, per month. DECIMAL not DOUBLE: this multiplies into an invoice
    -- figure, and binary floating point would drift on the totals.
    price_per_tenant            DECIMAL(10,2) NOT NULL,
    updated_by_user_login_id    BIGINT        NULL,
    created_at                  DATETIME(6)   NOT NULL,
    updated_at                  DATETIME(6)   NOT NULL,
    -- One live rate per org: the upsert depends on this, and two rows would make the report
    -- silently non-deterministic.
    UNIQUE KEY uk_otr_organization (organization_id),
    CONSTRAINT fk_otr_organization FOREIGN KEY (organization_id) REFERENCES facility (facility_id)
);

-- The fallback rate, and the thing an admin edits first. Seeded at 15.00 as requested.
-- It appears automatically in the existing System Settings list because that screen renders
-- every system_setting row.
INSERT INTO system_setting (setting_key, setting_value, encrypted, updated_at)
VALUES ('platform.price_per_active_tenant', '15.00', FALSE, NOW(6))
ON DUPLICATE KEY UPDATE setting_key = setting_key;
