-- The composite indexes on facility_party, facility_group_member, facility, rent, payment, and invoice
-- were already created in earlier migrations (V3–V8). No new indexes are needed.
-- Update table statistics so MySQL query planner uses the existing indexes optimally.
ANALYZE TABLE facility_party;
ANALYZE TABLE facility_group_member;
ANALYZE TABLE facility;
ANALYZE TABLE rent;
ANALYZE TABLE payment;
ANALYZE TABLE invoice;
