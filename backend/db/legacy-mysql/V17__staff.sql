-- V17: Staff management (employees + monthly salary payments)
--
-- Staff are simple employees (cook, warden, security...) — they don't need
-- logins or tenancy features, so this deliberately does NOT reuse
-- party/person. Professions are plain strings (UI offers common suggestions).
-- Paying a salary also inserts an `expense` row (category SALARY, linked via
-- staff_salary_payment.expense_id) so the expenses dashboard reflects payroll.

CREATE TABLE staff (
    staff_id             BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id      BIGINT        NOT NULL,
    property_facility_id BIGINT        NULL,                       -- NULL = org-level staff
    full_name            VARCHAR(120)  NOT NULL,
    profession           VARCHAR(60)   NOT NULL,
    mobile_number        VARCHAR(15),
    monthly_salary       DECIMAL(12,2) NOT NULL,
    join_date            DATE,
    status               VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | INACTIVE
    notes                VARCHAR(255),
    created_at           DATETIME      NOT NULL,
    updated_at           DATETIME      NOT NULL,
    KEY idx_staff_org (organization_id, status),
    KEY idx_staff_prop (property_facility_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- One row per staff per month; the unique key is the double-payment guard.
CREATE TABLE staff_salary_payment (
    staff_salary_payment_id BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id         BIGINT        NOT NULL,
    staff_id                BIGINT        NOT NULL,
    pay_month               CHAR(7)       NOT NULL,                -- 'YYYY-MM'
    amount                  DECIMAL(12,2) NOT NULL,
    payment_method          VARCHAR(20)   NOT NULL DEFAULT 'CASH',
    paid_date               DATE          NOT NULL,
    expense_id              BIGINT        NULL,                    -- linked SALARY expense row
    created_by              BIGINT        NULL,
    created_at              DATETIME      NOT NULL,
    updated_at              DATETIME      NOT NULL,
    UNIQUE KEY uk_staff_pay_month (staff_id, pay_month),
    KEY idx_ssp_org_month (organization_id, pay_month)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
