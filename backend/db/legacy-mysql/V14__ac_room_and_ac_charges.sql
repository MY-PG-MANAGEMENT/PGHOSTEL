-- V14: Add is_ac flag to facility (room-level AC indicator)
--       Add ac_charges column to property_sharing_price

ALTER TABLE facility
    ADD COLUMN is_ac TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 = Air-Conditioned room';

ALTER TABLE property_sharing_price
    ADD COLUMN ac_charges DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT 'Default AC surcharge per month';
