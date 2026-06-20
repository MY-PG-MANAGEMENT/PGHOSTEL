# Database Schema

PG Manager uses a pragmatic Apache OFBiz-style model while retaining numeric identifiers, JPA, and Flyway.

## Core model

- `party`, `person`, `party_role`, and contact mechanisms represent people and their effective-dated roles.
- `facility` represents organizations, properties, floors, rooms, and beds. `facility_group_member` stores hierarchy.
- `facility_party` stores organization membership and effective-dated bed occupancy.
- Type/status tables and role permissions replace ungoverned UI strings where lifecycle or authorization depends on the value.

## Application domains

- Inventory: facility addresses, amenities, pricing, availability, and future-ready `content_reference` metadata.
- Tenancy: employment, emergency contacts, ID metadata, admissions, agreements, checkout, and deposit settlement.
- Billing: accounts, recurring charges, invoices/items, payments, allocations, advances, refunds, and receipts.
- Experience: notifications, recipient read/archive state, channel preferences, outbox, and user preferences.
- Platform: plans/features, organization subscriptions, system settings, user devices, login history, and audit data.

Images and identity files are not stored in v1. A content record remains `STORAGE_DISABLED` until a private object-storage adapter is configured.

## Compatibility

Migration `V3__full_application_schema.sql` is additive. It retains `rent` and `payment`, creates normalized billing accounts/invoices, and backfills legacy rent/payment rows. Legacy endpoints can remain live while clients move to `/api/billing/**`.

Editable ER sources live in [`docs/er`](er/).

