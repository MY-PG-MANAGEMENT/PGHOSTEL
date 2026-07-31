-- Per-day price for temporary stays, set per property + sharing type in Price Master.
-- Temporary-stay amount = number of days * per_day_price (editable before invoicing).
ALTER TABLE property_sharing_price
    ADD COLUMN per_day_price DECIMAL(10,2) NOT NULL DEFAULT 0;
