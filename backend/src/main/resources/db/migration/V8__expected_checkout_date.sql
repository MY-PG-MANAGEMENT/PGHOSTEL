ALTER TABLE facility_party
    ADD COLUMN expected_checkout_date DATE NULL COMMENT 'Optional expected/planned checkout date set at assignment time';
