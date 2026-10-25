# Feature Matrix — what each login can do

Every feature available to each login type, and every option inside it. Super admin is excluded.

Derived from the controllers, `SecurityConfig`, `PropertyAccessGuard` and the Flutter screens — not
from the roadmap docs. Where the code and the intent differ, the code wins and it is flagged.

## Login types that actually exist

| Login | How it is created | How it signs in |
|---|---|---|
| **OWNER** | Super admin provisions the org + its owner login | Username (or 10-digit mobile) + password |
| **PROPERTY_MANAGER** | Owner, from Settings → Team → Managers | **Bare 10-digit mobile** + password |
| **TENANT** | Auto-provisioned when a tenant is added — **only if the org has Tenant Login enabled** | Mobile + password, with an org picker if the mobile exists in several orgs |

`RoleType` also declares **MANAGER, ACCOUNTANT, SUPPORT and VIEWER**, and they appear in
`SecurityConfig` and in several `@PreAuthorize` lists — but **nothing in the codebase creates a login
with those roles**. `PropertyManagerController` only ever writes `PROPERTY_MANAGER`. They are
reserved labels today, not usable logins.

New PROPERTY_MANAGER and TENANT logins both start on the temp password **`abc@123`** with
`must_change_password`, so the first screen after sign-in is Change Password.

---

# 1. OWNER

Unrestricted across the whole organization. Uses the owner app (indigo theme).

### 1.1 Dashboard — `/dashboard`
- Org stat row: **Properties · Total Beds · Occupied · Monthly revenue**
- Property cards — per property: floors, Rooms, Occupied, Vacant; tap to open the workspace
- **Add Property**
- Notification bell with unread badge → notifications list
- Menu button → Settings
- **Analytics** (`/dashboard/analytics`) — occupancy and collection charts
- Onboarding wizard (`/onboarding`) for first-time setup

### 1.2 Property workspace — tap any property card
Four bottom-nav tabs: **Overview · Tenants · Payments · Reports**.

**Overview tab**
- Hero: Floors / Rooms / Beds / Occupied Beds
- **Total Tenants** and **Vacant Beds** (with occupancy %) cards
- **Smart Insights** panel
- Quick Actions:
  - **Floors & Rooms** — the structure editor
  - **Temporary Stay** — short-term guests
  - **Expenses** — locked to this property
  - **Transactions** — money in & out
  - **Staff** — locked to this property
  - **Price Master** — rent & deposit per sharing type
  - **Complaints** — *only shown when the org has Tenant Login enabled*
- Overflow ⋮ → **Deleted tenants** (when on the Tenants tab)

### 1.3 Property structure (Floors & Rooms)
- Floor chips to switch floor; per-floor room list with each room's beds and occupant names
- **Add** floor / room / bed (`POST /api/facilities`)
- **Edit** a floor/room/bed (`PUT /api/facilities/{id}`) — including sharing type, AC flag, capacity
- **Delete Floor** / **Delete Room** / delete bed — every delete runs a **delete-check** first, so a
  blocked delete is one popup carrying the server's reason (occupied bed, or a pending transfer
  targeting it), never a confirm followed by an error
- Reduce sharing → trims excess vacant beds
- **Vacant Beds** sheet — two tabs **Vacant / Upcoming Vacant**, search, and a filter panel
  (floor, room, sharing type, expected checkout); **Assign** button per bed
- Read-only views: floors, rooms, beds, room summary, property stats, property report
- **Price Master** — per sharing type: monthly rent, security deposit, AC charges, **per-day price**

### 1.4 Tenants
- List with **search** (name/mobile) and **ALL / ACTIVE / INACTIVE** filters
- **Add Tenant** — full personal details (name, mobile, gender, email, Aadhaar, DOB, address,
  vehicle) plus a **Tenant Self Check-in QR** banner that lets the tenant fill their own details
- Tenant detail, three tabs:
  - **Profile** — identity, tenancy details (move-in, monthly rent, next payment, security deposit,
    checkout date); actions **Call**, **WhatsApp**, **Shift**, **Update Checkout Date**,
    **Change Rent**, **Checkout Tenant**, and **Delete** (only when they hold no bed)
  - **Payments** — that tenant's invoices and receipts
  - **Details** — Emergency Contact, Employment Details, Documents (each with Edit)
- **Edit Profile** — one form, one Save (a PUT that replaces the whole person row)
- **Delete = archive** — the tenant disappears from the lists; invoices, payments and history are
  untouched, and re-registering the same mobile **restores the same tenant**
- **Bulk delete** — multi-select on the INACTIVE filter
- **Deleted tenants** screen — search and **Restore**
- **Self check-in link / QR** per property
- **Generate Tenant Logins** (Settings → Tenant Portal) — only visible when the org has the feature
- Admissions: create, **sign** (raises the move-in invoice), agreements
- Checkout: create and **settle**

### 1.5 Occupancy
- **Assign bed** — with monthly rent, AC charges, security deposit, move-in date
- **Transfer bed** — same sharing type applies immediately; a **different** sharing type is
  scheduled for the next billing anniversary instead
- **Scheduled transfers** — list per tenant, and **cancel**
- **Temporary stay** — create (bed, dates, total), **edit** an active stay, **end** it, or
  **make permanent** (converts to a normal tenancy and starts billing)
- **Checkout** — with a **checkout preview** showing which invoices will be dropped, and an
  optional **deposit refund** (amount + method)
- **Expected checkout date** and **monthly rent** changes
- Occupancy **history** per tenant

### 1.6 Billing
- **Dashboard tab** — Total Collected, Received Today, Outstanding Today, Overdue, Recent Payments
- **Invoices tab** — search by tenant; filters **ALL / PENDING / PAID / PARTIAL / CANCELLED**
- **Invoice detail sheet**:
  - Charge breakdown (PG Rent, AC Charges, Security Deposit) and Total, Paid, Balance
  - **WhatsApp** — opens WhatsApp with the payment reminder pre-filled; the owner presses Send
  - **Edit** — re-price each charge line (pending, unpaid invoices only)
  - **Delete** — a soft-cancel, and **Restore** puts it back to pending
  - **Collect Payment**
- **Collect Payment** — mode (Cash / UPI / Bank / Cheque), amount, reference, notes
- **Generate invoices** — raises the invoices **due today** (manual fallback; the scheduler does
  this automatically at 01:00)
- **Payments tab** — receipt history with search and a date range
- Mark paid, write off, record advances, payment receipt, refund a payment
- **Invoice Automation** settings — lead days, checkout grace days, auto-generate on/off

### 1.7 Expenses
- Landing page: month selector, summary with month-on-month change, **Approvals** and
  **Transactions** chips, Category Overview, Smart Insights
- Activity screen: **Pending** (approve / reject) and **Transactions** (filter, edit, delete) pages
- **Add Expense** — title, category, amount, date, payment method, vendor, notes, property, and an
  optional "requires approval" switch
- **Edit** / **Delete** an expense (blocked for salary expenses owned by the Staff module)
- **Set Budget** — overall or per category, org-wide or per property
- **Petty cash** — manual IN / OUT entries; approved CASH expenses mirror in automatically

### 1.8 Staff (payroll)
- Month switcher, payroll summary (active count, monthly payroll, paid/due)
- **Add / Edit staff** (profession, salary, active toggle), **deactivate**
- **Pay** one, **Pay Selected**, or **Pay All** — with a payment method
- Per-staff **salary history**, and a **call** button

### 1.9 Transactions
- Unified money-in / money-out ledger for a month, with In/Out filters and a summary
  (total in, total out, net)

### 1.10 Reports — download only
Four cards, each producing a **PDF**:
- **Rent Collection Report** (month)
- **Outstanding Due Report** (month, cumulative arrears)
- **Expense Report** (month + category)
- **Profit & Loss Report** (from/to date range)

### 1.11 Complaints and Notices
- **Complaints** — list, detail, change status (each transition notifies the tenant)
- **Notices** — list, create (fans out notifications to tenants), update

### 1.12 Notifications
- List with **ACTIVE / ARCHIVED / UNREAD / IMPORTANT** filters and paging
- Mark read, archive, toggle important, delete archived
- **Notification Settings** — per-category in-app toggles. These genuinely gate delivery, and are
  **opt-in**: a category with no stored preference does not notify

### 1.13 Team — **owner only**
- **Managers** — list each manager with their mobile and assigned properties
- **Add Manager** — returns the temp password once
- **Edit properties** (which properties that login may see)
- **Activate / deactivate**, **Reset password** — both revoke refresh tokens

### 1.14 Account and settings
- Profile information, **Change Password**, **Biometric & Security** unlock
- Theme & Appearance, Language
- Notification Settings, Invoice Automation, Tenant Portal
- Devices and sessions
- **Forgot / reset password** from the login screen (no auth needed)

---

# 2. PROPERTY_MANAGER

**Same app and the same screens as the owner** — there is no separate manager UI. The difference is
*scope*, plus two hard exclusions.

### What is identical to the owner
Everything in §1.2 – §1.12 and §1.14, restricted to their assigned properties: property workspace,
structure editing and deletes, tenants and their whole lifecycle, occupancy, billing and payments,
expenses, staff, transactions, reports, complaints, notices, notifications, and their own account
settings.

### What is different

| | Behaviour |
|---|---|
| **Sign-in** | Their bare **10-digit mobile**. The username is stored as `{mobile}@m{orgId}` because usernames are globally unique, but nobody ever types that |
| **First login** | Forced Change Password from `abc@123` |
| **Property list** | `GET /api/owner/properties` returns **only assigned properties** — an unassigned one is absent from the switcher, not merely un-tappable |
| **Facility tree** | Pruned to their properties |
| **Tenant list** | Redirected to their property's list |
| **Dashboard** | Scoped counts; an **unassigned** login sees zeroes, and no query is even issued |
| **Several properties, none chosen** | **400 "Select a property"** rather than silently widening to the whole org |
| **Someone else's property** | **403** |
| **Assigned nothing** | Sees nothing at all — an empty assignment is never read as "unrestricted" |

### What a property manager cannot do
- **Team → Managers is refused (403).** Deliberate: a manager who could edit assignments could grant
  themselves the properties they were denied.
- Anything outside their assigned properties, at every by-id entry point (tenant, bed, invoice,
  facility) — not just in list queries.

---

# 3. TENANT

A separate portal inside the same app (purple theme), reached automatically when a TENANT signs in.
**Opt-in per organization** — if the org does not have Tenant Login enabled, no tenant login exists.

### 3.1 Dashboard — `/tenant`
- Property card — where they stay
- **Due card** — what they owe and by when
- Quick action cards
- Latest complaint and latest notice tiles
- Notification bell

### 3.2 Profile
- Their own details
- **Change password** (forced on first sign-in)

### 3.3 Payments
- Current dues
- Payment history, with **View all** for the full list

### 3.4 Complaints
- List of their complaints
- **Raise** a complaint
- Complaint detail with a **status timeline** as the owner works it

### 3.5 Notices
- List of notices published by the PG
- Notice detail

### 3.6 Notifications
- List, and mark as read

### What a tenant cannot do
Everything else. The portal is read-plus-two-writes: change password, and raise a complaint. Tenants
cannot see other tenants, rooms, beds, rent settings, invoices belonging to anyone else, expenses,
staff, reports, or any owner screen. `/api/tenant/**` is the only API surface open to them, and the
org and party are taken from their token, never from the request.

Tenants also have **no notification preferences UI** — so tenant notifications are opt-**out** on the
server (they are delivered unless a preference explicitly disables them), the opposite of the owner's
opt-in rule. Applying the owner's rule here would silence every tenant with no way to turn it back on.

---

# 4. Things worth knowing

1. **Four declared roles have no login path.** MANAGER, ACCOUNTANT, SUPPORT and VIEWER are in
   `SecurityConfig` and in `@PreAuthorize` lists, but nothing creates such a login. Any feature
   documented as "OWNER/MANAGER/ACCOUNTANT" is in practice owner + property manager only.
2. **A deactivated organization cannot sign in** — owner, manager and tenant alike get a 403, and
   every refresh token in the org is revoked. An already-signed-in session survives until its access
   token expires (up to 30 minutes).
3. **The Staff screen is payroll, not access control.** Staff records have no logins. Granting
   someone access is Settings → Team → **Managers**.
4. **Deleting a tenant does not delete anything** — it archives. Invoices, payments and history stay,
   and re-registering the same mobile restores the same tenant with their history intact.
5. **Deleting an invoice is a soft-cancel and is reversible** (Restore). Deleting an *expense* is a
   hard delete. Deleting a floor/room/bed is a real delete of the whole subtree, refused while any
   bed in it is occupied.
