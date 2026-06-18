CREATE TABLE party (
    party_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    party_type_id VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL
);

CREATE TABLE person (
    party_id BIGINT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    mobile_number VARCHAR(20) NOT NULL,
    gender VARCHAR(20),
    date_of_birth DATE,
    aadhaar_number VARCHAR(20),
    occupation VARCHAR(100),
    company_name VARCHAR(150),
    guardian_name VARCHAR(150),
    guardian_mobile_number VARCHAR(20),
    address VARCHAR(500),
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_person_party FOREIGN KEY (party_id) REFERENCES party (party_id)
);

CREATE TABLE facility (
    facility_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT,
    facility_type_id VARCHAR(30) NOT NULL,
    facility_name VARCHAR(150) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    sharing_type VARCHAR(50),
    capacity INT,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_facility_org_type (organization_id, facility_type_id),
    CONSTRAINT fk_facility_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id)
);

CREATE TABLE facility_group_member (
    facility_group_member_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    parent_facility_id BIGINT NOT NULL,
    child_facility_id BIGINT NOT NULL,
    from_date DATE NOT NULL,
    thru_date DATE,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_facility_group_active (parent_facility_id, child_facility_id, from_date),
    CONSTRAINT fk_fgm_parent FOREIGN KEY (parent_facility_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_fgm_child FOREIGN KEY (child_facility_id) REFERENCES facility (facility_id)
);

CREATE TABLE user_login (
    user_login_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    party_id BIGINT NOT NULL,
    username VARCHAR(120) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role_type_id VARCHAR(30) NOT NULL,
    organization_id BIGINT,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_user_party FOREIGN KEY (party_id) REFERENCES party (party_id),
    CONSTRAINT fk_user_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id)
);

CREATE TABLE refresh_token (
    refresh_token_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_login_id BIGINT NOT NULL,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    expires_at DATETIME(6) NOT NULL,
    revoked BOOLEAN NOT NULL DEFAULT FALSE,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_refresh_user FOREIGN KEY (user_login_id) REFERENCES user_login (user_login_id)
);

CREATE TABLE facility_party (
    facility_party_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    facility_id BIGINT NOT NULL,
    party_id BIGINT NOT NULL,
    role_type_id VARCHAR(30) NOT NULL,
    from_date DATE NOT NULL,
    thru_date DATE,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_facility_party_org (organization_id),
    INDEX idx_facility_party_facility (facility_id),
    INDEX idx_facility_party_party (party_id),
    CONSTRAINT fk_fp_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_fp_facility FOREIGN KEY (facility_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_fp_party FOREIGN KEY (party_id) REFERENCES party (party_id)
);

CREATE TABLE rent (
    rent_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    party_id BIGINT NOT NULL,
    facility_id BIGINT,
    rent_month DATE NOT NULL,
    monthly_rent DECIMAL(12, 2) NOT NULL DEFAULT 0,
    deposit DECIMAL(12, 2) NOT NULL DEFAULT 0,
    advance DECIMAL(12, 2) NOT NULL DEFAULT 0,
    discount DECIMAL(12, 2) NOT NULL DEFAULT 0,
    penalty DECIMAL(12, 2) NOT NULL DEFAULT 0,
    paid_amount DECIMAL(12, 2) NOT NULL DEFAULT 0,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_rent_org_month (organization_id, rent_month),
    CONSTRAINT fk_rent_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_rent_party FOREIGN KEY (party_id) REFERENCES party (party_id),
    CONSTRAINT fk_rent_facility FOREIGN KEY (facility_id) REFERENCES facility (facility_id)
);

CREATE TABLE payment (
    payment_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    rent_id BIGINT,
    party_id BIGINT NOT NULL,
    amount DECIMAL(12, 2) NOT NULL,
    payment_mode VARCHAR(30) NOT NULL,
    payment_date DATE NOT NULL,
    reference_number VARCHAR(120),
    notes VARCHAR(500),
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_payment_org_date (organization_id, payment_date),
    CONSTRAINT fk_payment_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_payment_rent FOREIGN KEY (rent_id) REFERENCES rent (rent_id),
    CONSTRAINT fk_payment_party FOREIGN KEY (party_id) REFERENCES party (party_id)
);

CREATE TABLE feature_master (
    feature_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    feature_code VARCHAR(60) NOT NULL UNIQUE,
    feature_name VARCHAR(120) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL
);

CREATE TABLE organization_feature (
    organization_feature_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    feature_id BIGINT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_org_feature (organization_id, feature_id),
    CONSTRAINT fk_org_feature_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_org_feature_feature FOREIGN KEY (feature_id) REFERENCES feature_master (feature_id)
);

CREATE TABLE subscription (
    subscription_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT NOT NULL,
    plan_code VARCHAR(30) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    renewal_date DATE,
    status VARCHAR(30) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_subscription_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id)
);

CREATE TABLE audit_log (
    audit_log_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id BIGINT,
    user_login_id BIGINT,
    action VARCHAR(80) NOT NULL,
    entity_type VARCHAR(80),
    entity_id VARCHAR(80),
    ip_address VARCHAR(80),
    details VARCHAR(1000),
    created_at DATETIME(6) NOT NULL,
    INDEX idx_audit_org_action (organization_id, action),
    CONSTRAINT fk_audit_org FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_audit_user FOREIGN KEY (user_login_id) REFERENCES user_login (user_login_id)
);
