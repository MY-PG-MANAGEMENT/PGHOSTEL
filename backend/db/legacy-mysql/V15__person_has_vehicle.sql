-- V15: Add has_vehicle flag to person (tenant owns a vehicle yes/no)

ALTER TABLE person
    ADD COLUMN has_vehicle TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 = tenant has a vehicle';
