# Database Schema

The schema intentionally avoids separate master tables for organization, property, floor, room, bed, tenant, and bed allocation.

## Core Generic Tables

- `facility`: stores `ORGANIZATION`, `PROPERTY`, `FLOOR`, `ROOM`, and `BED`.
- `facility_group_member`: stores the hierarchy between facilities.
- `party`: generic party identity.
- `person`: person details for owners and tenants.
- `user_login`: credentials and role.
- `facility_party`: effective-dated relationships between a party and facility.

## Business Tables

- `rent`: monthly rent, deposit, advance, discount, penalty, paid amount, status.
- `payment`: manual payment records by cash, UPI, bank transfer, or card.
- `audit_log`: operational activity logging.

## Future-Ready Tables

- `feature_master`: supported feature codes.
- `organization_feature`: per-organization feature enablement.
- `subscription`: organization subscription plan/status.

## Facility Hierarchy

```text
ORGANIZATION
  PROPERTY
    FLOOR
      ROOM
        BED
```

This hierarchy is stored with `facility_group_member`, not with separate parent columns for each level.

## Occupancy

Bed assignment is represented by:

```text
facility_party.facility_id = BED_ID
facility_party.party_id = TENANT_PARTY_ID
facility_party.role_type_id = OCCUPANT
facility_party.from_date = start date
facility_party.thru_date = checkout or transfer end date
```

Transfer closes the current active row and creates a new active row.
