-- Extend person table with richer profile fields needed by owner app
ALTER TABLE person
    ADD COLUMN email                       VARCHAR(120)  NULL AFTER mobile_number,
    ADD COLUMN permanent_address           VARCHAR(500)  NULL AFTER address,
    ADD COLUMN emergency_contact_name      VARCHAR(120)  NULL AFTER guardian_mobile_number,
    ADD COLUMN emergency_contact_mobile    VARCHAR(10)   NULL AFTER emergency_contact_name,
    ADD COLUMN emergency_contact_relation  VARCHAR(60)   NULL AFTER emergency_contact_mobile,
    ADD COLUMN employer_name               VARCHAR(200)  NULL AFTER company_name,
    ADD COLUMN designation                 VARCHAR(120)  NULL AFTER employer_name,
    ADD COLUMN work_address                VARCHAR(500)  NULL AFTER designation;
