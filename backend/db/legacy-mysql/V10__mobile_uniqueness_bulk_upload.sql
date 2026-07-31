-- V10: Unique mobile number per person + bulk upload job tracking

-- One phone number = one person globally.
-- The same party can join multiple orgs via facility_party, so this is correct.
-- If existing data has duplicate mobile numbers, this migration will fail:
-- manually deduplicate before running (keep the earliest party_id per mobile).
ALTER TABLE person ADD UNIQUE KEY uk_person_mobile (mobile_number);

CREATE TABLE bulk_upload_job (
    job_id                      BIGINT PRIMARY KEY AUTO_INCREMENT,
    organization_id             BIGINT NOT NULL,
    upload_type                 VARCHAR(30) NOT NULL,
    total_rows                  INT NOT NULL DEFAULT 0,
    created_rows                INT NOT NULL DEFAULT 0,
    updated_rows                INT NOT NULL DEFAULT 0,
    failed_rows                 INT NOT NULL DEFAULT 0,
    performed_by_user_login_id  BIGINT NOT NULL,
    created_at                  DATETIME(6) NOT NULL,
    CONSTRAINT fk_upload_job_org  FOREIGN KEY (organization_id) REFERENCES facility (facility_id),
    CONSTRAINT fk_upload_job_user FOREIGN KEY (performed_by_user_login_id) REFERENCES user_login (user_login_id)
);
