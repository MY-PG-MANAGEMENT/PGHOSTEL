# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Layout

- `backend/` — Spring Boot 3.3.5 / Java 21 / Gradle modular-monolith API
- `owner_app/` — Flutter owner mobile + responsive web app
- `docs/` — Architecture, API, database schema, and implementation notes

## Backend

### Commands (run from `backend/`)

> `backend/bin/` is Eclipse/Buildship build output (compiled classes). It is ignored via `backend/bin/` in the root `.gitignore` and must never be committed. (Buildship generates its own `.gitignore` inside `bin/main/` — that file is untracked and not the ignore mechanism.)

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

`@EnableScheduling` is active on `PgManagerApplication` — `RentReminderScheduler` fires daily at 09:00 (cron `0 0 9 * * *`) to dispatch rent-due, checkout, payment-receipt, and check-in notifications; `BedTransferScheduler` at 00:05 applies due sharing-change transfers; `InvoiceAutoGenerationScheduler` (billing) at 01:00 (cron `0 0 1 * * *`) auto-creates each tenant's recurring monthly invoice a configurable number of days before their billing anniversary (see the billing "Automated invoice generation" note).

### Caching (Redis)

Opt-in, fail-open Redis cache via Spring's cache abstraction. Config: `common/cache/CacheConfig.java` (`@EnableCaching`). Toggle with `app.cache.enabled` (env `CACHE_ENABLED`): off → `NoOpCacheManager` (app runs with no Redis); on → `RedisCacheManager` (JSON values, `pgm:cache:` prefix, per-cache TTL, transaction-aware) reading `spring.data.redis.*` (`REDIS_HOST/PORT/PASSWORD`). A `CacheErrorHandler` swallows Redis failures so an outage falls back to direct DB reads. **All cache keys lead with `organizationId`** for multi-tenancy safety. Cached: `ORG_FEATURES` (`OrganizationChannelService.enabled`, `TenantLoginPolicy.enabled`; evict `setChannel`/`setEnabled`/onboarding), `SHARING_PRICES` (`PropertySharingPriceService.list`; evict `upsert` — `OccupancyService.resolveRent` reads the repo directly, always fresh), `FACILITY_TREE` (`FacilityService.tree`; evict facility CRUD + bulk upload), and the occupancy read models `ROOM_SUMMARY`/`PROPERTY_STATS`/`VACANT_BEDS`/`TEMP_STAYS` (`FacilityService.getRoomSummary`/`propertyStats`, `FacilityController.vacantBeds`, `TemporaryStayController.list`). The occupancy caches are evicted **wholesale** by the composed `@EvictOccupancyCaches` annotation (`common/cache/`) on every `facility_party`-mutating entry point (all `OccupancyService` mutators + `OccupancyController.setExpectedCheckout` + `TenantService.create` + structural `FacilityService`/bulk writes) — add a new occupancy cache to that annotation once and all writers evict it. Money dashboards (billing/expense/transactions/property-report/owner+admin) are deliberately **not** cached (write-heavy, money-sensitive). Full design + extension list: `docs/CACHING.md`.

### Database Migrations

Flyway migrations in `src/main/resources/db/migration/`. Always add new migrations as `V<n>__description.sql` — never edit existing ones. `ddl-auto` is `validate`, so Hibernate rejects schema drift (adding an entity field requires a matching migration or startup fails). Current latest is V28 (`V28__tenant_archive.sql`).

Notable migration changes:
- V10 — adds `UNIQUE KEY uk_person_mobile` on `person.mobile_number` (global, not org-scoped) and creates `bulk_upload_job` tracking table
- V11 — seeds `notification_category` rows: `RENT_REMINDER`, `CHECKOUT_REMINDER`, `PAYMENT_RECEIPT`, `CHECK_IN`, `GENERAL`
- V12 — switches mobile uniqueness from global to property-scoped (drops `uk_person_mobile`); uniqueness now enforced in app code per-property
- V13 — creates `scheduled_bed_transfer` (deferred sharing-change transfers)
- V14 — adds `facility.is_ac` (`TINYINT(1)`) and `property_sharing_price.ac_charges`
- V15 — adds `person.has_vehicle` (`TINYINT(1)`); boolean flags use `TINYINT(1) NOT NULL DEFAULT 0` mapped to a primitive `boolean`
- V16 — creates `expense`, `expense_budget`, `petty_cash_entry` (expenses module; deliberately no category/vendor/approval tables — see `docs/EXPENSES_SCHEMA_MAPPING.md`)
- V17 — creates `staff` and `staff_salary_payment` (staff management; deliberately not party/person-based — staff have no logins; `uk_staff_pay_month` is the double-payment guard)
- V18 — adds `facility_party.ac_charges`: a **breakdown annotation** of `monthly_rent` (which stays the all-in total incl. AC) so invoices can itemize `MONTHLY_RENT` (base) + `AC_CHARGES` without changing any totals
- V19 — adds nullable `facility.email` (org sender/Reply-To address for tenant emails)
- V20 — seeds `EMAIL` and `SMS` into `feature_master` (`WHATSAPP` already seeded in V2); these back the per-org messaging-channel toggles stored as `organization_feature` rows
- V21 — removes the `SMS` channel: deletes its `organization_feature` toggle rows and the `feature_master` seed (the device-SIM SMS due-reminder feature was retired). `EMAIL`/`WHATSAPP` remain
- V22 — Tenant Module: adds `user_login.disabled_reason`/`must_change_password`/`last_login_at`; seeds `feature_master` `TENANT_LOGIN` (opt-in per org, super-admin controlled); seeds `notification_category` `COMPLAINT`/`NOTICE`; creates `complaint`, `complaint_status_history`, `notice`, `notice_read`. See `docs/TENANT_MODULE.md` and `docs/er/tenant-module.mmd`.
- V23 — adds two composite indexes on `facility_party` (`idx_fp_org_facility_role_thru` = `(organization_id, facility_id, role_type_id, thru_date)`, `idx_fp_org_party_role_thru` = `(organization_id, party_id, role_type_id, thru_date)`) covering the tenant-list hot paths; V1 only had single-column indexes so the planner filtered most predicates in memory.
- V24 — drops 15 dead tables + 4 views (over-provisioned V3/V4 schema never wired to any `@Entity` or JdbcTemplate SQL): the `contact_mech` cluster, `room_photo`, `recurring_charge`, `plan_feature`, `party_role`, `status_type`, `login_history`, `analytics_cache`, `activity_log`, `payment_receipt`, plus FK-entangled `content_reference` (drops `identity_document.content_reference_id`) and `payment_method_type` (drops the unmapped `payment.payment_method_type` column — `Payment` maps `payment_mode`, not this). If reintroducing any of these features, add a fresh migration.
- V25 — adds `property_sharing_price.per_day_price` (`DECIMAL(10,2) NOT NULL DEFAULT 0`): the per-day rate, set per property + sharing type in Price Master, used to price temporary stays (`days × per_day_price`, editable before invoicing). See the Temporary Stay module below.
- V26 — creates `organization_billing_config` (`organization_id` UNIQUE, `invoice_lead_days INT DEFAULT 1`, `auto_generate_enabled TINYINT(1) DEFAULT 1`): per-org invoice-automation settings backing `InvoiceAutoGenerationScheduler`. A missing row = defaults (lead days 1, auto ON), so existing orgs are automated with no backfill. Read/written via `BillingConfigService` (JdbcTemplate, **not** a JPA entity — so `validate` does not track it).
- V27 — adds `organization_billing_config.checkout_grace_days` (`INT NOT NULL DEFAULT 2`): how many days after the due date a freshly raised invoice still counts as unconsumed, so a tenant checking out in that window has it deleted rather than billed. Backs `CheckoutInvoiceService` (see the billing "Checkout drops the unconsumed invoice" note).
- V28 — creates `tenant_archive` (`party_id` UNIQUE, `organization_id`, `property_facility_id` nullable + no FK, `full_name`/`mobile_number` display snapshot, `archived_at`, `archived_by_user_login_id`): the org → property → tenant index of tenants "deleted" from the app. One live row per party, **deleted on restore** (history lives in `audit_log` as `TENANT_ARCHIVED` / `TENANT_RESTORED`), so "is this tenant hidden?" is a plain existence check. Read/written via `TenantArchiveService` (JdbcTemplate, **not** a JPA entity — so `validate` does not track it). See the tenant "Delete = archive" note.

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

**Security deposit & checkout refund** — the deposit is collected **once, with the first month's payment**: the move-in invoice (created by `OccupancyController.bootstrapBilling` for assign/make-permanent, and by the admission `sign` flow — both now delegate to the shared `billing.MoveInBillingService`, which the CSV import also uses) carries a `SECURITY_DEPOSIT` invoice item on top of `MONTHLY_RENT`; monthly `/generate-invoices` never includes it. Invoice items are itemized: `MONTHLY_RENT` (base rent = `monthly_rent - ac_charges`), `AC_CHARGES` (when the occupancy has the V18 `ac_charges` annotation — the app sends `acCharges` alongside the all-in `monthlyRent` on assign), and `SECURITY_DEPOSIT` (first invoice only). The Flutter `InvoiceDetailSheet` fetches `GET /billing/invoices/{id}` and renders this breakdown (PG Rent / AC Charges / Security Deposit → Total). At checkout, `CheckoutRequest` accepts optional `refundAmount`/`refundMethod` (validated ≤ the deposit held on the occupancy row); `OccupancyService.checkout` records it via `ExpenseWriter` as a `DEPOSIT_REFUND` expense (money-out in the transactions ledger; CASH refunds mirror into petty cash) and audit-logs `DEPOSIT_REFUNDED`. The Flutter `CheckoutSheet` shows an optional "Deposit Refund" section (prefilled from `GET /tenants/{id}` `securityDeposit`) once dues are settled.

**Temporary stay (`TEMP_OCCUPANT`)** — a temp stay is a single `facility_party` row (role `TEMP_OCCUPANT`) that **overloads generic columns**: `from_date` = check-in, `expected_checkout_date` = planned check-out, `thru_date` = actual check-out (null while active), and `monthly_rent` = the (editable) **total** charge. There is no dedicated temp-stay table and no per-booking price column — the per-day rate lives in Price Master (`property_sharing_price.per_day_price`, V25) and the app computes `days × per_day_price` as the total, which the owner can override before it's billed. Monthly invoice generation only ever reads `OCCUPANT` rows, so temp stays are never swept into recurring billing; instead a **single** `TEMP_STAY` invoice is raised (`MoveInBillingService.bootstrapTempStay`, invoice number `TEMP-{org}-{baId}-{yyyymmdd}`, idempotent).
- `POST /api/occupancy/temp-stay` (`TempStayRequest` carries `partyId, bedFacilityId, fromDate, expectedCheckoutDate, amount`) creates the row; the controller then calls `bootstrapTempStay(amount)`.
- `PUT /api/occupancy/temp-stay/{facilityPartyId}` (`TempStayUpdateRequest`) edits an **active** stay — planned checkout, total amount, and optionally the bed (re-checked via `ensureBedAvailable`); check-in is immutable (it anchors the invoice number). The controller then calls `MoveInBillingService.updateTempStayInvoice`, which re-totals the single temp invoice and refuses to drop below `paid_amount`.
- `POST /temp-stay/end` (move back / checkout) sets `thru_date`; `POST /temp-stay/make-permanent` ends the temp stay and runs the normal assign + first-invoice anchored to the temp start date (billing starts).
- **`TemporaryStayController` — `GET /api/occupancy/temp-stays?propertyId=&status=&q=`** (JdbcTemplate) is the property-scoped read model for the Flutter Temporary Stay screen: it joins the temp `facility_party` rows up the bed→room→floor→property tree + `person` + the matched `TEMP-…` invoice, and returns `{summary, items}` where each item's **booking status** (`ACTIVE`/`UPCOMING`/`CHECKOUT_TODAY`/`OVERDUE`/`CHECKED_OUT`), remaining days, and payment status (`PAID`/`PARTIAL`/`PENDING`/`NONE`) are **derived in Java** (no stored status column). `summary` = totalGuests / active / todayCheckins / todayCheckouts, computed over the unfiltered set.
- Temp-occupied beds are excluded from `/vacant-beds`. Tenant detail (`GET /api/tenants/{id}`) exposes `currentSharingType`, `inTemporaryStay`, `tempBedFacilityId`, `tempBedName` for tenant-detail banners.
- Flutter: the property-workspace **"Temporary Stay" quick action** opens `temporary_stay_screen.dart` (summary tiles, search, status-filter chips, booking cards, add/edit form with searchable tenant/bed pickers and a per-day → read-only total). The Add form lists only **inactive tenants** (`hasActiveAdmission != true`).

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
- **Automated invoice generation.** Recurring monthly invoices are created automatically by `InvoiceAutoGenerationScheduler` (daily 01:00). The shared recurring-invoice primitive lives in `InvoiceGenerationService.createRecurringInvoice` (`@Transactional` so its INSERT + `LAST_INSERT_ID()` share one connection when the scheduler calls it) — it builds `MONTHLY_RENT`(=rent−AC)+optional `AC_CHARGES`, total = rent (no deposit; the deposit is move-in-only, still in `MoveInBillingService`), due on the tenant's anniversary day clamped to month length, invoice number `INV-{org}-{baId}-{YYYYMM}`, idempotent per `(billing_account_id, invoice_month)`, and notifies the tenant. `BillingController.POST /generate-invoices?propertyId=` is the **manual fallback** and delegates to `InvoiceGenerationService.generateDueOn(org, today, propertyId)`: it raises only the invoices **due today** — active occupants whose anniversary day (clamped to month length) equals today's day-of-month — never a whole month, and it ignores the per-org automation settings. There is no `month` param (no back-dated catch-up); the response is `{generated, skipped, notDue, date}` where `skipped` = due today but already invoiced. The scheduler runs one global sweep of active-occupant billing accounts in ACTIVE orgs, joins per-org config, and for each account generates when `today + leadDays == this month's due date` (month-length-clamped so a 31st anniversary fires in Feb and lead days crossing a month boundary land in the right billing month). Per-org settings (`invoice_lead_days` 0–28, default 1; `checkout_grace_days` 0–28, default 2; `auto_generate_enabled`, default ON) come from `BillingConfigService`/`organization_billing_config` (V26/V27) and are owner-managed via `GET/PUT /api/billing/config` (Flutter: Settings → Billing → **Invoice Automation** sheet in `account_screens.dart`; `checkoutGraceDays` is optional in `BillingConfigRequest` so an older app build falls back to the default rather than 0).
- **Checkout drops the unconsumed invoice.** Because the scheduler raises the invoice *before* its due date, a tenant who leaves around that date would otherwise be asked to pay or write off a month they never stayed. `CheckoutInvoiceService.dropUnconsumedInvoices` (called from `OccupancyService.checkout`) **hard-deletes** those invoices — line items then the row, never a `CANCELLED` soft-cancel — when `checkoutDate <= due_date + checkoutGraceDays`. With the defaults (lead 1, grace 2) an invoice due on the 26th is dropped for a checkout on the 25th–28th and kept from the 29th. Never dropped: anything with money against it (`paid_amount > 0`, a `payment_allocation` row, or a status other than `PENDING`) or an invoice carrying a `SECURITY_DEPOSIT` line (the move-in invoice — deleting it would erase the deposit charge the checkout screen offers to refund); those fall through to the normal Pay / Write Off flow. Each deletion is audit-logged as `INVOICE_DROPPED_AT_CHECKOUT`. `GET /api/occupancy/checkout-preview?partyId=&checkoutDate=` returns the same set so the Flutter `CheckoutSheet` can leave them out of "settle dues" (and out of the Confirm-Checkout gate), showing a "Not billed — removed on checkout" card instead; the sheet re-queries whenever the checkout date changes, keeping the rule server-side only.

**`rent`**

- `Rent` entity records a monthly charge per tenant (`rentMonth`, `monthlyRent`, `deposit`, `advance`, `discount`, `penalty`). `Rent.totalDue()` computes the total owed; `paidAmount` tracks what has been collected. `RentService` validates the tenant's org membership before saving.

**`payment`**

- `PaymentController` / `PaymentService` record standalone payments (JPA-based, unlike billing). Separate from `BillingController`'s payment-collection flow.

**`tenant` lifecycle sub-resources**

- `TenantLifecycleController` (mapped to `/api/tenants/{partyId}/…`) handles sub-resources that are too granular for JPA entities: emergency contacts, employment history, documents, and convenience assign/checkout endpoints. It uses `JdbcTemplate` directly (same rationale as `BillingController`).

**`tenant` — "Delete" is an archive, and re-registering restores it**

- The Inactive list grows without bound (every tenant who ever left is kept, because they routinely rejoin a month or two later). "Delete" in the app therefore **archives**: `TenantArchiveService` (JdbcTemplate, table `tenant_archive` V28) writes one row and the tenant drops out of the lists. **Nothing is deleted** — `party` / `person` / `facility_party` / `invoice` / `payment` are untouched, and the org-level TENANT membership keeps its null `thru_date` (so `assertTenantInOrganization` still resolves an archived tenant).
- Hiding happens in exactly one place: `TenantService.buildTenantResponses` filters `tenantArchiveService.archivedPartyIds(org)` out, which covers both `list()` and `listByProperty()` in one query. `TenantLoginService.generateForOrganization` skips them too (`skippedArchived`).
- Guards: only a tenant with **no active bed** can be archived (no `OCCUPANT`/`TEMP_OCCUPANT` row with a null `thru_date`) — an occupied tenant must go through Checkout first, since that is what settles dues and the deposit refund. Archiving is idempotent, disables the tenant's portal login (`TenantLoginService.disableForArchive`, reason `ARCHIVED`), and audit-logs `TENANT_ARCHIVED`.
- `OccupancyService.validateTenant` (the single gate for both bed-assign and temp-stay) also **un-archives** — putting a tenant into a bed means they are back, and an archived-but-occupying tenant would be an active occupant nobody can see.
- Endpoints (`TenantController`, all mutations `@PreAuthorize`d to OWNER/PROPERTY_MANAGER/MANAGER): `DELETE /api/tenants/{partyId}` single, `POST /api/tenants/archive` `{partyIds:[…]}` bulk (returns `{total, archived, skippedActive, skippedAlreadyArchived, skippedNotFound}` — never fails the whole selection on one bad id), `GET /api/tenants/archived?propertyId=&q=` read model, `POST /api/tenants/{partyId}/restore?propertyId=`.
- **Rejoin is automatic.** `TenantService.create` checks `findArchivedPartyByMobile(org, mobile)` **before the duplicate-mobile rejection** — order is load-bearing: archiving leaves the TENANT membership rows with a null `thru_date`, so `countActiveTenantsByMobileAtProperty` still counts an archived tenant and running it first rejected every rejoin at the property they left with "already registered at this property". The only clash that still rejects is a *different* party with that mobile currently holding a bed (`PersonRepository.countOccupyingTenantsByMobileExcluding`, which looks at real occupancy rather than the never-end-dated membership row). Then: a match means this person was archived here, so it delegates to `restoreFromArchive` on the **same partyId** instead of minting a duplicate person (which would orphan their invoice/payment history). Only the fields the Add Tenant form actually filled in are merged over the stored profile (`applyEnteredFields` — blank ⇒ keep the old value, so emergency-contact/employment details the form never asks for survive); `restoredFromArchive: true` comes back on `TenantResponse` so the app can say what happened. The pre-existing active-duplicate check still runs first.

**`expense`**

- `ExpenseController` (`/api/expenses`) is JdbcTemplate-based (same rationale as billing). `GET /dashboard?propertyId=&month=` returns every section the Flutter expenses screen renders in one round-trip: summary (incl. MoM change %), category breakdown, category budgets vs spend, 6-month expense/income/profit trend (income = `RECEIVED` payments), pending approvals, recent transactions (whole dashboard month, `PENDING` included so a just-created expense shows immediately; summary/category totals stay `APPROVED`/`PAID` only), petty cash summary, and heuristic insights.
- Categories (`ELECTRICITY`, `WATER`, `SALARY`, `FOOD`, `CLEANING`, `REPAIRS`, `INTERNET`, `GAS`, `MAINTENANCE`, `LAUNDRY`, `TRANSPORT`, `RENT`, `DEPOSIT_REFUND`, `OTHERS`) and payment methods are string constants — no master tables. Categories are only ever **added**, never removed: an existing row must keep resolving, and `DEPOSIT_REFUND` is written by the checkout refund flow rather than chosen by hand. The Flutter side mirrors the list once in `lib/src/utils/expense_categories.dart` (`expenseCategoryMeta` — label/colour/icon), shared by the expenses screen and the reports filter so the two cannot drift; `expenseCategory()` falls back to "Others" for an unknown code. Approval is the `status` column (`PENDING`/`APPROVED`/`REJECTED`/`PAID`); only `PENDING` can transition. `POST /` creates `APPROVED` unless `requiresApproval: true`.
- Budget upsert (`PUT /budget`) uses sentinel scoping in `expense_budget`: `property_facility_id = 0` means org-wide, `category = 'ALL'` means the overall monthly budget (keeps the MySQL unique key enforceable).
- **Correcting a mis-keyed expense.** `GET /{expenseId}` returns the full row for the edit form plus `editable`/`lockedReason`; `PUT /{expenseId}` edits title/category/amount/date/method/vendor/notes/property (**not** status — that stays with `PATCH /{id}/status`); `DELETE /{expenseId}` is a **hard delete** (no void state in the schema — an expense entered by mistake must leave no trace in any total; `audit_log` keeps `EXPENSE_UPDATED`/`EXPENSE_DELETED`). Both are `@PreAuthorize`d to OWNER/PROPERTY_MANAGER/MANAGER/ACCOUNTANT, unlike create/approve which are unguarded. **Locked rows**: an expense referenced by `staff_salary_payment.expense_id` is owned by the staff module and is refused with "Manage it from the Staff screen" — editing it here would desync payroll. The mirrored petty-cash `OUT` row is kept in step by `syncCashMirror` (updated on edit, dropped when the expense stops being an approved CASH spend, deleted with the expense).
- **Flutter split: landing page vs activity screen.** `expenses_screen.dart` holds two screens. `ExpensesScreen` (routes `/expenses` + the property-workspace quick action) is the month at a glance only — property/month selector, summary card, **Approvals / Transactions** chips, Category Overview, Smart Insights. The row-by-row work moved to **`ExpenseActivityScreen`** (same file), pushed by those chips with `initialPage` 0 or 1: a **pinned** month selector (it scopes both pages, so it must not scroll away) over a swipeable `PageView` of **Pending** (approve/reject) and **Transactions** (filter chips + edit/delete). A segmented control mirrors the pager — tap or swipe. Returning from it reloads the landing page, since approvals/edits/deletes move the month's totals. Both screens fetch the same `GET /expenses/dashboard` payload. (The old "Reports" coming-soon chip was dropped to make room for the Transactions chip.)
- Flutter: each Transactions row has a ⋮ with Edit / Delete. Edit fetches `GET /expenses/{id}` first (the dashboard payload omits vendor/notes/property) and refuses **before** opening the sheet when `editable` is false; the sheet is `_AddExpenseSheet` with an optional `expense:` param (title/button flip to "Edit Expense"/"Update Expense", the approval switch is hidden, the date picker widens to include an older expense date). Delete confirms, then `DELETE`. Covered by `test/expense_edit_delete_test.dart` (`FakeApiClient` gained `stubPut`/`putCalls`/`putBodies`).
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
- **Per-org channel toggles** — `OrganizationChannelService` (notification package) is the single source of truth for whether `EMAIL`/`WHATSAPP` are enabled for an org. Channels are **opt-in**: a channel is enabled only when an `organization_feature` row exists with `enabled=TRUE` for the matching `feature_master.feature_code` (missing/false = disabled). `NotificationService.notifyTenant` gates the email outbox enqueue on `channelService.enabled(org, "EMAIL")` (in addition to the global `app.messaging.email.enabled` flag and per-recipient `notification_preference` opt-out). Super admins toggle via `GET/PATCH /api/super-admin/organizations/{id}/channels` (body `{channel, enabled}`).

**`tenant` login lifecycle + `tenantportal` (Tenant Module)**

- **Opt-in, super-admin controlled.** Tenant Login is an `organization_feature` (`feature_master.feature_code = 'TENANT_LOGIN'`, V22), toggled only via `GET/PATCH /api/super-admin/organizations/{id}/tenant-login`. `tenant/TenantLoginPolicy.enabled(orgId)` is the single gate; default disabled.
- `tenant/TenantLoginService` owns the login lifecycle. Username scheme is **`{mobile}@{orgId}`** (globally unique, org-scoped). Temp password **`abc@123`** + `must_change_password=1` on every auto-created/reactivated login. `provisionForTenant` (called from `TenantService.create`, so it covers manual add, Excel upload, self check-in) reuses an active login, reactivates an inactive one on rejoin (re-points `party_id`), or creates a new one. `disableForCheckout` (called from `OccupancyService.checkout`) sets status INACTIVE + reason CHECKED_OUT and revokes refresh tokens. `generateForOrganization` backs the owner bulk action `POST /api/tenants/generate-logins` (skips inactive/checked-out/already-provisioned; returns a summary). `GET /api/tenants/login-feature` drives the owner affordance.
- `auth/TenantAuthService` + `TenantAuthController` authenticate by **mobile + password** (`POST /api/auth/tenant/login`), bypassing the username-based `AuthenticationManager`. Returns `{needsOrgSelection, organizations, auth}` — the org picker fires when a mobile maps to >1 active login. `AuthResponse` carries `mustChangePassword` + `partyId`; refresh reuses `/api/auth/refresh`.
- `tenantportal/TenantPortalController` (`/api/tenant/**`, guarded to `ROLE_TENANT` in `SecurityConfig` **before** the generic `/api/**` guard which excludes TENANT). Endpoints: `dashboard`, `profile`, `payments`, `change-password`, `complaints` (list/create/detail), `notices` (list/detail), `notifications` (list/read). Org + partyId come only from `CurrentUser`.
- `complaint` + `notice` packages: JPA entities/repos with owner-facing controllers (`/api/complaints` triage + status transitions notify the tenant; `/api/notices` authoring fans out notifications). Status/type constants in `ComplaintStatus`/`NoticeType`.
- Flutter tenant experience lives inside `owner_app` (`lib/src/screens/tenant/tenant_app.dart`, Purple/White MD3 via `theme/tenant_theme.dart`), reached by the TENANT branch in `main.dart`'s redirect (careful: owner route is `/tenants`, tenant portal base is `/tenant`). Login has an Owner/Tenant toggle. Full spec: `docs/TENANT_MODULE.md`.

**`feature`**

- `feature_master` seeds available feature codes; `organization_feature` stores which features an org has enabled. The `OnboardingService` activates features during the wizard run. The messaging-channel codes `EMAIL`/`WHATSAPP` reuse this table — read/written via `OrganizationChannelService` (notification package), not `OnboardingService`.

**`admin`**

- `SuperAdminController` (mapped to `/api/super-admin`) is gated to `SUPER_ADMIN` role. Endpoints: `GET /dashboard` (cross-org metrics + last 10 audit entries), `GET /organizations` (filterable by `?status=`), `POST /organizations` (provision a new organization + its OWNER login — delegates to `AuthService.createOwnerAccount` without logging the super admin out), `PATCH /organizations/{id}/status` (toggle org active/inactive/suspended), `GET /plans` + `POST /plans` + `PATCH /plans/{id}` (activate/deactivate a plan, body `{active}`), `GET /reports/revenue` (per-month per-org totals incl. `organization_name`), `POST /broadcast` (push a titled announcement to all org owners via `NotificationService`). Uses JdbcTemplate throughout (except org creation, which reuses the JPA-based `AuthService`). Note: `GET /system-settings` masks encrypted values as `********`; the Flutter admin screen must exclude encrypted keys from the `PATCH /system-settings` payload (else it would overwrite the real secret and clear the encrypted flag).
- Owner self-registration was removed from the Flutter login screen; new organizations are created exclusively by super admins via `POST /organizations` (the admin panel's Organizations tab has a "New Organization" dialog). `AuthService.registerOwner` (and `POST /api/auth/register-owner`) still exist and wrap `createOwnerAccount`, but the owner app no longer exposes a `/register` route.
- `BulkUploadController` (mapped to `/api/super-admin/upload/{facilities|tenants}/{organizationId}`). `GET /template/facilities` and `GET /template/tenants` return downloadable CSV templates. `POST` endpoints accept `MultipartFile` CSV uploads parsed via Apache Commons CSV. **Facilities upload now creates the PROPERTY** (find-or-create by `property_code`/`property_name`, linked org→property) as well as floors/rooms/beds. The org is always the selected org (path `organizationId` from the upload wizard) — there is no per-row org column. Facilities CSV columns: `property_name,property_code,floor_name,floor_number,floor_code,room_name,room_number,room_code,sharing_type,monthly_rent,security_deposit,is_ac,capacity,bed_name,bed_code` (room-level `is_ac`/`capacity`/`security_deposit` map to the `Facility` entity). **Codes are dual-purpose**: `floor_code`/`room_code`/`bed_code` both match an existing node (code-wise, via `findChildByCode`) and, on create, set that node's `facility_code` (else auto `<TYPE-prefix>_<id>`). Tenant CSV columns cover the full `TenantCreateRequest` (incl. `employer_name,designation,work_address,has_vehicle`) plus assignment resolved by code OR name **at every level** (`property_code`/`floor_code`/`room_code`/`bed_code` via `resolveBed`+`findChild`; a `bed_code` resolves the bed directly via `findFacilityByCode(BED)`), and `move_in_date,monthly_rent,ac_charges,security_deposit,expected_checkout_date` + backfill (`paid_up_to_month,payment_method`). Booleans accept `true/1/yes/y`. Parsing is by header name so column order/presence is flexible (missing columns default to empty/null via `col()`). Bulk test data lives in `docs/test-data/` (generator: scratchpad `gen_test_data.py`). Tenant upload calls `TenantService.create` per row (no dedup — re-uploading a mobile creates a duplicate person; the property-scoped uniqueness check is skipped because the bulk path passes `propertyId = null`). Results tracked in `bulk_upload_job` table.
- **Bulk tenant bed-assignment produces real billing.** After `OccupancyService.assign`, the bulk path calls `MoveInBillingService.bootstrapMoveIn` (same move-in invoice as the in-app flow). The tenant CSV also carries optional `paid_up_to_month` (`YYYY-MM`) + `payment_method` columns: when present, `MoveInBillingService.backfillPaidHistory` generates and fully settles an invoice for every month from move-in through that month (first month includes the deposit), so imported tenants carry realistic invoice + payment history. Backfill is idempotent per invoice (`bulk-backfill-{org}-{invoiceId}` idempotency key).

**`selfcheckin` — tenant self check-in via QR**

- `PublicSelfCheckinController` (`/api/public/self-checkin/{orgId}/{propertyId}/{sig}`, **no auth**) serves a self-contained HTML registration form (`GET`) and creates the tenant on submit (`POST`, form-urlencoded). It reuses `TenantService.create` — the *same* code path as the in-app Add Tenant flow — passing `userLoginId = null`. A `propertyId` of `0` means org-level (no property scope).
- `SelfCheckinTokenService` signs the `(orgId, propertyId)` pair (`sha256` of the ids + jwt-secret, truncated) so the URL ids cannot be swapped. `pathFor`/`linkFor` build the signed path.
- `TenantController` exposes the authenticated `GET /api/tenants/self-checkin-link?propertyId=` returning `{url, path}`. The Flutter app prepends **its own** `ApiClient.baseUrl` origin to `path` so the QR host always matches the backend the app is actually using (avoids `public-base-url` drift). `TenantCreateRequest`/`TenantUpdateRequest`/`TenantResponse` carry a primitive `boolean hasVehicle`.

**`dashboard`**, **`settings`**, **`subscription`**

- Self-contained packages for their respective concerns; follow the same JPA + `ApiResponse<T>` convention unless they involve aggregation (in which case JdbcTemplate may be used, as in `FacilityController`'s `/vacant-beds` and `/room-summary` endpoints).

**`report` — downloadable reports**

- `ReportController` (`/api/reports`, JdbcTemplate) serves **four** reports, all scoped by `propertyId`. Each returns **data, not a file** — the Flutter app renders the PDF, so a layout change needs no backend release. All four return `{…scope, summary, items}` shaped for a table.
  - `GET /rent-collection?month=YYYY-MM` — one row per invoice raised that month (14 columns).
  - `GET /outstanding-dues?month=YYYY-MM&partyId=` — one row per tenant still owing. The app always requests the whole property (the card is month-only, with no tenant filter and no tenant-list fetch); `partyId` remains as an optional single-tenant filter for a future per-tenant statement. **Cumulative**: any unpaid invoice with `invoice_month <=` the selected month counts, so a tenant three months behind shows the whole arrears. Computed as of `min(today, month end)` so "days overdue" never runs into the future for a historical month. `reminderStatus` = whether a `RENT_REMINDER` notification was ever sent to that party (Sent / Not sent).
  - `GET /expenses?month=YYYY-MM&category=` — the month's spend, `APPROVED`/`PAID` only (a PENDING expense is not money out yet), so it ties to the expenses dashboard. `paidBy` = `COALESCE(approved_by, created_by)` → `user_login` → `person.full_name`.
  - `GET /profit-loss?from=&to=` — **cash basis**: income is RECEIVED payments dated in the range, expenses are APPROVED/PAID entries dated in it, so it reconciles with the transactions ledger. `totalRent` is the slice of receipts allocated to invoices (`payment_allocation`), `otherIncome` the remainder, clamped so it can never go negative when an older advance is applied inside the window. Also returns a month-by-month split and an expense-by-category breakdown.
- Field derivation for rent collection (the schema has no report-shaped columns): `rentAmount` = the `MONTHLY_RENT` line item (base rent, AC excluded per V18); `additionalCharges` = every other **positive** line (`AC_CHARGES`, `SECURITY_DEPOSIT`, `TEMP_STAY`, `OTHER`); `discount` = the sum of **negative** lines — there is no `DISCOUNT` item type yet, so it is 0 unless an invoice was credited down; `status` is derived from the money (Paid / Partial / Pending), **not** `invoice.status`, so an OVERDUE-but-part-paid invoice reads Partial; `roomBed` is the occupancy that **covers the invoice month**, not the tenant's current bed. Room/bed, property and the latest receipt are **scalar subqueries, not joins** — a tenant can hold several occupancy/membership rows in a month, and joining would duplicate the row (and need a `GROUP BY` that `ONLY_FULL_GROUP_BY` rejects).
- Flutter: **`screens/reports_screen.dart`** holds the public `ReportsTab` (the property-workspace Reports tab; the old private `_PropertyReportsTab` and its `_ReportCard`/`_ReportRow`/`_MonthlyTrendCard` read-only cards are gone). One card per report — icon tile, title, subtitle, inline filters, **Download PDF**. Each card owns its filter state and busy flag, so one download never blocks another, and **nothing is fetched until a download is requested**. Filters: Month (Rent Collection), Month (Outstanding), Month + Category (Expense), From/To (P&L). The button drops to its own full-width row when the card is too narrow for filters + button.
- `lib/src/reports/` holds one builder per report over a shared `report_pdf_common.dart` (page shell, title block, summary strip, branded table, money/date formatting) so the four PDFs read as one family. Every builder is a **pure function of the payload** (no plugin, no `BuildContext`), so `test/rent_collection_pdf_test.dart` renders all four headlessly.
- **Download = save + open, never a chooser.** `reports/report_download.dart` → `savePdfToDevice` writes the bytes straight to storage and hands the file to the system viewer (`open_filex`); there is no folder picker and no share sheet. Android target is the app's external `Reports/` dir — writable without `MANAGE_EXTERNAL_STORAGE` under scoped storage, unlike the public Downloads folder; desktop uses the real Downloads dir; web has no filesystem so it falls back to `Printing.sharePdf` (a browser download). The toast always names the folder, since that is the only place the owner learns where it went. `debugOpenSavedFile` is the test seam — `OpenFilex` shells out to a real process on desktop (`cmd /c start` on Windows), which a widget test must never do.
- The month filter is **month + year only** (`_MonthYearDialog`: year stepper over twelve month chips, future months disabled) — these reports are month-scoped, so a day grid would ask for a value the report ignores. Only Profit & Loss uses full date pickers, because its range is arbitrary.
- **PDF text must stay ASCII**: the built-in Helvetica is a Type1 font with no Unicode support, so an em dash or a non-Latin tenant name will not render. `₹` is written as `Rs.` and separators are `|` for the same reason. Bundling a Unicode TTF (or `PdfGoogleFonts`) is the fix if non-Latin names ever need to print.
- Testing the tab (see `test/reports_screen_test.dart`) needs four non-obvious bits: pump it inside a `Scaffold` (the filter `InkWell`s need a Material ancestor) **and** a `MaterialApp` carrying `AppToast.navigatorKey`, or `AppToast` finds no root overlay and silently shows nothing; mock `plugins.flutter.io/path_provider` to a temp dir; set `debugOpenSavedFile` so no viewer process launches; and **wait in real time** (`tester.runAsync`) for the file I/O — pumped time does not advance it, and the PDF lands on disk a beat before the download completes, so poll on the *open* step rather than the file.

**`facility` — deleting structure (floor / room / bed)**

- `DELETE /api/facilities/{facilityId}` → `FacilityService.deleteNode` handles **FLOOR, ROOM and BED** (anything else → 400). Floors/rooms/beds are pure structure with no history worth keeping, so unlike a tenant this is a **real delete, not an archive**: the whole subtree goes (floor → its rooms → their beds), along with each node's `facility_party` rows and its `facility_group_member` links, in one transaction. Returns `DeleteFacilityResult {facilityTypeId, deletedRooms, deletedBeds}`.
- Refused (400, message names the count) when any bed in the subtree has an **active occupant** — `facility_party` with a null `thru_date` in role `OCCUPANT` **or** `TEMP_OCCUPANT`, so a temp stay blocks the delete too — or is the **target of a PENDING `scheduled_bed_transfer`**, which would otherwise fire at a bed that no longer exists. An occupied bed must go through Checkout first.
- `@PreAuthorize`d to OWNER/PROPERTY_MANAGER/MANAGER (the endpoint was previously bed-only and unguarded). The Flutter "reduce sharing" flow in `_EditRoomSheet` still uses the same endpoint to trim excess vacant beds.
- `GET /api/facilities/{facilityId}/delete-check` → `checkDelete` is the **dry run** of exactly the same rules (both share `subtreeOf` + `blockingReason`, so the check can never drift from the delete): `{facilityTypeId, deletable, reason, rooms, beds}`.
- Flutter: the ⋮ on the floor header card ("Delete Floor") and on each room card ("Delete Room") in `FloorsRoomsScreen` (`property_workspace_screen.dart`). Both go through `_deleteCheck` **before** confirming, so a blocked delete is a **single** popup carrying the server's `reason` — not a confirm dialog followed by an error. When it is deletable, the counts from the check fill in the confirm text ("The room and its 3 beds will be removed."). Success → toast; a delete that still fails (someone moved in meanwhile) → `_showDeleteBlocked` dialog. Deleting a floor calls `_onFloorDeleted`, which jumps the `PageView` back to page 0 before the shorter floor list rebuilds. The rule itself is **server-side only** — the app never decides deletability locally.

**`facility` — InventoryController**

- `InventoryController` (separate from `FacilityController`) exposes read-only inventory views: `GET /api/inventory/properties/{propertyId}` (rooms with bed counts and occupancy stats) and `GET /api/inventory/rooms/{roomId}` (individual bed status including current occupant details). Uses JdbcTemplate for the aggregated joins.

**Common patterns**

- All controllers return `ApiResponse<T>` (`{ success, message, data }`).
- Entities extend `BaseEntity` (provides `createdAt`, `updatedAt` via JPA auditing).
- `GlobalExceptionHandler` maps: `NotFoundException` → 404, `BadRequestException` → 400, `MethodArgumentNotValidException` → 400 with aggregated field errors (`"field: msg, field2: msg2"`), `AccessDeniedException` → 403.
- `AuditService.log(organizationId, userLoginId, eventType, entityType, entityId, description)` should be called for significant state changes.
- **Reading boolean flags through JdbcTemplate**: use `common/util/JdbcValues.toBoolean(value, fallback)`, never a `(Number)` cast. MySQL Connector/J maps `TINYINT(1)` to `Boolean` (its `tinyInt1isBit` default) but returns a `Number` for the same column through `COALESCE`/`SUM`, so a raw cast throws `ClassCastException` — and it throws only once a row actually exists, which hides the bug behind "no row → defaults" branches. `JdbcValues.toInt` is the matching null-safe integer read.

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
flutter test test/tenant_screen_test.dart   # run a single test file
flutter build apk              # Android release APK
flutter analyze                # lint
```

Widget tests live in `test/` and stub the network with `FakeApiClient` from `test/support/test_harness.dart` — it overrides `ApiClient.get`/`post` with per-path responders (`stubGet`, `stubGetError`, `stubGetPending` for observing loading states) and records call order. Note list payloads must be stubbed as `{'items': [...]}` to match the real client's unwrapping. Use it instead of hand-rolling mocks when testing screens.

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

**Super admin screen** — `admin_screen.dart` is the full `SUPER_ADMIN` panel (route `/admin`). It contains nine in-file sections: Dashboard (org metrics + broadcast form), Organizations (list/filter/status toggle), Data Upload (CSV file picker → `POST /api/super-admin/upload/{facilities|tenants}`), Users, Plans, Reports, Audit Logs, System Settings, and Messaging. The **Messaging** section (`_AdminMessaging` + `_OrgChannelsSheet`) lists orgs; tapping one opens a sheet with EMAIL/WHATSAPP `SwitchListTile`s backed by `GET/PATCH /api/super-admin/organizations/{id}/channels` (channels are opt-in — off until toggled on). Uses the `file_selector` package (^1.0.4) for cross-platform CSV file picking — this is the only screen that picks files.

**Property workspace** — `property_workspace_screen.dart` holds the per-property tabbed view (Overview / Tenants / Payments / Reports via bottom `NavigationBar`), reached by tapping a property card; it shares `AssignBedSheet` from `room_screen.dart`. The Overview tab has a hero stat card, overview metric cards, and a **Quick Actions** grid (`_QuickActionCard`, 3 columns): Floors & Rooms, Staff (pushes `StaffScreen` locked to the property), Expenses (pushes `ExpensesScreen` locked to the property), Transactions (pushes `TransactionsScreen` locked to the property — money-in/out ledger), Price Master (`_SharingPricesScreen` — per-sharing-type monthly rent / deposit / AC charges **and the V25 per-day rate**), Complaints, and Temporary Stay (pushes `TemporaryStayScreen`). (Reports is a bottom-nav tab, not a quick action.) The **Vacant Beds** sheet has a filter panel (`_VacantBedsFilterPanel` with `_FilterGroupCard`/`_PanelFilterChip`) filtering by floor/room/sharing-type/expected-checkout.

**Expenses screen** — `expenses_screen.dart` follows the app's light theme (`PgColors`) and is fully API-backed via `GET /expenses/dashboard`. It is **two screens**: the `ExpensesScreen` landing page (monthly summary + Set Budget sheet, Approvals/Transactions chips, category overview, insights) and `ExpenseActivityScreen` (pinned month header over a swipeable Pending / Transactions pager) — see the expense module notes above. The dashboard payload also carries budget-utilization, trend, and petty-cash data that the UI currently does not render. Two entry modes: route `/expenses` (org-level, property switcher) and the "Expenses" quick action on the property workspace Overview tab (locked to that property).

**Staff screen** — `staff_screen.dart` (light theme). Entry: route `/staff` (org-level) or the "Staff" quick action on the property workspace Overview tab (locked to that property). Month switcher (past months allowed, future blocked), payroll summary card, bulk pay bar (Pay All when nothing selected, Pay Selected when due staff are checkbox-selected; payment-method radio in the confirm dialog), per-staff Pay pill, tel: call button, add/edit sheet (profession dropdown + Other, Active toggle) and a payment-history sheet.

**Tenant screen — delete / deleted tenants** — `tenant_screen.dart` renders the tenant list in both entry modes (route `/tenants`, and the property-workspace Tenants tab, which has no app bar of its own). Three separate affordances, deliberately not one overflow menu:
- **Bulk delete** — a red `delete_outline` `IconButton` at the end of the ALL/ACTIVE/INACTIVE filter chip row, rendered only when `_filter == 'INACTIVE' && !_selectMode` (both entry modes). It turns the list into a multi-select: checkboxes on `_TenantCard` plus `_selectionBar` (select-all, count, Cancel, Delete) → `POST /tenants/archive`. Leaving the Inactive filter exits select mode.
- **Deleted tenants** — always the **top-bar ⋮ of whichever screen owns the app bar**, never the filter row. On the standalone `/tenants` route that is `TenantScreen`'s own `AppBar`; in the property workspace `TenantScreen` has no app bar (the `Stack` branch), so the item lives in `PropertyWorkspaceScreen`'s existing tab-aware ⋮ gated on `_tab == 1` (Tenants) and passes `propertyId` through. Both open `ArchivedTenantsScreen` (in `tenant_screen.dart`, optional `propertyId`): search, `GET /tenants/archived`, per-row Restore → `POST /tenants/{id}/restore`. Note the property-scoped list filters on `tenant_archive.property_facility_id`, so an archived tenant who never had a property or a bed shows only in the org-level list.
- **Single delete** — a danger-tinted card at the bottom of the tenant-detail **Profile tab** (`_ProfileTab`, `onDelete` callback → `_TenantDetailScreenState._deleteTenant` → `DELETE /tenants/{id}`), matching the inline Checkout/Change-Rent buttons above it. Not in the overflow menu. Rendered only when the tenant holds no bed and is not in a temp stay — an active tenant sees "Checkout Tenant" there instead.

Every confirmation states that invoices/payments are kept and that re-registering the mobile restores the profile; the Add Tenant form shows an "Existing Tenant Restored" dialog when the response carries `restoredFromArchive`. **Generate Tenant Logins moved out of this screen** — it now lives in Settings (see below). `FakeApiClient` stubs `delete` (`stubDelete`/`deleteCalls`) and records `postBodies` — see `test/tenant_archive_test.dart`.

**Settings → Tenant Portal** — `_TenantPortalSettingsGroup` (in `account_screens.dart`) holds **Generate Tenant Logins** (`POST /tenants/generate-logins`, with the created/skipped summary dialog). The whole group renders `SizedBox.shrink()` unless `GET /tenants/login-feature` reports the org has Tenant Login enabled, so an org that cannot use the feature never sees it.

**Key third-party packages** — `provider` (state), `go_router` (nav), `flutter_secure_storage` (tokens), `local_auth` (biometric), `file_selector` (CSV pick, admin only), `url_launcher` (tel/`wa.me` from the tenant detail action row), `flutter_svg` (inline WhatsApp glyph in `tenant_screen.dart`), `qr_flutter` (self check-in QR), `pdf` + `printing` (report PDFs — see the `report` module notes), `shared_preferences`. Tenant detail bed-occupancy and the vacant-bed grid use a shared color convention (vacant = green, occupied = gray, temporary = orange).

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
