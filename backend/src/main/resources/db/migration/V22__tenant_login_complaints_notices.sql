-- Tenant Module: tenant-login lifecycle columns, opt-in feature, complaints & notices.

-- 1) Tenant-login lifecycle columns on user_login.
--    disabled_reason records WHY a login is INACTIVE (e.g. CHECKED_OUT); must_change_password
--    forces a first-login password change (temp password abc@123); last_login_at is audit/telemetry.
ALTER TABLE user_login
    ADD COLUMN disabled_reason VARCHAR(40) NULL,
    ADD COLUMN must_change_password TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN last_login_at DATETIME(6) NULL;

-- 2) Tenant Login is opt-in per organization, toggled only by the Super Admin.
--    Reuses the feature_master / organization_feature pattern (like EMAIL/WHATSAPP): a login is
--    provisioned only when an organization_feature row exists with enabled = TRUE for this code.
INSERT IGNORE INTO feature_master (feature_code, feature_name, active, created_at, updated_at) VALUES
    ('TENANT_LOGIN', 'Tenant Login', TRUE, NOW(6), NOW(6));

-- 3) Notification categories used by the tenant module (notification.category_id FK).
INSERT IGNORE INTO notification_category (category_id, name, description, active) VALUES
    ('COMPLAINT', 'Complaint Updates', 'Tenant complaint status changes and new complaints', TRUE),
    ('NOTICE',    'Notices',           'Announcements and property notices', TRUE);

-- 4) Complaints raised by tenants.
CREATE TABLE complaint (
    complaint_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    party_id BIGINT NOT NULL,                       -- the tenant who raised it
    property_facility_id BIGINT NULL,               -- resolved from the tenant's active bed (nullable)
    category VARCHAR(40) NOT NULL,
    title VARCHAR(160) NOT NULL,
    description VARCHAR(2000) NOT NULL,
    priority VARCHAR(20) NOT NULL DEFAULT 'MEDIUM',
    status VARCHAR(20) NOT NULL DEFAULT 'OPEN',      -- OPEN / IN_PROGRESS / RESOLVED / CLOSED
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_complaint_org_party (organization_id, party_id),
    INDEX idx_complaint_org_status (organization_id, status),
    CONSTRAINT fk_complaint_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_complaint_party FOREIGN KEY (party_id) REFERENCES party (party_id)
);

CREATE TABLE complaint_status_history (
    complaint_status_history_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    complaint_id BIGINT NOT NULL,
    from_status VARCHAR(20) NULL,
    to_status VARCHAR(20) NOT NULL,
    note VARCHAR(1000) NULL,
    changed_by_user_login_id BIGINT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_complaint_history_complaint (complaint_id),
    CONSTRAINT fk_complaint_history_complaint FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id)
);

-- 5) Notices published to tenants (org-wide when property_facility_id IS NULL).
CREATE TABLE notice (
    notice_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    property_facility_id BIGINT NULL,
    notice_type VARCHAR(30) NOT NULL DEFAULT 'ANNOUNCEMENT',  -- ANNOUNCEMENT/RENT_REMINDER/MAINTENANCE/WATER_SHUTDOWN/POWER_SHUTDOWN
    title VARCHAR(160) NOT NULL,
    body VARCHAR(4000) NOT NULL,
    published_at DATETIME(6) NOT NULL,
    expires_at DATETIME(6) NULL,
    created_by_user_login_id BIGINT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_notice_org_active (organization_id, active),
    CONSTRAINT fk_notice_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id)
);

CREATE TABLE notice_read (
    notice_read_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    notice_id BIGINT NOT NULL,
    party_id BIGINT NOT NULL,
    read_at DATETIME(6) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_notice_read (notice_id, party_id),
    CONSTRAINT fk_notice_read_notice FOREIGN KEY (notice_id) REFERENCES notice (notice_id),
    CONSTRAINT fk_notice_read_party FOREIGN KEY (party_id) REFERENCES party (party_id)
);
