# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Layout

- `backend/` — Spring Boot 3.3.5 / Java 21 / Gradle modular-monolith API
- `owner_app/` — Flutter owner mobile + responsive web app
- `docs/` — Architecture, API, database schema, and implementation notes

## Backend

### Commands (run from `backend/`)

```bash
./gradlew bootRun          # start dev server on :8080
./gradlew test             # run all tests (Testcontainers spins up MySQL)
./gradlew test --tests "com.pgmanager.SomeTest"   # run a single test class
./gradlew build            # full build + tests
```

Swagger UI is at `http://localhost:8080/swagger-ui.html`.

### Configuration

`src/main/resources/application.yml` — expects local MySQL on port 3306, database `pg_manager`, user `root`/`root`. JWT secret and token lifetimes (`access-token-minutes: 30`, `refresh-token-days: 14`) live under `app.security`.

### Database Migrations

Flyway migrations in `src/main/resources/db/migration/`. Always add new migrations as `V<n>__description.sql` — never edit existing ones. `ddl-auto` is `validate`, so Hibernate rejects schema drift.

### Package Structure

Each feature is a self-contained package under `com.pgmanager`. Cross-cutting concepts:

**`party` + `facility` — the two backbone models**

- `party` is a generic actor (PERSON or future ORGANIZATION). `person` holds human details with a 1:1 FK to `party`.
- `facility` is a single polymorphic table covering the full hierarchy: ORGANIZATION → PROPERTY → FLOOR → ROOM → BED. The `facility_type_id` column distinguishes levels. String constants live in `FacilityType`. Parent–child relationships are in `facility_group_member` (dated, allowing history). An owner's organization is itself a `Facility` row with `facility_type_id = ORGANIZATION`.
- `Facility` carries an optimistic-locking `@Version long version` field — always save through the repository to avoid version conflicts.
- `FacilityService.link(parentId, childId)` creates `FacilityGroupMember` records; always call it when attaching a new node to the tree.

**`facility_party` — the occupancy/membership join table**

- Links a `party` to a `facility` with a role and a date range (`from_date` / `thru_date`). Active bed assignments have a null `thru_date`.
- When a tenant is created, **two** `FacilityParty` rows are written: one with `facilityId = organizationId` (role `TENANT`, org-level membership) and one with `facilityId = propertyId` (role `TENANT`, property-scoped). The `TenantService.list()` query filters on `facilityId = organizationId` to avoid duplicating tenants. The bed-level role is `OCCUPANT`.
- `OccupancyRole` holds the string constants (`TENANT`, `OCCUPANT`).
- `OccupancyService.assign` also calls `ensurePropertyTenantMembership` so tenants assigned via the global bed-assign flow still appear in property-scoped lists.

**`security`**

- `JwtAuthenticationFilter` extracts the JWT on every request and populates `AppUserPrincipal` (contains `userLoginId`, `organizationId`, `roleTypeId`).
- Inject `CurrentUser` (not `SecurityContextHolder` directly) in controllers/services — it exposes `.organizationId()` and `.userLoginId()` with built-in null checks.
- Role URL guards live in `SecurityConfig`; fine-grained guards use `@PreAuthorize`.
- `RoleType` constants: `SUPER_ADMIN`, `OWNER`, `PROPERTY_MANAGER`, `MANAGER`, `ACCOUNTANT`, `SUPPORT`, `VIEWER`, `TENANT`.
- All owner business APIs must derive `organizationId` from `CurrentUser` — never accept an org ID from the request body.

**`billing`**

- `BillingController` is intentionally implemented with raw `JdbcTemplate` (not JPA entities). Invoice generation, payment collection, payment allocation, and the billing dashboard all run as direct SQL to keep aggregate queries simple. Other packages should continue using JPA.
- Payments support an `idempotency_key` column — pass a client-generated UUID to make payment collection safe to retry.

**`rent`**

- `Rent` entity records a monthly charge per tenant (`rentMonth`, `monthlyRent`, `deposit`, `advance`, `discount`, `penalty`). `Rent.totalDue()` computes the total owed; `paidAmount` tracks what has been collected. `RentService` validates the tenant's org membership before saving.

**`payment`**

- `PaymentController` / `PaymentService` record standalone payments (JPA-based, unlike billing). Separate from `BillingController`'s payment-collection flow.

**`tenant` lifecycle sub-resources**

- `TenantLifecycleController` (mapped to `/api/tenants/{partyId}/…`) handles sub-resources that are too granular for JPA entities: emergency contacts, employment history, documents, and convenience assign/checkout endpoints. It uses `JdbcTemplate` directly (same rationale as `BillingController`).

**`notification`**

- `NotificationController` is JdbcTemplate-based. Stores per-user notifications in a `notification` table; exposes list, mark-read, and delete endpoints.

**`feature`**

- `feature_master` seeds available feature codes; `organization_feature` stores which features an org has enabled. The `OnboardingService` activates features during the wizard run.

**`admin`**

- `SuperAdminController` is gated to `SUPER_ADMIN` role and handles cross-org operations.

**`dashboard`**, **`settings`**, **`subscription`**

- Self-contained packages for their respective concerns; follow the same JPA + `ApiResponse<T>` convention unless they involve aggregation (in which case JdbcTemplate may be used, as in `FacilityController`'s `/vacant-beds` and `/room-summary` endpoints).

**Common patterns**

- All controllers return `ApiResponse<T>` (`{ success, message, data }`).
- Entities extend `BaseEntity` (provides `createdAt`, `updatedAt` via JPA auditing).
- `GlobalExceptionHandler` maps `NotFoundException` → 404, `BadRequestException` → 400.
- Refresh tokens are stored as SHA-256 hashes (`HashUtil.sha256`); raw tokens are never persisted.
- `AuditService.log(organizationId, userLoginId, eventType, entityType, entityId, description)` should be called for significant state changes.

### Owner registration flow

`AuthService.registerOwner` creates: `Party` → `Person` → `Facility(ORGANIZATION)` → `UserLogin(role=OWNER)`. The organization's `facilityId` doubles as its `organizationId` throughout the system.

### Rent resolution for bed assignment

When assigning a bed without an explicit rent, `OccupancyService.resolveRent` walks up the `facility_group_member` tree (BED → ROOM → FLOOR → PROPERTY) and looks up `PropertySharingPrice` by `(organizationId, propertyId, room.sharingType)`.

### JdbcTemplate usage pattern

JdbcTemplate is used in several places for complex or aggregate queries that are awkward with JPA:
- `BillingController` — all billing/invoice/payment aggregate queries
- `TenantLifecycleController` — emergency contacts, employment, documents
- `NotificationController` — notifications
- `FacilityController` — `/vacant-beds` (UNION query for vacant + upcoming) and `/room-summary`

For everything else, use JPA repositories.

## Flutter Owner App

### Commands (run from `owner_app/`)

```bash
flutter run                    # run on connected device/emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api   # Android emulator
flutter test                   # run all widget/unit tests
flutter build apk              # Android release APK
flutter analyze                # lint
```

Default API base URL in `ApiClient` is `http://192.168.1.33:8080/api` (hardcoded local IP). Override with `--dart-define=API_BASE_URL=<url>`.

### Architecture

**State management** — single `AppState extends ChangeNotifier` (Provider, provided at root). It owns `ApiClient` and `AuthRepository`, holds `isLoggedIn` and `roleTypeId`. The `GoRouter` is constructed inside the `Consumer<AppState>` builder so route guards react to state changes.

**Navigation** — `go_router` with a redirect guard: `/` dispatches to `/dashboard` (or `/admin` for SUPER_ADMIN) when logged in, or to `/login` when not. SUPER_ADMIN users are locked to `/admin`. Key routes: `/onboarding`, `/properties`, `/tenants`, `/occupancy`, `/rents`, `/billing`, `/settings`.

**API layer**

- `ApiClient` — HTTP wrapper that injects `Authorization: Bearer` from `FlutterSecureStorage`. On 401, it automatically calls `/auth/refresh` and retries the request once before giving up. Response unwrapping: returns `body['data']` on success, throws `Exception(body['message'])` on `success: false` or 4xx/5xx.
- `AuthRepository` — wraps `/auth/login` and `/auth/register-owner`, persists `accessToken`, `refreshToken`, `organizationId`, and `roleTypeId` to secure storage.

**Layout** — `AppShell` provides responsive chrome: sidebar nav at ≥900 px width, bottom `NavigationBar` + `Drawer` below that.

**Property workspace** — `PropertyWorkspaceScreen` is a per-property tabbed view (Tenants / Billing / Rooms) reached by tapping a property card. It shares `AssignBedSheet` from `room_screen.dart`.

**Biometric** — `AppState.setBiometricEnabled` / `biometricLogin` use `local_auth`. When biometric is enabled, `restoreSession` leaves `isLoggedIn = false` even if a token is present, forcing fingerprint/PIN unlock.

## Multi-tenancy

Shared-database multi-tenancy. Each organization is a `Facility(ORGANIZATION)`. Every business table carries `organization_id`. The backend enforces org scope from the JWT principal via `CurrentUser`.
