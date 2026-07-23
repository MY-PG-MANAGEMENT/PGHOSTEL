-- V18: AC-charges breakdown on bed occupancy.
--
-- facility_party.monthly_rent stays the ALL-IN monthly amount (base rent + AC)
-- so billing totals are unchanged everywhere. ac_charges only annotates how
-- much of that total is the AC premium, letting invoices itemize
-- MONTHLY_RENT (base) + AC_CHARGES instead of one lump-sum line.
ALTER TABLE facility_party
    ADD COLUMN ac_charges DECIMAL(10,2) NULL AFTER monthly_rent;
