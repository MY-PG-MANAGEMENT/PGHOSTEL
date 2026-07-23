# Bulk-upload test data (with org + facility codes)

Reference "today" = **2026-07-06** (2026-04 = 3 months old, 2026-05 = 2 months old).

## Upload order (Admin Console -> Data Upload)
1. Select the target organization in the wizard (step 1).
2. Upload **facilities_200.csv** -> **creates the property `Sunrise PG` (code `PROP_104`)** plus
   5 floors, 120 rooms, **250 beds** (each with `floor_code` / `room_code` / `bed_code`).
   No need to pre-create the property — the upload now creates it.
3. Upload **tenants_200.csv** -> creates tenants, assigns beds, backfills paid history.

## Facility codes
- The property is created with code `PROP_104`; every floor/room/bed carries an explicit code
  (`FL-<floor>`, `RM-<room#>`, `BED-<room#>-<bed>`, e.g. `FL-G`, `RM-G01`, `BED-G01-A`, `BED-101-1`).
- Codes both match an existing node AND set the node's code on create; re-upload is idempotent.
- Tenant assignment resolves each level by **code or name**: `property_code`/`floor_code`/`room_code`/`bed_code`
  (a `bed_code` resolves the bed directly).

## tenants_200.csv  (213 rows)
- **100 tenants assigned CODE-wise** (only `bed_code` set, name columns blank) and
  **100 assigned NAME-wise** (property/floor/room/bed set) — both paths are exercised.
- Move-ins spread 2026-01..2026-06 (weighted to 3-2 months old); backfill pattern by index%5:
  blank (PENDING) / 2026-05 (current dues open) / 2026-06 (paid through last month).
- Payment method rotates CASH/UPI/BANK; ~1/3 own a vehicle; AC rooms carry `ac_charges`.

### Corner cases (rows 201-212)
| Row | Tests | Expected |
|---|---|---|
| Corner NoBed | no assignment | tenant only, no billing |
| Corner DupMobile | reuse mobile 9000000001 | 2nd person created (no dedup) |
| Corner BadMobile | mobile `12345` | **row FAILS** |
| (blank name) | empty full_name | **row FAILS** |
| Corner OccupiedBed | G01/Bed 1 already taken | created, "Bed already occupied" |
| Corner BadBed | Room 999/Bed Z | created, "Bed not found" |
| Corner WrongProperty | property Nonexistent PG | created, "Bed not found" |
| Corner AcRoom | AC + full backfill, 3-mo-old | invoices itemize Rent+AC+Deposit, PAID |
| Corner VehicleYes | has_vehicle=`yes` | truthy parse, assigned |
| Corner PendingDues | 3-mo-old, no backfill | single PENDING move-in invoice |
| Corner ByCode | assign via `bed_code` only | **code-wise assign succeeds** |
| Corner BadCode | bed_code `BED-NOPE-9` | created, **"Bed not found"** (by code) |
| Corner CodePath | property_code + floor_code + room_code + bed_name | **code-path assign succeeds** |

**Expected result:** totalRows 213, created 211, failed 2 (BadMobile + blank name),
plus row errors for OccupiedBed / BadBed / WrongProperty / BadCode (assignment skipped, tenant kept).
