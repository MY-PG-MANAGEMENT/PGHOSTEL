-- V12: Remove global mobile uniqueness constraint.
-- Mobile number uniqueness is now enforced per-property in application code:
-- the same mobile may appear as an active tenant in different properties.
ALTER TABLE person DROP INDEX uk_person_mobile;
