# Tenant Module

Complete, production-ready tenant self-service module for PGHOSTEL: opt-in tenant login
(Super-Admin controlled), an automatic login lifecycle, tenant-facing REST APIs, and a
tenant experience inside the existing Flutter app (Purple/White Material 3, Quick-Action
navigation).

---

## 1. Roles & feature control

| Role | Capabilities |
|------|--------------|
| **Super Admin** | Creates organizations. **Only** the Super Admin enables/disables the *Tenant Login* feature per org. |
| **Owner / Manager** | Creates tenants, uploads Excel, allocates rooms, manages complaints & notices, triggers bulk *Generate Tenant Logins*. |
| **Tenant** | Login, view profile, view payments, raise complaints & track status, read notices, receive notifications. **Cannot** see any other tenant's data. |

Tenant Login is **disabled by default**. It is stored as an `organization_feature` row keyed
by `feature_master.feature_code = 'TENANT_LOGIN'` (V22 seed) — identical opt-in mechanism to
the messaging channels. Backend gate: `tenant/TenantLoginPolicy.enabled(orgId)`.

### Enablement workflow
```
Super Admin ──creates──▶ Organization (Tenant Login = DISABLED)
      │
      └──enables Tenant Login──▶ org can now provision tenant logins
```

---

## 2. Login lifecycle & business rules

Username scheme: **`{mobileNumber}@{organizationId}`** — globally unique (satisfies the
`user_login.username` constraint) while allowing the same mobile to hold independent logins
in different orgs. Temporary password for every auto-created / reactivated login: **`abc@123`**
(BCrypt-hashed), with `must_change_password = 1` forcing a first-login reset.

### Case 1 — Tenant Login disabled
Owner can create tenants / upload Excel / allocate rooms. **No login accounts are created.**
Tenants cannot access the app.

### Case 2 — Tenant Login enabled
Whenever a tenant is created manually **or** via Excel upload **or** via self check-in
(all funnel through `TenantService.create`), the system auto-provisions a login: username,
temp password `abc@123`, status `ACTIVE`.

### Case 3 — Existing org enables Tenant Login later
Owner runs **Generate Tenant Login Accounts** (`POST /api/tenants/generate-logins`):
- Creates logins only for tenants without one.
- Skips inactive tenants, checked-out tenants, and tenants who already have an active login.
- Returns a progress summary `{total, created, skippedExisting, skippedInactive, skippedCheckedOut}`.

### Login-generation logic (`TenantLoginService.provisionForTenant`)
```
Tenant created/uploaded
        │
Tenant Login enabled? ──no──▶ stop
        │ yes
Search user_login by (organizationId, mobileNumber)
        │
        ├─ active login exists   → reuse it (re-point party_id to newest record); never duplicate
        ├─ only inactive exists  → REACTIVATE (status ACTIVE, clear reason, reset pw abc@123, force change)
        └─ none                  → CREATE new ACTIVE login (temp pw, force change)
```

### Checkout (`OccupancyService.checkout` → `TenantLoginService.disableForCheckout`)
```
Tenant checks out
    → user_login.status = INACTIVE, disabled_reason = CHECKED_OUT
    → all refresh_token rows revoked (sessions/tokens invalidated)
    → login row is NOT deleted
```
A checked-out tenant cannot log in (`AppUserPrincipal.isEnabled()` is false for non-ACTIVE).

### Rejoin & multi-org
- **Rejoin same org** → the inactive login is reactivated (not recreated): status ACTIVE,
  reason cleared, password reset, force change, `party_id` re-pointed to the new tenant record.
- **Join a different org** → org A login stays INACTIVE; a brand-new login is created for org B.
  Same mobile lives in both orgs with full data isolation.

---

## 3. Database design (V22)

New migration `V22__tenant_login_complaints_notices.sql`:

- **`user_login`** += `disabled_reason VARCHAR(40)`, `must_change_password BOOLEAN`, `last_login_at TIMESTAMP(6)`.
- **`feature_master`** seed `TENANT_LOGIN`.
- **`notification_category`** seed `COMPLAINT`, `NOTICE`.
- **`complaint`** — `complaint_id, organization_id, party_id, property_facility_id, category, title, description, priority, status, created_at, updated_at`.
- **`complaint_status_history`** — `complaint_id, from_status, to_status, note, changed_by_user_login_id, created_at`.
- **`notice`** — `organization_id, property_facility_id (NULL=org-wide), notice_type, title, body, published_at, expires_at, created_by_user_login_id, active`.
- **`notice_read`** — `notice_id, party_id, read_at`, `UNIQUE(notice_id, party_id)`.

ER diagram: [`docs/er/tenant-module.mmd`](er/tenant-module.mmd).

### Data mapping (tenant portal → tables)
| Screen field | Source |
|---|---|
| Room / Bed / Stay-since | active `facility_party` (role OCCUPANT) → `facility` (bed→room via `facility_group_member`) |
| Monthly rent / deposit | `facility_party.monthly_rent`, `.security_deposit` |
| Outstanding / due date | `invoice` (via `billing_account.party_id`), unpaid statuses |
| Payment history | `payment` (party_id) |
| Complaints | `complaint` + `complaint_status_history` |
| Notices | `notice` (+ `notice_read` for unread flag) |
| Notifications | `notification` + `notification_recipient` (party_id) |

---

## 4. REST API

### Auth (public — `/api/auth/**`)
`POST /api/auth/tenant/login`
```json
// request
{ "mobile": "9876543210", "password": "abc@123", "organizationId": 12 }  // organizationId optional

// success
{ "success": true, "message": "Logged in", "data": {
  "needsOrgSelection": false, "organizations": null,
  "auth": { "accessToken": "…", "refreshToken": "…", "organizationId": 12,
            "roleTypeId": "TENANT", "fullName": "Ravi", "mustChangePassword": true, "partyId": 501 } } }

// mobile registered in >1 org and none chosen
{ "success": true, "message": "Select your organization", "data": {
  "needsOrgSelection": true,
  "organizations": [ {"organizationId":10,"organizationName":"Sunrise PG"}, {"organizationId":20,"organizationName":"Nest PG"} ],
  "auth": null } }
```
Errors: `401 Invalid mobile number or password`. Token refresh reuses `POST /api/auth/refresh`.

### Tenant portal (`/api/tenant/**`, ROLE_TENANT; org + partyId from JWT only)
| Method & path | Purpose |
|---|---|
| `GET /api/tenant/dashboard` | greeting, property card, outstanding+due, recent payment, latest complaint/notice, unread counts |
| `GET /api/tenant/profile` | full profile (contact, stay, agreement, financials, status) |
| `GET /api/tenant/payments` | rent, deposit, outstanding, due date, paid-to-date, history, invoices |
| `POST /api/tenant/change-password` | `{oldPassword, newPassword}` — clears `must_change_password` |
| `GET /api/tenant/complaints` | list of my complaints |
| `POST /api/tenant/complaints` | `{category, title, description, priority}` (no image) |
| `GET /api/tenant/complaints/{id}` | detail + status timeline |
| `GET /api/tenant/notices` | active notices (each with `read_flag`) |
| `GET /api/tenant/notices/{id}` | detail (marks read) |
| `GET /api/tenant/notifications?limit=` | my notifications |
| `POST /api/tenant/notifications/{id}/read` | mark read |

### Owner-facing management
| Method & path | Purpose |
|---|---|
| `GET /api/tenants/login-feature` | `{enabled}` — drives the "Generate Logins" affordance |
| `POST /api/tenants/generate-logins` | bulk generation summary |
| `GET /api/complaints?propertyId=&status=` | triage list (tenant name, mobile) |
| `GET /api/complaints/{id}` | detail + history |
| `PATCH /api/complaints/{id}/status` | `{status, note}` → history + notifies tenant |
| `GET /api/notices?propertyId=` | list |
| `POST /api/notices` | `{propertyId?, type, title, body, expiresAt?}` → fan-out to tenants |
| `PATCH /api/notices/{id}` | deactivate |

### Super-admin (`/api/super-admin/**`, ROLE_SUPER_ADMIN)
| Method & path | Purpose |
|---|---|
| `GET /api/super-admin/organizations/{id}/tenant-login` | `{enabled}` |
| `PATCH /api/super-admin/organizations/{id}/tenant-login` | `{enabled}` toggle |

Standard error envelope (via `GlobalExceptionHandler`): `{ "success": false, "message": "...", "data": null }`
— `NotFoundException`→404, `BadRequestException`/validation→400, `AccessDeniedException`→403, 401 for bad credentials.

---

## 5. Security

- **JWT** access tokens + **refresh tokens** (SHA-256 hashed at rest), 30-min access / 14-day refresh (reused from the owner stack).
- **BCrypt** password hashing (`BCryptPasswordEncoder`); passwords never stored in plaintext.
- **Password reset on first login** via `must_change_password`.
- **RBAC**: `ROLE_TENANT` guards `/api/tenant/**` (SecurityConfig matcher placed before the generic `/api/**` guard which excludes TENANT). Owner complaint/notice endpoints use `@PreAuthorize`.
- **Session expiry / invalidation**: checkout revokes refresh tokens; a checked-out (INACTIVE) login is rejected by `AppUserPrincipal.isEnabled()`.
- **Org-level isolation**: every tenant query is scoped by `organizationId` + `partyId` taken from `CurrentUser` (JWT) — never from the request body.
- **Audit logging** (`AuditService`): `TENANT_LOGIN_CREATED/REACTIVATED/DISABLED`, `TENANT_LOGINS_GENERATED`, `TENANT_LOGIN_FEATURE_TOGGLED`, `TENANT_LOGIN`.

---

## 6. Validation rules
- One active login per tenant per organization; duplicates are reused, never created.
- Same mobile number may exist across multiple organizations (org-scoped username).
- Checked-out tenants cannot log in.
- Bulk generation skips inactive, checked-out, and already-provisioned tenants.
- Rejoin same org → reactivate; join another org → new login.
- Tenant login request: mobile is a 10-digit number; complaint title/description `@NotBlank`; new password ≥ 6 chars.

---

## 7. Mobile UI (inside `owner_app`, Purple #6C5CE7 + White, MD3)
Tenant screens live in `lib/src/screens/tenant/tenant_app.dart`, wrapped in `buildTenantTheme()`.
Navigation is via **Quick-Action cards only** — no bottom nav, no FAB.

Screens: Splash (shared) · Tenant Login (toggle on the shared login screen; org picker when needed) ·
Forgot Password (shared) · Dashboard · My Profile · Payments · Payment History · Complaint List ·
Raise Complaint (no image) · Complaint Details (status timeline) · Notices (unread highlighted) ·
Notice Details · Notifications · Empty / Loading / Session-Expired / No-Internet states
(`TenantData`, `TenantEmpty`, `_ErrorView`, `SessionExpiredScreen`).

Routing: `main.dart` redirect sends a logged-in TENANT to `/tenant`, keeps tenants off owner/admin
routes (and vice-versa), and forces `/tenant/change-password` while `mustChangePassword` is set.

---

## 8. Edge cases
- Same mobile in multiple orgs → login returns `needsOrgSelection` + org list; app shows a picker.
- Rejoin re-points `party_id` to the newest tenant record and resets the password.
- Feature disabled mid-session → existing tokens remain valid until expiry (acceptable); no *new* logins provisioned.
- Bulk generate is idempotent (skips existing active logins).
- Tenant with no bed yet → dashboard/profile show "awaiting room allocation".

## 9. Future scalability
- Online payments + receipt download (payments screen already flags "coming soon").
- Push notifications (FCM) reusing `notification_outbox` / `user_device.push_token`.
- Notice fan-out currently loops `notifyTenant` per tenant — batch into a single notification with bulk recipients for very large orgs.
- Complaint attachments (image upload) — deliberately excluded for v1.
