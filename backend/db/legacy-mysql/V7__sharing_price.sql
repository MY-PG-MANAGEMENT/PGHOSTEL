CREATE TABLE property_sharing_price (
    id                  BIGINT NOT NULL AUTO_INCREMENT,
    organization_id     BIGINT NOT NULL,
    property_facility_id BIGINT NOT NULL,
    sharing_type        VARCHAR(5) NOT NULL,
    monthly_rent        DECIMAL(10,2) NOT NULL,
    security_deposit    DECIMAL(10,2) NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uk_prop_sharing (property_facility_id, sharing_type),
    CONSTRAINT fk_psp_facility FOREIGN KEY (property_facility_id) REFERENCES facility (facility_id)
);

ALTER TABLE facility_party
    ADD COLUMN monthly_rent      DECIMAL(10,2) NULL,
    ADD COLUMN security_deposit  DECIMAL(10,2) NULL;
