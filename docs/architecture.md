# Architecture Overview

PG Manager is a lightweight owner-first PG/Hostel Management SaaS.

## Phase 1 Scope

- Spring Boot backend APIs.
- Flutter Owner App.
- Shared MySQL database.
- Organization-scoped multi-tenancy.
- Owner workflows for setup, tenant management, occupancy, rent, payment, and dashboard.

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
- `rent`: rent/deposit/advance/discount/penalty tracking.
- `payment`: manual payment recording.
- `dashboard`: owner summary APIs.
- `feature`: future feature toggles.
- `subscription`: future subscription support.
- `audit`: audit logging foundation.

## Multi-Tenancy

The first version uses shared-database multi-tenancy. Organization is represented as a `Facility` row with `facility_type_id = ORGANIZATION`.

All owner business APIs derive `organizationId` from the authenticated user. Clients should not be trusted to choose organization scope for owner actions.

## Future Readiness

The schema reserves roles, subscriptions, feature toggles, and audit logging from phase 1 so super-admin functionality can be added later without changing the core data model.
