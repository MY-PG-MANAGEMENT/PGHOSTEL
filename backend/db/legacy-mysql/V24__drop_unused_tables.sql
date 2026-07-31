-- V24: Drop dead-weight schema objects.
--
-- These 15 tables and 4 views are created by earlier migrations (mostly the V3
-- "full application schema" and V4 "phase 2 enhancements") but are NEVER
-- referenced anywhere in backend/src/main/java -- no JPA @Entity mapping and no
-- raw JdbcTemplate SQL. They are an over-provisioned data model whose features
-- were never wired up. Verified by a full-tree usage audit.
--
-- Two of them (content_reference, payment_method_type) have an incoming FK from
-- a LIVE table, so they are handled at the end: we first drop the FK and the
-- now-orphan column on identity_document / payment, then drop the table.
-- Safety verified:
--   * identity_document is JdbcTemplate-only (no JPA entity) and never names the
--     content_reference_id column in code.
--   * The Payment @Entity maps payment_mode, NOT payment_method_type; the column
--     is unmapped, so dropping it does not affect Hibernate ddl-auto=validate.

-- Views (no dependents) -------------------------------------------------------
DROP VIEW IF EXISTS facility_occupancy_summary;
DROP VIEW IF EXISTS pending_payment_summary;
DROP VIEW IF EXISTS monthly_revenue_by_property;
DROP VIEW IF EXISTS tenant_occupancy_history;

-- contact_mech cluster: drop children (FK -> contact_mech) before the parent ---
DROP TABLE IF EXISTS postal_address;
DROP TABLE IF EXISTS party_contact_mech;
DROP TABLE IF EXISTS facility_contact_mech;
DROP TABLE IF EXISTS contact_mech;

-- Self-contained dead tables (no incoming FK from any retained table) ----------
DROP TABLE IF EXISTS room_photo;
DROP TABLE IF EXISTS recurring_charge;
DROP TABLE IF EXISTS plan_feature;
DROP TABLE IF EXISTS party_role;
DROP TABLE IF EXISTS status_type;
DROP TABLE IF EXISTS login_history;
DROP TABLE IF EXISTS analytics_cache;
DROP TABLE IF EXISTS activity_log;
DROP TABLE IF EXISTS payment_receipt;

-- FK-entangled reference tables: drop the FK + orphan column on the live table,
-- then drop the reference table. MySQL has no IF EXISTS for DROP FOREIGN KEY /
-- DROP COLUMN; names are exactly as created (fk_identity_content in V3,
-- fk_payment_method_type in V4).

-- content_reference <- identity_document
ALTER TABLE identity_document DROP FOREIGN KEY fk_identity_content;
ALTER TABLE identity_document DROP COLUMN content_reference_id;
DROP TABLE IF EXISTS content_reference;

-- payment_method_type <- payment
ALTER TABLE payment DROP FOREIGN KEY fk_payment_method_type;
ALTER TABLE payment DROP COLUMN payment_method_type;
DROP TABLE IF EXISTS payment_method_type;
