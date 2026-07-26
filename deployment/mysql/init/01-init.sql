-- =============================================================================
-- One-time database initialisation.
--
-- The official MySQL entrypoint runs every *.sql in /docker-entrypoint-initdb.d
-- EXACTLY ONCE — on the very first start, while the data directory is empty. It is
-- never re-run, so editing this file after the first boot has no effect. To apply a
-- change here you must destroy the mysql_data volume, which destroys the database.
--
-- IMPORTANT: this file does NOT create tables. Flyway owns the schema
-- (backend/src/main/resources/db/migration, currently through V31) and runs at
-- application startup with ddl-auto=validate. Creating anything here would drift
-- from the migration history and cause Hibernate's schema validation to fail on boot.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Character set.
--
-- MYSQL_DATABASE is created by the entrypoint before this script runs, using the
-- server default. That default is already utf8mb4 on 8.4, so this is belt-and-braces
-- — but it makes the requirement explicit and survives someone changing the server
-- default later. Free-form tenant names, complaint bodies and notice text all need
-- 4-byte support; the legacy 3-byte `utf8` truncates at the first emoji.
-- ---------------------------------------------------------------------------
ALTER DATABASE `pg_manager`
    CHARACTER SET = utf8mb4
    COLLATE = utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Application account.
--
-- The entrypoint has already created MYSQL_USER@'%' with ALL PRIVILEGES on
-- MYSQL_DATABASE. That grant is correct and is deliberately left alone:
--
--   * Flyway needs full DDL (CREATE, ALTER, DROP, INDEX, CREATE VIEW) to apply
--     migrations at startup, so a SELECT/INSERT/UPDATE/DELETE-only account cannot
--     boot the application.
--   * The grant is scoped to this one schema. The account has no privileges on
--     `mysql`, `sys`, `performance_schema`, and no global privileges (SUPER, FILE,
--     PROCESS, SHUTDOWN), so it cannot read other databases, write files on the
--     host, or see other sessions' queries.
--
-- What it must NOT have, and does not: GRANT OPTION. Without it a compromised
-- application account cannot escalate its own privileges or create new users.
--
-- The statement below is a no-op re-assertion that documents the intended surface.
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE,
      CREATE, ALTER, DROP, INDEX, REFERENCES,
      CREATE VIEW, SHOW VIEW,
      CREATE TEMPORARY TABLES, LOCK TABLES,
      EXECUTE
    ON `pg_manager`.*
    TO 'pgmanager'@'%';

-- ---------------------------------------------------------------------------
-- NOTE on the hardcoded names above.
--
-- MySQL cannot interpolate environment variables into a .sql file, so `pg_manager`
-- and `pgmanager` are literals. They must match MYSQL_DATABASE and MYSQL_USER in
-- .env. If you change either variable, change it here too — otherwise this script
-- fails on first boot and the entrypoint aborts the whole initialisation, leaving
-- you with a half-built data directory that must be deleted before retrying.
-- ---------------------------------------------------------------------------

FLUSH PRIVILEGES;
