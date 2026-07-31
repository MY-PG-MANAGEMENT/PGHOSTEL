# Legacy MySQL migrations (V1–V31)

These are the original Flyway migrations from when PG Manager ran on MySQL 8.4.
They are kept **unmodified**, as a historical record of how the schema evolved and
why — several carry design rationale in their comments that is not repeated
anywhere else.

**They are not on the classpath and Flyway never reads them.** Flyway scans
`classpath:db/migration`, which now contains a single consolidated PostgreSQL
baseline (`V1__baseline.sql`) representing the net schema these 31 files produced
— that is, after `V24` dropped 15 dead tables plus 4 views and `V29` dropped
`subscription_plan`.

Do not add files here and do not edit these. New schema changes go to
`src/main/resources/db/migration` as `V<n>__description.sql`, in PostgreSQL
syntax, starting from V2.

## Why the history was not ported file-by-file

A MySQL `flyway_schema_history` table cannot be carried across to PostgreSQL, so
replaying the sequence would have bought nothing: every environment starts from an
empty PostgreSQL database and applies the baseline in one step. Porting 31 files
would also have meant translating DDL that later files in the same sequence undo.

## Reading these against the baseline

| Looking for | Legacy file |
|---|---|
| Original core schema | `V1__init_schema.sql` |
| The large "full application" extension | `V3__full_application_schema.sql` |
| Mobile-uniqueness reversal (global → property-scoped) | `V10`, `V12` |
| Bed transfer / temp stay | `V13` |
| Expenses, staff | `V16`, `V17` |
| Tenant login, complaints, notices | `V22` |
| The two `facility_party` composite indexes and why | `V23` |
| What was dropped as dead weight, and the safety audit | `V24`, `V29` |
| Billing automation config | `V26`, `V27` |
| Tenant archive | `V28` |
| API request log | `V30` |
| Platform per-tenant pricing | `V31` |
