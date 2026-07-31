-- Per-organization billing / invoice-automation configuration.
--
-- Backs the daily auto-invoice scheduler: `invoice_lead_days` is how many days
-- BEFORE a tenant's billing anniversary (their move-in day-of-month) the monthly
-- invoice is raised, and `auto_generate_enabled` lets an org opt out of automation
-- (the manual POST /api/billing/generate-invoices fallback always works regardless).
--
-- A missing row means "use defaults" (lead days = 1, auto-generate ON), so existing
-- organizations are automated by default without a backfill. Read/written via
-- JdbcTemplate (BillingConfigService) — deliberately not mapped to a JPA @Entity, so
-- `ddl-auto: validate` does not track it (matches the billing package's JDBC style).
CREATE TABLE organization_billing_config (
    organization_billing_config_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id       BIGINT       NOT NULL,
    invoice_lead_days     INT          NOT NULL DEFAULT 1,
    auto_generate_enabled TINYINT(1)   NOT NULL DEFAULT 1,
    created_at            DATETIME(6)  NOT NULL,
    updated_at            DATETIME(6)  NOT NULL,
    UNIQUE KEY uk_org_billing_config (organization_id),
    CONSTRAINT fk_org_billing_config_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id)
);
