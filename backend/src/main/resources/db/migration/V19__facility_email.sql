-- Contact email on facility. For ORGANIZATION rows this is the sender ("From")
-- address used for outbound tenant emails. Nullable in the DB (existing orgs have
-- none); mandatory only at organization-creation time, enforced in the API layer.
ALTER TABLE facility ADD COLUMN email VARCHAR(160) NULL;
