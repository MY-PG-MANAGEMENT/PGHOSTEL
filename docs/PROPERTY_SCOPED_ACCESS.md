# Property-Scoped Logins

One owner, many properties: give one person one property. A `PROPERTY_MANAGER` login sees and acts
on only the properties assigned to it; the owner keeps the whole organization.

---

## 1. What was there before

Nothing enforced. Worth being precise, because the roles made it look like there was:

- `PROPERTY_MANAGER`, `MANAGER`, `ACCOUNTANT`, `SUPPORT`, `VIEWER` existed in `RoleType` and in
  `@PreAuthorize` lists — as **role** checks only, never a scope.
- **No way to create such a login.** The only two paths were `AuthService.createOwnerAccount` (OWNER)
  and `TenantLoginService` (TENANT).
- `propertyId` was a **client-supplied `@RequestParam`** dropped into a `WHERE` clause, and in most
  endpoints not even validated as belonging to the caller's organization.
- `permission` / `role_permission` were seeded in V3 and read by two read-only super-admin
  endpoints. Never enforced at runtime.
- The JWT carried `userLoginId`, `partyId`, `organizationId`, `roleTypeId` — no property.

So a `PROPERTY_MANAGER` login, had one existed, would have had full organization access.

## 2. Storage — no new tables

An assignment is a `facility_party` row: `role_type_id = 'PROPERTY_MANAGER'`,
`facility_id = <propertyId>`, `thru_date IS NULL` while active. The same dated-membership pattern
tenants already use, so unassigning is an **end-date** and "who managed this property in March" stays
answerable. Covered by the V23 index `idx_fp_org_party_role_thru`.

The login itself is the same `Party → Person → UserLogin` graph an owner is. `user_login` already had
`must_change_password` (V22). **No migration was needed for this feature.**

## 3. Enforcement

Everything funnels through **`security/PropertyAccessGuard`**.

| Method | Use |
|---|---|
| `scope()` | `PropertyScope` — unrestricted, or a set. Memoised per request. |
| `resolvePropertyId(requested)` | The workhorse for any endpoint taking an optional `propertyId`. |
| `assertCanAccess(propertyId)` | For a required path-variable `propertyId`. |
| `assertFacilityInScope(facilityId)` | For a FLOOR/ROOM/BED id — walks `facility_group_member` up. |
| `assertTenantInScope(partyId)` | For a tenant id — via their property-level `TENANT` row. |
| `propertyFilter(column)` | SQL fragment for org-wide reads. `" AND 1=0"` when unassigned. |

### `resolvePropertyId` semantics

| Caller | Requested | Result |
|---|---|---|
| OWNER / SUPER_ADMIN | `null` | `null` — org-wide, byte-for-byte as before |
| OWNER | `X` | `X` |
| Manager | own property | that property |
| Manager | someone else's | **403** |
| Manager, 1 assignment | `null` | **substituted** with theirs |
| Manager, 2+ assignments | `null` | **400 "Select a property"** |
| Manager, 0 assignments | anything | **403** |

**The 400 is the deliberate design decision.** The alternative — quietly widening the query to
`IN (...)` over their set — means rewriting the SQL of ~20 aggregate endpoints (billing, expenses,
transactions, reports) and getting every one right. One missed predicate silently returns the whole
organization, and the API *looks* scoped while leaking. Requiring an explicit property cannot leak.
In practice it never fires: a scoped login's property picker only lists their own properties.

### Three design choices worth keeping

**Assignments come from the database, not the JWT.** A property claim would be baked into a token
living `access-token-minutes` (30), so revoking a property wouldn't take effect for half an hour —
the same staleness trap documented for `OrganizationStatusGuard`. Instead it is one indexed query,
**memoised on the request**, so a reassignment applies on the caller's very next call.

**Memoisation uses a request attribute, not a `ThreadLocal`.** Same reason as `ApiLogContext`: a
`ThreadLocal` survives on a pooled container thread and would leak one login's property set into the
next request — a cross-tenant authorization bug.

**An empty restricted set is not the same as unrestricted.** A staff login with no assignments sees
nothing. Failing closed is the only safe default; the opposite mistake hands a brand-new login the
whole organization. `propertyFilter` therefore returns `" AND 1=0"`, never `""`.

**No authenticated principal ⇒ unrestricted (system context).** The `@Scheduled` jobs (rent
reminders, invoice auto-generation, bed transfers) and the public self check-in endpoints run with an
empty `SecurityContext`; scoping them would stop invoice generation dead. Safe because every route
under `/api/**` is authenticated by the security chain long before a controller is reached.

## 4. Where enforcement is applied

**Service-layer choke points** — chosen over per-controller edits so a *new* endpoint is scoped by
default rather than by remembering:

| Choke point | Covers |
|---|---|
| `TenantService.assertTenantInOrganization` | every by-id tenant op: get, update, patch, archive, restore, and all `TenantLifecycleController` sub-resources (contacts, employment, documents, admission, agreements, checkout, settle) |
| `OccupancyService.validateTenant` | assign, temp-stay, make-permanent |
| `OccupancyService.validateBed` | assign, transfer, temp-stay, checkout |
| `TenantService.list()` | redirects a scoped login to their own property's list |
| `FacilityService.tree()` | prunes the org's children to the permitted set |
| `OwnerController.properties()` | **the property list / switcher** — `GET /api/owner/properties` |
| `DashboardService.ownerDashboard()` | the home screen's six headline figures |

**Entry points guarded individually** (25): billing dashboard / invoices / payments /
generate-invoices; expenses dashboard + list; transactions ledger; staff list; complaints list;
notices list; all four reports; facility floors / rooms / beds / vacant-beds / report / room-summary /
stats / tenants / sharing-prices; facility update / delete-check / delete; inventory property + room;
temp-stays list.

## 5. Managing the logins

`/api/managers`, **OWNER-only** — deliberately excluding `PROPERTY_MANAGER`, because a manager who
could edit assignments could grant themselves the properties they were denied. This is the one
surface where that role must be excluded, since it is the surface that defines the role.

| Endpoint | Action |
|---|---|
| `GET /api/managers` | Logins with their assigned properties (one batched query, no N+1) |
| `POST /api/managers` | Create — returns username + temp password (only time it is knowable) |
| `PUT /api/managers/{id}/properties` | Replace the assignment set |
| `PATCH /api/managers/{id}/status` | Activate / deactivate (deactivating revokes refresh tokens) |
| `POST /api/managers/{id}/reset-password` | Back to the temp password, forced change, tokens revoked |

**The manager signs in with their mobile number.** The username is *stored* as
`{mobile}@m{orgId}` because `user_login.username` is globally `UNIQUE` and the same mobile may exist
in several organizations (the `m` prefix also avoids colliding with a tenant's `{mobile}@{orgId}` for
the same person) — but that suffix is an implementation detail nobody should have to type.
`AuthService.resolveStaffMobile` maps a bare 10-digit entry back to it, so the credential an owner
hands over is just the mobile, and the app needs no change (the login screen already tries the
owner path first).

Order is load-bearing: an **exact** username match always wins, so an owner whose chosen username
happens to be ten digits authenticates exactly as before. Only `PROPERTY_MANAGER` logins are resolved
this way. If one mobile has manager logins in two organizations the input is left alone and the error
names the full-username fallback — guessing an organization at the login boundary would be the wrong
kind of helpful.

Temp password `abc@123` with `must_change_password = 1`, the same convention as the tenant portal. The
create/reset dialogs show **"Sign in with: <mobile>"**, and the manager list shows the mobile rather
than the suffixed username.

Flutter: **Settings → Team → Managers** (`screens/managers_screen.dart`), owner-only. Create with
name + mobile + property tickboxes; per-row menu for edit / reset password / activate-deactivate. A
manager with nothing ticked is flagged inline — an unassigned login can sign in but sees nothing,
which otherwise reads as a broken app rather than a configuration gap.

`main.dart` needed one fix: `mustChangePassword` was enforced only on the tenant branch, so every new
manager would have kept running on `abc@123`. Non-tenant, non-super-admin logins are now redirected
to `/settings/password` until they change it.

## 6. Tests

`PropertyAccessGuardTest` — 20 tests, both failure directions:

- **Owner is never narrowed**: `null` in → `null` out; no assignment query is issued at all; the
  filter fragment is empty.
- **Manager is never widened**: assigned allowed, unassigned 403, single assignment substituted,
  multiple + `null` → 400, zero assignments → 403 and `" AND 1=0"`.
- Non-OWNER roles (`ACCOUNTANT`, …) are scoped too, so a role added to `SecurityConfig` later cannot
  arrive org-wide by accident.
- System context and SUPER_ADMIN are unrestricted; the assignment set resolves **once per request**.
- Tenant scoping: own-property tenant allowed, other-property denied, a tenant with no property row
  is owner-only.

Backend suite: **222 tests, 0 failures.**

### A trap the tests surfaced

A bare Mockito mock of the guard returns `unrestricted() == false` — the production-safe default —
which silently sends existing owner tests down the *scoped* branch. `TenantServiceTest` and
`OccupancyServiceTest` therefore stub `unrestricted() → true` explicitly, and the controller tests
use a `passThroughGuard()` helper that returns the `propertyId` it was handed. Without it a bare mock
returns `null` and quietly turns every scoped request into an org-wide one.

## 7. The property list and dashboard

Scoping `FacilityService.tree()` was **not** sufficient, and this is worth remembering when adding a
screen: the app does not read its property list from the tree. It reads
`GET /api/owner/properties`, which was unscoped — so a manager was shown a property they had no
access to, and tapping it produced a 403 on every panel instead of the property simply not being
there. That endpoint now filters on the scope.

`DashboardService.ownerDashboard` keeps **two code paths on purpose**. An owner keeps the original JPA
counts untouched, so numbers they have been reading for months cannot shift because of this feature.
A scoped login takes a SQL path that confines all six figures to their properties: beds by walking
bed → room → floor → property through `facility_group_member`, and rent/revenue through the tenant
set (neither table carries a facility id). An unassigned login gets **zeroes with no query issued** —
an empty `IN ()` would be a SQL error, and dropping the predicate would have reported the whole
organization.

## 8. Known gaps

Honest inventory. None of these leak a **list**; each is a by-id read/write where a manager who
guesses or learns an id from another property could act on it.

- **Single entities by id, with no `propertyId` in the request**: invoice, payment, expense, staff
  member, complaint, notice, temp-stay, scheduled transfer. The list endpoints that surface these ids
  are scoped, so a manager has no in-app way to obtain one — but the ids are sequential and
  guessable. Closing this needs an "owning property of entity X" resolver per module.
- **Org-level settings are not restricted.** Per the "full access to their property" decision, a
  manager can change `GET/PUT /api/billing/config`, which is per-**organization** and therefore
  affects every property. Worth revisiting.
- **Multi-property managers get a 400** on aggregate endpoints instead of a combined view (§3).
- **Bulk CSV upload** is super-admin-only and unrestricted by design.
