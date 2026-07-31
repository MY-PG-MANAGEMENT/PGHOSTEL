-- V23: Composite indexes on facility_party for the tenant-list hot paths.
--
-- facility_party previously had only single-column indexes (organization_id,
-- facility_id, party_id — see V1). Every tenant-list query filters on a
-- combination of (organization_id, facility_id|party_id, role_type_id, thru_date),
-- so MySQL could use only one column and filtered the rest in memory. These
-- covering composites let the planner satisfy each predicate from the index.

-- findTenantsAtFacility(org, facility, role) + ensureBedAvailable / occupancy lookups
-- by (org, facility, role, active?): org-level & property-level TENANT lists, bed-occupied checks.
CREATE INDEX idx_fp_org_facility_role_thru
    ON facility_party (organization_id, facility_id, role_type_id, thru_date);

-- findActiveOccupantsByPartyIds / findByOrganizationIdAndPartyId...Role(...) : the batched
-- per-party occupant/temp lookups that build each tenant row.
CREATE INDEX idx_fp_org_party_role_thru
    ON facility_party (organization_id, party_id, role_type_id, thru_date);

-- Refresh planner statistics so the new indexes are used immediately.
ANALYZE TABLE facility_party;
