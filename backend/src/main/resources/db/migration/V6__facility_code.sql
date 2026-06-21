-- Add human-readable facility code column (nullable so application can set it after insert)
ALTER TABLE facility
    ADD COLUMN facility_code VARCHAR(30) NULL AFTER facility_id;

-- Backfill all existing rows
UPDATE facility
SET facility_code = CONCAT(
    CASE facility_type_id
        WHEN 'ORGANIZATION' THEN 'ORG'
        WHEN 'PROPERTY'     THEN 'PROP'
        WHEN 'FLOOR'        THEN 'FLR'
        WHEN 'ROOM'         THEN 'ROOM'
        WHEN 'BED'          THEN 'BED'
        ELSE 'FAC'
    END,
    '_', facility_id
);

ALTER TABLE facility
    ADD CONSTRAINT uq_facility_code UNIQUE (facility_code);

-- Normalize sharing_type to numeric strings (1–6) for consistency
UPDATE facility SET sharing_type = '1' WHERE sharing_type = 'SINGLE';
UPDATE facility SET sharing_type = '2' WHERE sharing_type = 'DOUBLE';
UPDATE facility SET sharing_type = '3' WHERE sharing_type = 'TRIPLE';
UPDATE facility SET sharing_type = '4' WHERE sharing_type = 'QUAD';
UPDATE facility SET sharing_type = NULL  WHERE sharing_type = 'DORMITORY';
