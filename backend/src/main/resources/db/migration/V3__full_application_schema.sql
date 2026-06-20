-- PG Manager full-application extension. Existing phase-1 tables remain compatible.

CREATE TABLE status_type (
    status_id VARCHAR(40) PRIMARY KEY,
    status_group VARCHAR(40) NOT NULL,
    description VARCHAR(160) NOT NULL,
    sequence_num INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE role_type (
    role_type_id VARCHAR(40) PRIMARY KEY,
    description VARCHAR(160) NOT NULL,
    parent_role_type_id VARCHAR(40),
    CONSTRAINT fk_role_type_parent FOREIGN KEY (parent_role_type_id) REFERENCES role_type (role_type_id)
);

CREATE TABLE permission (
    permission_id VARCHAR(80) PRIMARY KEY,
    module_code VARCHAR(40) NOT NULL,
    description VARCHAR(200) NOT NULL
);

CREATE TABLE role_permission (
    role_type_id VARCHAR(40) NOT NULL,
    permission_id VARCHAR(80) NOT NULL,
    from_date DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    thru_date DATETIME(6),
    PRIMARY KEY (role_type_id, permission_id, from_date),
    CONSTRAINT fk_role_permission_role FOREIGN KEY (role_type_id) REFERENCES role_type (role_type_id),
    CONSTRAINT fk_role_permission_permission FOREIGN KEY (permission_id) REFERENCES permission (permission_id)
);

CREATE TABLE party_role (
    party_id BIGINT NOT NULL,
    role_type_id VARCHAR(40) NOT NULL,
    organization_id BIGINT,
    from_date DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    thru_date DATETIME(6),
    PRIMARY KEY (party_id, role_type_id, from_date),
    INDEX idx_party_role_org_active (organization_id, role_type_id, thru_date),
    CONSTRAINT fk_party_role_party FOREIGN KEY (party_id) REFERENCES party (party_id),
    CONSTRAINT fk_party_role_role FOREIGN KEY (role_type_id) REFERENCES role_type (role_type_id),
    CONSTRAINT fk_party_role_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id)
);

CREATE TABLE contact_mech (
    contact_mech_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    contact_mech_type_id VARCHAR(40) NOT NULL,
    info_string VARCHAR(500),
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL
);

CREATE TABLE postal_address (
    contact_mech_id BIGINT PRIMARY KEY,
    address1 VARCHAR(250) NOT NULL,
    address2 VARCHAR(250),
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(100),
    postal_code VARCHAR(20),
    country_code VARCHAR(3) NOT NULL DEFAULT 'IND',
    CONSTRAINT fk_postal_contact FOREIGN KEY (contact_mech_id) REFERENCES contact_mech (contact_mech_id)
);

CREATE TABLE party_contact_mech (
    party_id BIGINT NOT NULL,
    contact_mech_id BIGINT NOT NULL,
    purpose_type_id VARCHAR(40) NOT NULL,
    from_date DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    thru_date DATETIME(6),
    PRIMARY KEY (party_id, contact_mech_id, purpose_type_id, from_date),
    CONSTRAINT fk_pcm_party FOREIGN KEY (party_id) REFERENCES party (party_id),
    CONSTRAINT fk_pcm_contact FOREIGN KEY (contact_mech_id) REFERENCES contact_mech (contact_mech_id)
);

ALTER TABLE facility ADD COLUMN description VARCHAR(1000), ADD COLUMN room_number VARCHAR(30),
    ADD COLUMN floor_number INT, ADD COLUMN monthly_rent DECIMAL(12,2), ADD COLUMN security_deposit DECIMAL(12,2),
    ADD COLUMN size_sq_ft DECIMAL(10,2), ADD COLUMN available_from DATE, ADD COLUMN version BIGINT NOT NULL DEFAULT 0;

CREATE TABLE facility_contact_mech (
    facility_id BIGINT NOT NULL,
    contact_mech_id BIGINT NOT NULL,
    purpose_type_id VARCHAR(40) NOT NULL,
    from_date DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    thru_date DATETIME(6),
    PRIMARY KEY (facility_id, contact_mech_id, purpose_type_id, from_date),
    CONSTRAINT fk_fcm_facility FOREIGN KEY (facility_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_fcm_contact FOREIGN KEY (contact_mech_id) REFERENCES contact_mech (contact_mech_id)
);

CREATE TABLE amenity_type (
    amenity_type_id VARCHAR(40) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    icon_code VARCHAR(60),
    active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE facility_amenity (
    facility_id BIGINT NOT NULL,
    amenity_type_id VARCHAR(40) NOT NULL,
    available BOOLEAN NOT NULL DEFAULT TRUE,
    details VARCHAR(500),
    PRIMARY KEY (facility_id, amenity_type_id),
    CONSTRAINT fk_fa_facility FOREIGN KEY (facility_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_fa_type FOREIGN KEY (amenity_type_id) REFERENCES amenity_type (amenity_type_id)
);

CREATE TABLE content_reference (
    content_reference_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    owner_entity_type VARCHAR(40) NOT NULL,
    owner_entity_id BIGINT NOT NULL,
    content_type_id VARCHAR(40) NOT NULL,
    storage_provider VARCHAR(40),
    storage_key VARCHAR(500),
    mime_type VARCHAR(100),
    status VARCHAR(30) NOT NULL DEFAULT 'STORAGE_DISABLED',
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_content_owner (organization_id, owner_entity_type, owner_entity_id),
    CONSTRAINT fk_content_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id)
);

CREATE TABLE tenant_employment (
    tenant_employment_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    party_id BIGINT NOT NULL,
    company_name VARCHAR(160), designation VARCHAR(120), employee_id VARCHAR(80),
    monthly_salary DECIMAL(12,2), work_email VARCHAR(160), office_address VARCHAR(500),
    from_date DATE NOT NULL, thru_date DATE,
    created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL,
    INDEX idx_employment_tenant (organization_id, party_id, thru_date),
    CONSTRAINT fk_employment_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_employment_party FOREIGN KEY (party_id) REFERENCES party (party_id)
);

CREATE TABLE emergency_contact (
    emergency_contact_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL, party_id BIGINT NOT NULL,
    contact_name VARCHAR(150) NOT NULL, relationship_type_id VARCHAR(40) NOT NULL,
    mobile_number VARCHAR(20) NOT NULL, alternate_number VARCHAR(20), address VARCHAR(500),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL,
    INDEX idx_emergency_party (organization_id, party_id),
    CONSTRAINT fk_emergency_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_emergency_party FOREIGN KEY (party_id) REFERENCES party (party_id)
);

CREATE TABLE identity_document (
    identity_document_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL, party_id BIGINT NOT NULL,
    document_type_id VARCHAR(40) NOT NULL, document_number VARCHAR(120),
    verification_status VARCHAR(30) NOT NULL DEFAULT 'PENDING', verified_at DATETIME(6),
    expires_on DATE, content_reference_id BIGINT,
    created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_identity_org_party_type (organization_id, party_id, document_type_id),
    CONSTRAINT fk_identity_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_identity_party FOREIGN KEY (party_id) REFERENCES party (party_id),
    CONSTRAINT fk_identity_content FOREIGN KEY (content_reference_id) REFERENCES content_reference (content_reference_id)
);

CREATE TABLE admission (
    admission_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL, party_id BIGINT NOT NULL, bed_facility_id BIGINT NOT NULL,
    move_in_date DATE NOT NULL, monthly_rent DECIMAL(12,2) NOT NULL,
    security_deposit DECIMAL(12,2) NOT NULL DEFAULT 0, advance_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    notice_period_days INT NOT NULL DEFAULT 30, status VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
    created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL, version BIGINT NOT NULL DEFAULT 0,
    INDEX idx_admission_org_status (organization_id, status),
    CONSTRAINT fk_admission_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_admission_party FOREIGN KEY (party_id) REFERENCES party (party_id),
    CONSTRAINT fk_admission_bed FOREIGN KEY (bed_facility_id) REFERENCES facility (facility_id)
);

CREATE TABLE agreement (
    agreement_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL, admission_id BIGINT NOT NULL,
    agreement_type_id VARCHAR(40) NOT NULL DEFAULT 'ACCOMMODATION',
    agreement_number VARCHAR(80) NOT NULL, from_date DATE NOT NULL, thru_date DATE,
    terms LONGTEXT, status VARCHAR(30) NOT NULL DEFAULT 'DRAFT', signed_at DATETIME(6),
    created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL, version BIGINT NOT NULL DEFAULT 0,
    UNIQUE KEY uk_agreement_org_number (organization_id, agreement_number),
    CONSTRAINT fk_agreement_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_agreement_admission FOREIGN KEY (admission_id) REFERENCES admission (admission_id)
);

CREATE TABLE checkout (
    checkout_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL, admission_id BIGINT NOT NULL,
    checkout_date DATE NOT NULL, pending_dues DECIMAL(12,2) NOT NULL DEFAULT 0,
    damage_charges DECIMAL(12,2) NOT NULL DEFAULT 0, other_deductions DECIMAL(12,2) NOT NULL DEFAULT 0,
    refundable_deposit DECIMAL(12,2) NOT NULL DEFAULT 0, status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    refund_method VARCHAR(30), refund_reference VARCHAR(120), settled_at DATETIME(6),
    created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_checkout_admission (admission_id),
    CONSTRAINT fk_checkout_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_checkout_admission FOREIGN KEY (admission_id) REFERENCES admission (admission_id)
);

CREATE TABLE billing_account (
    billing_account_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL, party_id BIGINT NOT NULL, admission_id BIGINT,
    currency_code CHAR(3) NOT NULL DEFAULT 'INR', status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    advance_balance DECIMAL(12,2) NOT NULL DEFAULT 0,
    created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL, version BIGINT NOT NULL DEFAULT 0,
    INDEX idx_billing_party (organization_id, party_id, status),
    CONSTRAINT fk_billing_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_billing_party FOREIGN KEY (party_id) REFERENCES party (party_id),
    CONSTRAINT fk_billing_admission FOREIGN KEY (admission_id) REFERENCES admission (admission_id)
);

CREATE TABLE recurring_charge (
    recurring_charge_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    billing_account_id BIGINT NOT NULL, charge_type_id VARCHAR(40) NOT NULL,
    description VARCHAR(200) NOT NULL, amount DECIMAL(12,2) NOT NULL,
    from_date DATE NOT NULL, thru_date DATE,
    created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_charge_account FOREIGN KEY (billing_account_id) REFERENCES billing_account (billing_account_id)
);

CREATE TABLE invoice (
    invoice_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL, billing_account_id BIGINT NOT NULL,
    legacy_rent_id BIGINT, invoice_number VARCHAR(80) NOT NULL,
    invoice_month DATE NOT NULL, issue_date DATE NOT NULL, due_date DATE NOT NULL,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0, paid_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL, version BIGINT NOT NULL DEFAULT 0,
    UNIQUE KEY uk_invoice_org_number (organization_id, invoice_number),
    UNIQUE KEY uk_invoice_legacy_rent (legacy_rent_id),
    INDEX idx_invoice_org_month_status (organization_id, invoice_month, status),
    CONSTRAINT fk_invoice_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_invoice_account FOREIGN KEY (billing_account_id) REFERENCES billing_account (billing_account_id),
    CONSTRAINT fk_invoice_legacy FOREIGN KEY (legacy_rent_id) REFERENCES rent (rent_id)
);

CREATE TABLE invoice_item (
    invoice_item_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    invoice_id BIGINT NOT NULL, item_type_id VARCHAR(40) NOT NULL,
    description VARCHAR(200) NOT NULL, amount DECIMAL(12,2) NOT NULL,
    created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_invoice_item_invoice FOREIGN KEY (invoice_id) REFERENCES invoice (invoice_id)
);

CREATE TABLE payment_allocation (
    payment_allocation_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL, payment_id BIGINT NOT NULL, invoice_id BIGINT NOT NULL,
    amount DECIMAL(12,2) NOT NULL, allocated_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_payment_invoice (payment_id, invoice_id),
    CONSTRAINT fk_allocation_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_allocation_payment FOREIGN KEY (payment_id) REFERENCES payment (payment_id),
    CONSTRAINT fk_allocation_invoice FOREIGN KEY (invoice_id) REFERENCES invoice (invoice_id)
);

CREATE TABLE payment_refund (
    payment_refund_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL, payment_id BIGINT NOT NULL,
    amount DECIMAL(12,2) NOT NULL, refund_method VARCHAR(30) NOT NULL DEFAULT 'CASH',
    reference_number VARCHAR(120), reason VARCHAR(500), status VARCHAR(30) NOT NULL DEFAULT 'RECORDED',
    refunded_at DATETIME(6) NOT NULL, created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_refund_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_refund_payment FOREIGN KEY (payment_id) REFERENCES payment (payment_id)
);

ALTER TABLE payment ADD COLUMN idempotency_key VARCHAR(100), ADD COLUMN provider_code VARCHAR(40),
    ADD COLUMN external_transaction_id VARCHAR(160), ADD COLUMN status VARCHAR(30) NOT NULL DEFAULT 'RECEIVED';
CREATE UNIQUE INDEX uk_payment_org_idempotency ON payment (organization_id, idempotency_key);

CREATE TABLE notification_category (
    category_id VARCHAR(40) PRIMARY KEY, name VARCHAR(100) NOT NULL, description VARCHAR(250), active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE notification (
    notification_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL, category_id VARCHAR(40) NOT NULL,
    title VARCHAR(160) NOT NULL, message VARCHAR(2000) NOT NULL,
    entity_type VARCHAR(40), entity_id BIGINT, priority VARCHAR(20) NOT NULL DEFAULT 'NORMAL',
    created_at DATETIME(6) NOT NULL, expires_at DATETIME(6),
    INDEX idx_notification_org_created (organization_id, created_at),
    CONSTRAINT fk_notification_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_notification_category FOREIGN KEY (category_id) REFERENCES notification_category (category_id)
);

CREATE TABLE notification_recipient (
    notification_recipient_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    notification_id BIGINT NOT NULL, party_id BIGINT NOT NULL,
    read_at DATETIME(6), archived_at DATETIME(6), important BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE KEY uk_notification_party (notification_id, party_id),
    CONSTRAINT fk_nr_notification FOREIGN KEY (notification_id) REFERENCES notification (notification_id),
    CONSTRAINT fk_nr_party FOREIGN KEY (party_id) REFERENCES party (party_id)
);

CREATE TABLE notification_preference (
    party_id BIGINT NOT NULL, category_id VARCHAR(40) NOT NULL, channel_type_id VARCHAR(30) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE, updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (party_id, category_id, channel_type_id),
    CONSTRAINT fk_np_party FOREIGN KEY (party_id) REFERENCES party (party_id),
    CONSTRAINT fk_np_category FOREIGN KEY (category_id) REFERENCES notification_category (category_id)
);

CREATE TABLE notification_outbox (
    outbox_id BIGINT PRIMARY KEY AUTO_INCREMENT, notification_id BIGINT NOT NULL, party_id BIGINT NOT NULL,
    channel_type_id VARCHAR(30) NOT NULL, provider_code VARCHAR(40), provider_message_id VARCHAR(160),
    status VARCHAR(30) NOT NULL DEFAULT 'DISABLED', attempt_count INT NOT NULL DEFAULT 0,
    next_attempt_at DATETIME(6), last_error VARCHAR(1000), created_at DATETIME(6) NOT NULL, updated_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_outbox_notification FOREIGN KEY (notification_id) REFERENCES notification (notification_id),
    CONSTRAINT fk_outbox_party FOREIGN KEY (party_id) REFERENCES party (party_id)
);

CREATE TABLE user_preference (
    user_login_id BIGINT NOT NULL, preference_key VARCHAR(80) NOT NULL, preference_value VARCHAR(1000),
    updated_at DATETIME(6) NOT NULL, PRIMARY KEY (user_login_id, preference_key),
    CONSTRAINT fk_preference_user FOREIGN KEY (user_login_id) REFERENCES user_login (user_login_id)
);

CREATE TABLE login_history (
    login_history_id BIGINT PRIMARY KEY AUTO_INCREMENT, user_login_id BIGINT NOT NULL,
    login_at DATETIME(6) NOT NULL, logout_at DATETIME(6), ip_address VARCHAR(80), user_agent VARCHAR(500),
    success BOOLEAN NOT NULL, failure_reason VARCHAR(250),
    CONSTRAINT fk_login_history_user FOREIGN KEY (user_login_id) REFERENCES user_login (user_login_id)
);

CREATE TABLE password_reset_token (
    password_reset_token_id BIGINT PRIMARY KEY AUTO_INCREMENT, user_login_id BIGINT NOT NULL,
    token_hash VARCHAR(255) NOT NULL UNIQUE, expires_at DATETIME(6) NOT NULL, used_at DATETIME(6), created_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_password_reset_user FOREIGN KEY (user_login_id) REFERENCES user_login (user_login_id)
);

CREATE TABLE user_device (
    user_device_id BIGINT PRIMARY KEY AUTO_INCREMENT, user_login_id BIGINT NOT NULL,
    device_identifier_hash VARCHAR(255) NOT NULL, platform VARCHAR(30) NOT NULL,
    biometric_enabled BOOLEAN NOT NULL DEFAULT FALSE, push_token VARCHAR(500),
    last_seen_at DATETIME(6) NOT NULL, revoked_at DATETIME(6),
    UNIQUE KEY uk_user_device (user_login_id, device_identifier_hash),
    CONSTRAINT fk_user_device_user FOREIGN KEY (user_login_id) REFERENCES user_login (user_login_id)
);

CREATE TABLE subscription_plan (
    plan_id BIGINT PRIMARY KEY AUTO_INCREMENT, plan_code VARCHAR(40) NOT NULL UNIQUE, name VARCHAR(100) NOT NULL,
    price_monthly DECIMAL(12,2) NOT NULL DEFAULT 0, property_limit INT, active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME(6) NOT NULL , updated_at DATETIME(6) NOT NULL
);

CREATE TABLE plan_feature (
    plan_id BIGINT NOT NULL, feature_id BIGINT NOT NULL, enabled BOOLEAN NOT NULL DEFAULT TRUE,
    limit_value BIGINT, PRIMARY KEY (plan_id, feature_id),
    CONSTRAINT fk_plan_feature_plan FOREIGN KEY (plan_id) REFERENCES subscription_plan (plan_id),
    CONSTRAINT fk_plan_feature_feature FOREIGN KEY (feature_id) REFERENCES feature_master (feature_id)
);

CREATE TABLE system_setting (
    setting_key VARCHAR(100) PRIMARY KEY, setting_value VARCHAR(2000), encrypted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_by_user_login_id BIGINT, updated_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_system_setting_user FOREIGN KEY (updated_by_user_login_id) REFERENCES user_login (user_login_id)
);

ALTER TABLE audit_log ADD COLUMN correlation_id VARCHAR(100), ADD COLUMN old_values_json JSON,
    ADD COLUMN new_values_json JSON, ADD COLUMN user_agent VARCHAR(500);

INSERT INTO role_type (role_type_id, description) VALUES
('SUPER_ADMIN','Platform administrator'),('OWNER','Organization owner'),('PROPERTY_MANAGER','Property manager'),
('MANAGER','Manager'),('ACCOUNTANT','Accountant'),('SUPPORT','Support'),('VIEWER','Read-only user'),
('TENANT','Tenant'),('OCCUPANT','Active bed occupant');

INSERT INTO permission (permission_id,module_code,description) VALUES
('DASHBOARD_VIEW','DASHBOARD','View dashboards'),('PROPERTY_MANAGE','PROPERTY','Manage properties and inventory'),
('TENANT_MANAGE','TENANT','Manage tenants and admissions'),('BILLING_MANAGE','BILLING','Manage invoices and payments'),
('REPORT_VIEW','REPORTS','View reports'),('SETTINGS_MANAGE','SETTINGS','Manage organization settings'),
('PLATFORM_MANAGE','ADMIN','Manage the SaaS platform');

INSERT INTO role_permission (role_type_id,permission_id) SELECT 'OWNER', permission_id FROM permission WHERE permission_id <> 'PLATFORM_MANAGE';
INSERT INTO role_permission (role_type_id,permission_id) SELECT 'SUPER_ADMIN', permission_id FROM permission;

INSERT INTO amenity_type (amenity_type_id,name,icon_code) VALUES
('WIFI','WiFi','wifi'),('POWER_BACKUP','Power Backup','bolt'),('CCTV','CCTV','videocam'),('RO_WATER','RO Water','water_drop'),
('PARKING','Parking','local_parking'),('CLEANING','Cleaning','cleaning_services'),('FOOD','Food','restaurant'),
('LAUNDRY','Laundry','local_laundry_service'),('AC','Air Conditioning','ac_unit');

INSERT INTO notification_category (category_id,name,description) VALUES
('RENT_REMINDER','Rent reminders','Rent due and overdue reminders'),('PAYMENT_UPDATE','Payment updates','Payments, failures and refunds'),
('MAINTENANCE','Maintenance alerts','Maintenance schedules and updates'),('COMPLAINT','Complaint updates','Complaint status changes'),
('TENANT_UPDATE','Tenant updates','Tenant admission and checkout'),('AGREEMENT','Agreements and leases','Agreement lifecycle updates'),
('PROMOTION','Promotions and offers','Optional promotions');


INSERT INTO subscription_plan
(
plan_code,
name,
price_monthly,
property_limit,
created_at,
updated_at
)
VALUES
('BASIC','Basic Plan',999,10,NOW(),NOW()),
('STANDARD','Standard Plan',1999,50,NOW(),NOW()),
('PREMIUM','Premium Plan',3999,NULL,NOW(),NOW()),
('ENTERPRISE','Enterprise Plan',7999,NULL,NOW(),NOW());


-- Backfill normalized billing accounts and invoices without changing legacy API behavior.
INSERT INTO billing_account (organization_id,party_id,currency_code,status,advance_balance,created_at,updated_at)
SELECT DISTINCT r.organization_id,r.party_id,'INR','ACTIVE',0,NOW(6),NOW(6) FROM rent r;

INSERT INTO invoice (organization_id,billing_account_id,legacy_rent_id,invoice_number,invoice_month,issue_date,due_date,total_amount,paid_amount,status,created_at,updated_at)
SELECT r.organization_id, MIN(ba.billing_account_id), r.rent_id, CONCAT('LEGACY-',r.rent_id), r.rent_month,
       r.rent_month, DATE_ADD(r.rent_month, INTERVAL 9 DAY),
       r.monthly_rent + r.deposit + r.advance + r.penalty - r.discount, r.paid_amount, r.status, r.created_at, r.updated_at
FROM rent r JOIN billing_account ba ON ba.organization_id=r.organization_id AND ba.party_id=r.party_id
GROUP BY r.rent_id,r.organization_id,r.rent_month,r.monthly_rent,r.deposit,r.advance,r.penalty,r.discount,r.paid_amount,r.status,r.created_at,r.updated_at;

INSERT INTO invoice_item (invoice_id,item_type_id,description,amount,created_at,updated_at)
SELECT i.invoice_id,'MONTHLY_RENT','Monthly rent',r.monthly_rent,NOW(6),NOW(6) FROM invoice i JOIN rent r ON r.rent_id=i.legacy_rent_id;

INSERT INTO payment_allocation (organization_id,payment_id,invoice_id,amount,allocated_at)
SELECT p.organization_id,p.payment_id,i.invoice_id,p.amount,TIMESTAMP(p.payment_date)
FROM payment p JOIN invoice i ON i.legacy_rent_id=p.rent_id WHERE p.rent_id IS NOT NULL;
