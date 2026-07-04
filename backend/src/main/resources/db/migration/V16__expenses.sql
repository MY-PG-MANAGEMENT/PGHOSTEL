-- V16: Expense tracking (expenses dashboard)
--
-- Deliberately minimal — three tables only. Things we do NOT create tables for:
--   * expense categories  -> VARCHAR constants in code (same pattern as
--                            FacilityType / OccupancyRole): FOOD, SALARY,
--                            ELECTRICITY, MAINTENANCE, LAUNDRY, TRANSPORT,
--                            RENT, OTHERS
--   * vendors             -> optional vendor_party_id FK reusing the existing
--                            party model, or a plain vendor_name text column;
--                            no separate vendor master table
--   * approvals           -> status/approved_by/approved_at columns on the
--                            expense row itself; no approval workflow table
--   * monthly summaries, category breakdowns, trends, budget utilization,
--     AI insights          -> all derived by aggregate queries over `expense`
--                            (JdbcTemplate, same pattern as BillingController)

-- One row per expense. Property scope is optional (NULL = org-level expense).
CREATE TABLE expense (
    expense_id           BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id      BIGINT        NOT NULL,
    property_facility_id BIGINT        NULL,
    category             VARCHAR(30)   NOT NULL,
    title                VARCHAR(120)  NOT NULL,
    description          VARCHAR(500),
    amount               DECIMAL(12,2) NOT NULL,
    expense_date         DATE          NOT NULL,
    payment_method       VARCHAR(20)   NOT NULL DEFAULT 'CASH',  -- CASH | UPI | CARD | BANK_TRANSFER
    vendor_party_id      BIGINT        NULL,                      -- optional link to party
    vendor_name          VARCHAR(120),                            -- free-text fallback
    status               VARCHAR(20)   NOT NULL DEFAULT 'PENDING',-- PENDING | APPROVED | REJECTED | PAID
    approved_by          BIGINT        NULL,                      -- user_login_id
    approved_at          DATETIME      NULL,
    created_by           BIGINT        NULL,                      -- user_login_id
    created_at           DATETIME      NOT NULL,
    updated_at           DATETIME      NOT NULL,
    KEY idx_expense_org_date (organization_id, expense_date),
    KEY idx_expense_prop_date (property_facility_id, expense_date),
    KEY idx_expense_org_status (organization_id, status),
    KEY idx_expense_org_cat (organization_id, category, expense_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Monthly budget per scope. Sentinels keep the unique key enforceable in MySQL
-- (unique indexes ignore NULLs): property_facility_id = 0 means "whole org",
-- category = 'ALL' means "overall monthly budget" (the summary-card number).
CREATE TABLE expense_budget (
    expense_budget_id    BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id      BIGINT        NOT NULL,
    property_facility_id BIGINT        NOT NULL DEFAULT 0,
    category             VARCHAR(30)   NOT NULL DEFAULT 'ALL',
    budget_month         CHAR(7)       NOT NULL,                  -- 'YYYY-MM'
    amount               DECIMAL(12,2) NOT NULL,
    created_at           DATETIME      NOT NULL,
    updated_at           DATETIME      NOT NULL,
    UNIQUE KEY uk_budget_scope (organization_id, property_facility_id, category, budget_month)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Petty-cash ledger. OUT rows are written automatically when a CASH expense is
-- approved (expense_id set); IN rows are manual top-ups. Opening/closing
-- balances are computed (running sum), never stored.
CREATE TABLE petty_cash_entry (
    petty_cash_entry_id  BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id      BIGINT        NOT NULL,
    property_facility_id BIGINT        NOT NULL DEFAULT 0,
    entry_type           VARCHAR(10)   NOT NULL,                  -- IN | OUT
    amount               DECIMAL(12,2) NOT NULL,
    note                 VARCHAR(255),
    entry_date           DATE          NOT NULL,
    expense_id           BIGINT        NULL,                      -- set when auto-created from a cash expense
    created_by           BIGINT        NULL,
    created_at           DATETIME      NOT NULL,
    updated_at           DATETIME      NOT NULL,
    KEY idx_pce_scope_date (organization_id, property_facility_id, entry_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
