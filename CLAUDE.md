# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Layout

- `backend/` — Spring Boot 3.3.5 / Java 21 / Gradle modular-monolith API
- `owner_app/` — Flutter owner mobile + responsive web app
- `docs/` — Architecture, API, database schema, and implementation notes

## Backend

### Commands (run from `backend/`)

> `backend/bin/` is Gradle build output (compiled classes). It is gitignored via `backend/bin/main/.gitignore` and should never be committed.

```bash
./gradlew bootRun          # start dev server on :8080 (Git Bash / macOS / Linux)
.\gradlew.bat bootRun      # start dev server on :8080 (Windows cmd/PowerShell)
./gradlew test             # run all tests (unit/web-slice tests run everywhere; Testcontainers-based integration tests auto-skip when Docker is absent — see docs/TEST_PLAN.md)
./gradlew test --tests "com.pgmanager.SomeTest"   # run a single test class
./gradlew build            # full build + tests
```

Swagger UI is at `http://localhost:8080/swagger-ui.html`.

### Configuration

`src/main/resources/application.yml` — expects local MySQL on port 3306, database `pg_manager`, user `root`/`root`. JWT secret and token lifetimes (`access-token-minutes: 30`, `refresh-token-days: 14`) live under `app.security`. `app.public-base-url` (env `APP_PUBLIC_BASE_URL`, default a LAN IP) is the origin the tenant self check-in QR points to — it must be reachable from the tenant's phone.

`@EnableScheduling` is active on `PgManagerApplication` — `RentReminderScheduler` fires daily at 09:00 (cron `0 0 9 * * *`) to dispatch rent-due, checkout, payment-receipt, and check-in notifications.

### Database Migrations

Flyway migrations in `src/main/resources/db/migration/`. Always add new migrations as `V<n>__description.sql` — never edit existing ones. `ddl-auto` is `validate`, so Hibernate rejects schema drift (adding an entity field requires a matching migration or startup fails). Current latest is V17 (`V17__staff.sql`).

Notable migration changes:
- V10 — adds `UNIQUE KEY uk_person_mobile` on `person.mobile_number` (global, not org-scoped) and creates `bulk_upload_job` tracking table
- V11 — seeds `notification_category` rows: `RENT_REMINDER`, `CHECKOUT_REMINDER`, `PAYMENT_RECEIPT`, `CHECK_IN`, `GENERAL`
- V12 — switches mobile uniqueness from global to property-scoped (drops `uk_person_mobile`); uniqueness now enforced in app code per-property
- V13 — creates `scheduled_bed_transfer` (deferred sharing-change transfers)
- V14 — adds `facility.is_ac` (`TINYINT(1)`) and `property_sharing_price.ac_charges`
- V15 — adds `person.has_vehicle` (`TINYINT(1)`); boolean flags use `TINYINT(1) NOT NULL DEFAULT 0` mapped to a primitive `boolean`
- V16 — creates `expense`, `expense_budget`, `petty_cash_entry` (expenses module; deliberately no category/vendor/approval tables — see `docs/EXPENSES_SCHEMA_MAPPING.md`)
- V17 — creates `staff` and `staff_salary_payment` (staff management; deliberately not party/person-based — staff have no logins; `uk_staff_pay_month` is the double-payment guard)

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
- `OccupancyRole` holds the string constants (`TENANT`, `OCCUPANT`, `TEMP_OCCUPANT`).
- `OccupancyService.assign` also calls `ensurePropertyTenantMembership` so tenants assigned via the global bed-assign flow still appear in property-scoped lists.

**Bed transfer rules (`OccupancyService.transfer`, `POST /api/occupancy/transfer-bed`)** — returns a `TransferResult` (`mode` = `APPLIED` or `SCHEDULED`):
- **Same sharing type** → applied immediately; the new occupancy row carries the *original* `from_date` so the billing cycle/day and rent are unchanged.
- **Different sharing type** → never applied mid-cycle. A `scheduled_bed_transfer` (PENDING) is written with `effective_date` = the tenant's next billing anniversary; the swap + new rent are applied on that date by `BedTransferScheduler` (`@Scheduled` daily, applies `applyDueTransfers()`). The current month's invoice is untouched. A bed with a PENDING transfer is excluded from `/vacant-beds`. Cancel via `DELETE /api/occupancy/scheduled-transfers/{id}`; list via `GET /api/occupancy/scheduled-transfers/{partyId}`.

**Temporary stay (`TEMP_OCCUPANT`)** — `POST /api/occupancy/temp-stay` places a tenant in a bed with **no billing** (invoice generation only ever reads `OCCUPANT` rows). `POST /temp-stay/end` (move back) closes it; `POST /temp-stay/make-permanent` ends the temp stay and runs the normal assign + first-invoice (billing starts). Temp-occupied beds are excluded from `/vacant-beds`. Tenant detail (`GET /api/tenants/{id}`) exposes `currentSharingType`, `inTemporaryStay`, `tempBedFacilityId`, `tempBedName` for the Flutter `TransferBedSheet` and tenant-detail banners.

**`security`**

- `JwtAuthenticationFilter` extracts the JWT on every request and populates `AppUserPrincipal` (contains `userLoginId`, `organizationId`, `roleTypeId`).
- Inject `CurrentUser` (not `SecurityContextHolder` directly) in controllers/services — it exposes `.organizationId()` and `.userLoginId()` with built-in null checks.
- Role URL guards live in `SecurityConfig`; fine-grained guards use `@PreAuthorize`. `/api/auth/**` and `/api/public/**` are `permitAll` (no auth) — the self check-in endpoints live under `/api/public/**`, and the forgot/reset-password flow (`PublicAccountController`, settings package) at `/api/auth/password/{forgot,reset}`.
- `JwtAuthenticationFilter` skips requests with no `Bearer` token (so public endpoints work); it never rejects, it just leaves the context unauthenticated.
- `RoleType` constants: `SUPER_ADMIN`, `OWNER`, `PROPERTY_MANAGER`, `MANAGER`, `ACCOUNTANT`, `SUPPORT`, `VIEWER`, `TENANT`.
- All owner business APIs must derive `organizationId` from `CurrentUser` — never accept an org ID from the request body.
- JWT claims include: `userLoginId` (Long), `partyId` (Long), `organizationId` (Long), `roleTypeId` (String). Refresh tokens are stored as SHA-256 hashes (`HashUtil.sha256`); raw tokens are never persisted.

**`billing`**

- `BillingController` is intentionally implemented with raw `JdbcTemplate` (not JPA entities). Invoice generation, payment collection, payment allocation, and the billing dashboard all run as direct SQL to keep aggregate queries simple. Other packages should continue using JPA.
- Payments support an `idempotency_key` column — pass a client-generated UUID to make payment collection safe to retry.

**`rent`**

- `Rent` entity records a monthly charge per tenant (`rentMonth`, `monthlyRent`, `deposit`, `advance`, `discount`, `penalty`). `Rent.totalDue()` computes the total owed; `paidAmount` tracks what has been collected. `RentService` validates the tenant's org membership before saving.

**`payment`**

- `PaymentController` / `PaymentService` record standalone payments (JPA-based, unlike billing). Separate from `BillingController`'s payment-collection flow.

**`tenant` lifecycle sub-resources**

- `TenantLifecycleController` (mapped to `/api/tenants/{partyId}/…`) handles sub-resources that are too granular for JPA entities: emergency contacts, employment history, documents, and convenience assign/checkout endpoints. It uses `JdbcTemplate` directly (same rationale as `BillingController`).

**`expense`**

- `ExpenseController` (`/api/expenses`) is JdbcTemplate-based (same rationale as billing). `GET /dashboard?propertyId=&month=` returns every section the Flutter expenses screen renders in one round-trip: summary (incl. MoM change %), category breakdown, category budgets vs spend, 6-month expense/income/profit trend (income = `RECEIVED` payments), pending approvals, recent transactions (whole dashboard month, `PENDING` included so a just-created expense shows immediately; summary/category totals stay `APPROVED`/`PAID` only), petty cash summary, and heuristic insights.
- Categories (`FOOD`, `SALARY`, `ELECTRICITY`, `MAINTENANCE`, `LAUNDRY`, `TRANSPORT`, `RENT`, `OTHERS`) and payment methods are string constants — no master tables. Approval is the `status` column (`PENDING`/`APPROVED`/`REJECTED`/`PAID`); only `PENDING` can transition. `POST /` creates `APPROVED` unless `requiresApproval: true`.
- Budget upsert (`PUT /budget`) uses sentinel scoping in `expense_budget`: `property_facility_id = 0` means org-wide, `category = 'ALL'` means the overall monthly budget (keeps the MySQL unique key enforceable).
- Approving a `CASH` expense auto-inserts a petty-cash `OUT` row linked via `expense_id` (idempotent); `POST /petty-cash` records manual `IN`/`OUT` entries. Balances are computed from the ledger, never stored. Full UI-to-SQL mapping: `docs/EXPENSES_SCHEMA_MAPPING.md`.

**`staff`**

- `StaffController` (`/api/staff`, JdbcTemplate, schema V17). `GET /?propertyId=&month=` returns staff joined with that month's salary payment plus a payroll summary (active count, monthly payroll, paid/due counts and totals). CRUD: `POST /` create, `PUT /{id}` update (incl. `status` ACTIVE/INACTIVE), `DELETE /{id}` soft-deactivates. `GET /{id}/payments` is the salary history (last 24 months).
- `POST /pay` bulk-pays `{staffIds, month, paymentMethod}`: per staff, insert into `staff_salary_payment` (unique `(staff_id, pay_month)` — duplicates and INACTIVE staff are skipped, not errors), then record a `SALARY` expense via `ExpenseWriter` and link it back through `expense_id`. Future months are rejected.
- `ExpenseWriter` (expense package) is the shared write path for approved expenses + the CASH → petty-cash `OUT` mirror; both `ExpenseController` and `StaffController` use it.

**`transaction`**

- `TransactionController` (`GET /api/transactions?propertyId=&month=`, JdbcTemplate) returns a unified money-in / money-out ledger for a month: `RECEIVED` payments (in) merged with `APPROVED`/`PAID` expenses (out), plus a summary (`totalIn`, `totalOut`, `net`, counts). Property scoping: payments via the tenant's property-level `TENANT` row in `facility_party` (payments carry no facility id); expenses via `property_facility_id`. Rendered by `transactions_screen.dart` (the "Transactions" quick action on the property workspace).

**`notification`**

- `NotificationController` is JdbcTemplate-based. Stores per-user notifications with a `notification_recipient` join table; list endpoint supports `state` filter (`ACTIVE`, `ARCHIVED`, `UNREAD`, `IMPORTANT`) with pagination (`page`, `size`). Also exposes mark-read, archive, toggle-important, and delete endpoints.
- `NotificationService` provides `createForOrg(organizationId, category, title, message, entityType, entityId, priority, recipientPartyIds)` — used both by business logic and the scheduler. Categories come from V11 seeds.
- `RentReminderScheduler` runs at 09:00 daily; queries tenants with overdue rent, upcoming checkouts, and recent payments then calls `NotificationService` for each event type.

**`feature`**

- `feature_master` seeds available feature codes; `organization_feature` stores which features an org has enabled. The `OnboardingService` activates features during the wizard run.

**`admin`**

- `SuperAdminController` (mapped to `/api/super-admin`) is gated to `SUPER_ADMIN` role. Endpoints: `GET /dashboard` (cross-org metrics + last 10 audit entries), `GET /organizations` (filterable by `?status=`), `POST /organizations` (provision a new organization + its OWNER login — delegates to `AuthService.createOwnerAccount` without logging the super admin out), `PATCH /organizations/{id}/status` (toggle org active/inactive), `POST /broadcast` (push a titled announcement to all org owners via `NotificationService`). Uses JdbcTemplate throughout (except org creation, which reuses the JPA-based `AuthService`).
- Owner self-registration was removed from the Flutter login screen; new organizations are created exclusively by super admins via `POST /organizations` (the admin panel's Organizations tab has a "New Organization" dialog). `AuthService.registerOwner` (and `POST /api/auth/register-owner`) still exist and wrap `createOwnerAccount`, but the owner app no longer exposes a `/register` route.
- `BulkUploadController` (mapped to `/api/super-admin/upload`). `GET /template/facilities` and `GET /template/tenants` return downloadable CSV templates. `POST /facilities` and `POST /tenants` accept `MultipartFile` CSV uploads parsed via Apache Commons CSV. Tenant upload uses find-or-create by `mobile_number` (enforced unique in V10) to avoid creating duplicate persons across orgs. Results tracked in `bulk_upload_job` table.

**`selfcheckin` — tenant self check-in via QR**

- `PublicSelfCheckinController` (`/api/public/self-checkin/{orgId}/{propertyId}/{sig}`, **no auth**) serves a self-contained HTML registration form (`GET`) and creates the tenant on submit (`POST`, form-urlencoded). It reuses `TenantService.create` — the *same* code path as the in-app Add Tenant flow — passing `userLoginId = null`. A `propertyId` of `0` means org-level (no property scope).
- `SelfCheckinTokenService` signs the `(orgId, propertyId)` pair (`sha256` of the ids + jwt-secret, truncated) so the URL ids cannot be swapped. `pathFor`/`linkFor` build the signed path.
- `TenantController` exposes the authenticated `GET /api/tenants/self-checkin-link?propertyId=` returning `{url, path}`. The Flutter app prepends **its own** `ApiClient.baseUrl` origin to `path` so the QR host always matches the backend the app is actually using (avoids `public-base-url` drift). `TenantCreateRequest`/`TenantUpdateRequest`/`TenantResponse` carry a primitive `boolean hasVehicle`.

**`dashboard`**, **`settings`**, **`subscription`**

- Self-contained packages for their respective concerns; follow the same JPA + `ApiResponse<T>` convention unless they involve aggregation (in which case JdbcTemplate may be used, as in `FacilityController`'s `/vacant-beds` and `/room-summary` endpoints).

**`facility` — InventoryController**

- `InventoryController` (separate from `FacilityController`) exposes read-only inventory views: `GET /api/inventory/properties/{propertyId}` (rooms with bed counts and occupancy stats) and `GET /api/inventory/rooms/{roomId}` (individual bed status including current occupant details). Uses JdbcTemplate for the aggregated joins.

**Common patterns**

- All controllers return `ApiResponse<T>` (`{ success, message, data }`).
- Entities extend `BaseEntity` (provides `createdAt`, `updatedAt` via JPA auditing).
- `GlobalExceptionHandler` maps: `NotFoundException` → 404, `BadRequestException` → 400, `MethodArgumentNotValidException` → 400 with aggregated field errors (`"field: msg, field2: msg2"`), `AccessDeniedException` → 403.
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

Default API base URL in `ApiClient` is a hardcoded local IP. Override with `--dart-define=API_BASE_URL=<url>` at build time.

### Architecture

**State management** — single `AppState extends ChangeNotifier` (Provider, provided at root). It owns `ApiClient` and `AuthRepository`, holds `isLoggedIn` and `roleTypeId`. The `GoRouter` is constructed inside the `Consumer<AppState>` builder so route guards react to state changes.

**Navigation** — `go_router` with a layered redirect guard evaluated in order:
1. Not yet initialized → stay on `/` (splash)
2. On `/` → go to `/dashboard` (OWNER) or `/admin` (SUPER_ADMIN) if logged in, else `/login`
3. Not logged in + on a protected route → `/login`
4. Logged in + on an auth route (login/register) → `/dashboard` or `/admin`
5. SUPER_ADMIN on any non-`/admin` route → `/admin`

Key routes: `/onboarding`, `/properties`, `/tenants`, `/billing`, `/expenses`, `/staff`, `/notifications`, `/settings`, `/dashboard/analytics`, `/admin`. Legacy paths redirect: `/tenants/manage` → `/tenants`, `/billing/manage` and `/payments` → `/billing`.

**API layer**

- `ApiClient` — HTTP wrapper that injects `Authorization: Bearer` from `FlutterSecureStorage`. On 401, it automatically calls `/auth/refresh` and retries the original request once before clearing storage and giving up. Response unwrapping: returns `body['data']` on success, throws `Exception(body['message'])` on `success: false` or 4xx/5xx.
- `AuthRepository` — wraps `/auth/login` and `/auth/register-owner`, persists `accessToken`, `refreshToken`, `organizationId`, and `roleTypeId` to secure storage.

**Layout** — `AppShell` provides responsive chrome: sidebar nav at ≥900 px width, bottom `NavigationBar` + `Drawer` below that.

**Screen consolidation** — `account_screens.dart` groups several screens in one file: Dashboard, Analytics, Notifications, NotificationSettings, Settings, Profile, ChangePassword, and ForgotPassword. Look here before creating new account-adjacent screens. `checkout_sheet.dart` handles the tenant checkout flow; `responsive_modules.dart` contains layout helpers for adaptive UI.

**Biometric** — `AppState.setBiometricEnabled` / `biometricLogin` use `local_auth`. When biometric is enabled, `restoreSession` leaves `isLoggedIn = false` even if a token is present, forcing fingerprint/PIN unlock.

**Super admin screen** — `admin_screen.dart` is the full `SUPER_ADMIN` panel (route `/admin`). It contains eight in-file sections: Dashboard (org metrics + broadcast form), Organizations (list/filter/status toggle), Data Upload (CSV file picker → `POST /api/super-admin/upload/{facilities|tenants}`), Users, Plans, Reports, Audit Logs, and System Settings. Uses the `file_selector` package (^1.0.4) for cross-platform CSV file picking — this is the only screen that picks files.

**Property workspace** — `property_workspace_screen.dart` holds the per-property tabbed view (Overview / Tenants / Payments / Reports via bottom `NavigationBar`), reached by tapping a property card; it shares `AssignBedSheet` from `room_screen.dart`. The Overview tab has a hero stat card, overview metric cards, and a 3×2 **Quick Actions** grid (`_QuickActionCard`): Floors & Rooms, Staff (pushes `StaffScreen` locked to the property), Expenses (pushes `ExpensesScreen` locked to the property), Transactions (pushes `TransactionsScreen` locked to the property — money-in/out ledger), Price Master, and Reports. The **Vacant Beds** sheet has a filter panel (`_VacantBedsFilterPanel` with `_FilterGroupCard`/`_PanelFilterChip`) filtering by floor/room/sharing-type/expected-checkout.

**Expenses screen** — `expenses_screen.dart` follows the app's light theme (`PgColors`) and is fully API-backed via `GET /expenses/dashboard`. Rendered sections: monthly summary (+ Set Budget sheet), Approvals/Reports quick chips, category overview, pending approvals (approve/reject), recent transactions (this month, with client-side category filter chips), and insights. The dashboard payload also carries budget-utilization, trend, and petty-cash data that the UI currently does not render. Two entry modes: route `/expenses` (org-level, property switcher) and the "Expenses" quick action on the property workspace Overview tab (locked to that property).

**Staff screen** — `staff_screen.dart` (light theme). Entry: route `/staff` (org-level) or the "Staff" quick action on the property workspace Overview tab (locked to that property). Month switcher (past months allowed, future blocked), payroll summary card, bulk pay bar (Pay All when nothing selected, Pay Selected when due staff are checkbox-selected; payment-method radio in the confirm dialog), per-staff Pay pill, tel: call button, add/edit sheet (profession dropdown + Other, Active toggle) and a payment-history sheet.

**Key third-party packages** — `provider` (state), `go_router` (nav), `flutter_secure_storage` (tokens), `local_auth` (biometric), `file_selector` (CSV pick, admin only), `url_launcher` (tel/sms/`wa.me` from the tenant detail action row), `flutter_svg` (inline WhatsApp glyph in `tenant_screen.dart`), `qr_flutter` (self check-in QR), `shared_preferences`. Tenant detail bed-occupancy and the vacant-bed grid use a shared color convention (vacant = green, occupied = gray, temporary = orange).

## Multi-tenancy

Shared-database multi-tenancy. Each organization is a `Facility(ORGANIZATION)`. Every business table carries `organization_id`. The backend enforces org scope from the JWT principal via `CurrentUser`.

## Docs

`docs/` contains:
- `API_SPECIFICATION.md` — 80+ endpoint reference
- `MOBILE_APP_BACKEND_MAPPING.md` — screen-to-API mapping; check before wiring up new Flutter screens
- `IMPLEMENTATION_ROADMAP.md` — planned work and priorities
- `api-design.md` — REST conventions and design decisions
- `architecture.md` — system architecture overview
- `database-schema.md` — table-level schema reference
- `implementation-notes.md` — per-feature implementation notes
- `EXPENSES_SCHEMA_MAPPING.md` — expenses screen UI-to-SQL mapping and the deliberate no-master-table design decisions
- `TEST_PLAN.md` — test strategy; integration tests auto-skip locally (no Docker)

`docs/er/` holds Mermaid ER diagrams (`.mmd`) covering authentication, billing, analytics, facility hierarchy, payments, photos, and tenant management. Useful when reasoning about join paths or adding new tables.
