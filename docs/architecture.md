# Architecture Overview

PG Manager is a lightweight owner-first PG/Hostel Management SaaS.

## Product Scope

- Spring Boot backend APIs.
- Flutter Owner App.
- Shared MySQL database.
- Organization-scoped multi-tenancy.
- Owner workflows for setup, inventory, tenant lifecycle, billing, notifications, settings, and analytics.
- A responsive Flutter Super Admin workspace using the same API and design system.

## Backend Style

The backend is a modular monolith. Each feature is isolated by package while sharing one deployment and one database.

Packages:

- `auth`: owner registration, login, refresh tokens.
- `security`: JWT, role gates, current user context.
- `party`: generic party/person model.
- `facility`: generic organization/property/floor/room/bed hierarchy.
- `onboarding`: owner setup wizard.
- `tenant`: tenant onboarding and profile management.
- `occupancy`: bed assignment, transfer, checkout, history.
- `billing`: invoices, allocations, cash payments, advances, receipts, and refunds.
- `notification`: in-app delivery and provider-neutral future outbox.
- `settings`: profile, device security, and user preferences.
- `admin`: plans, organizations, roles, reporting, audit, and platform settings.
- `dashboard`: owner summary APIs.
- `feature`: future feature toggles.
- `subscription`: future subscription support.
- `audit`: audit logging foundation.

## Multi-Tenancy

The first version uses shared-database multi-tenancy. Organization is represented as a `Facility` row with `facility_type_id = ORGANIZATION`.

All owner business APIs derive `organizationId` from the authenticated user. Clients should not be trusted to choose organization scope for owner actions.

## External Adapter Boundaries

- Online payment provider fields and webhook/idempotency contracts exist, but only cash is enabled.
- WhatsApp outbox/provider fields exist, but only in-app delivery is enabled.
- Content references exist, but upload/view actions remain disabled until private object storage is configured.
- Biometric data never leaves the device; the backend stores only device enrollment metadata.
