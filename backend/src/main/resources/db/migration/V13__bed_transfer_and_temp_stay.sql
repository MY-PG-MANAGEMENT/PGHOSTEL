-- V13: Bed-transfer scheduling + temporary-stay support
--
-- scheduled_bed_transfer: a sharing-type change is not applied immediately. It is
-- recorded here and applied on its effective_date (the tenant's next billing-cycle
-- anniversary) so the current month's invoice is untouched and the new sharing's
-- rent only starts from the next cycle. Same-sharing transfers are applied inline
-- and never create a row here.
CREATE TABLE scheduled_bed_transfer (
    scheduled_bed_transfer_id BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id           BIGINT       NOT NULL,
    party_id                  BIGINT       NOT NULL,
    from_bed_facility_id      BIGINT,
    to_bed_facility_id        BIGINT       NOT NULL,
    effective_date            DATE         NOT NULL,
    new_monthly_rent          DECIMAL(10,2),
    new_security_deposit      DECIMAL(10,2),
    status                    VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    note                      VARCHAR(255),
    created_at                DATETIME     NOT NULL,
    updated_at                DATETIME     NOT NULL,
    KEY idx_sbt_due (status, effective_date),
    KEY idx_sbt_party (organization_id, party_id, status),
    KEY idx_sbt_to_bed (to_bed_facility_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Temporary stays reuse facility_party with a distinct role (TEMP_OCCUPANT). No
-- schema change is required for that; the role string carries the meaning and such
-- rows are deliberately excluded from billing/invoice generation.
