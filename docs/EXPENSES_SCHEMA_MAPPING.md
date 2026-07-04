# Expenses Screen — Database Mapping

Screen: `owner_app/lib/src/screens/expenses_screen.dart`.
Schema: `backend/src/main/resources/db/migration/V16__expenses.sql`.

The screen uses the app's standard light theme (`PgColors`). It renders:
summary, category overview, pending approvals, recent transactions (last 7
days), and insights. The dashboard payload additionally returns budget
utilization, the 6-month trend, and petty cash — computed but not currently
rendered by the UI (kept so those sections can return without backend work).

Entry points:
- **Org-level** — route `/expenses`; the property switcher pill is enabled and
  every section recalculates for the selected property.
- **Property-scoped** — the "Expenses" quick action on the Property Overview
  tab (`property_workspace_screen.dart`) pushes
  `ExpensesScreen(propertyId: ..., propertyName: ...)`; the scope pill is
  locked (lock icon) and all figures are that property's alone. When wiring
  the backend, this `propertyId` maps to `expense.property_facility_id` and
  the `?propertyId=` param on the dashboard endpoint (property-wise
  calculation = the same aggregate queries with `property_facility_id = ?`;
  org-wide = no property filter).

Three tables only: `expense`, `expense_budget`, `petty_cash_entry`. Everything
else on the screen is an aggregate query — no summary/trend/insight tables.

## Design decisions (what we did NOT create tables for)

| Concept | Instead of a table |
|---|---|
| Expense categories | String constants in code (`FOOD`, `SALARY`, `ELECTRICITY`, `MAINTENANCE`, `LAUNDRY`, `TRANSPORT`, `RENT`, `OTHERS`) — same pattern as `FacilityType` / `OccupancyRole` |
| Vendors | `expense.vendor_party_id` (optional FK to existing `party`) + `vendor_name` free text |
| Approval workflow | `expense.status` (`PENDING`/`APPROVED`/`REJECTED`/`PAID`) + `approved_by`, `approved_at` |
| Monthly summary, trends, budget %, insights | Aggregate SQL over `expense` (JdbcTemplate, same rationale as `BillingController`) |
| Petty-cash balance | Running `SUM` over `petty_cash_entry`; never stored |

## UI section → data source

| Screen section | Source |
|---|---|
| Expenses This Month | `SELECT SUM(amount) FROM expense WHERE organization_id=? AND expense_date BETWEEN ? AND ? AND status IN ('APPROVED','PAID')` (+ optional `property_facility_id=?`) |
| Budget Remaining | `expense_budget` row for `(org, property, 'ALL', 'YYYY-MM')` minus the sum above |
| % vs last month | Same sum for the previous month; delta computed in service code |
| Set Budget | UPSERT into `expense_budget` (unique key `uk_budget_scope`) |
| Category overview (stacked bar + rows) | `SELECT category, SUM(amount) FROM expense ... GROUP BY category` |
| Budget utilization cards | Join of the category sums against `expense_budget` rows where `category <> 'ALL'` |
| Monthly trend (Expense line) | `SELECT DATE_FORMAT(expense_date,'%Y-%m'), SUM(amount) FROM expense ... GROUP BY 1` (last 6 months) |
| Monthly trend (Income line) | Existing billing/payment aggregates (`payment` / invoice tables) — no new table |
| Monthly trend (Profit) | Income − expense, computed in service code |
| Pending approvals card | `SELECT ... FROM expense WHERE status='PENDING'`; Approve/Reject = `UPDATE expense SET status=?, approved_by=?, approved_at=NOW()` |
| Recent transactions | `SELECT ... FROM expense WHERE status IN ('APPROVED','PAID') AND expense_date >= CURRENT_DATE - INTERVAL 6 DAY ORDER BY expense_date DESC LIMIT 20` (rolling last 7 days) |
| Petty cash summary | Opening = running sum before month start; Cash In/Out = month sums by `entry_type`; Balance = opening + in − out. `OUT` rows auto-insert (with `expense_id`) when a `CASH` expense is approved |
| AI insights | Derived in service code from the aggregates above (month-over-month category deltas, budget utilization thresholds) |

## Endpoints (implemented — `com.pgmanager.expense.ExpenseController`)

JdbcTemplate-based (same rationale as `BillingController`), org scope always
from `CurrentUser`, responses wrapped in `ApiResponse<T>`:

- `GET  /api/expenses/dashboard?propertyId=&month=` — one round-trip returning all sections above (summary incl. MoM change %, categories, category budgets vs spend, 6-month expense/income/profit trend, pending approvals, recent transactions, petty cash, insights)
- `GET  /api/expenses?propertyId=&month=&status=&category=&page=&size=` — paginated list
- `POST /api/expenses` — create; status `APPROVED` unless `requiresApproval: true` (then `PENDING`); an approved `CASH` expense auto-inserts a petty-cash `OUT` row (idempotent per expense)
- `PATCH /api/expenses/{id}/status` — `APPROVED`/`REJECTED`, only from `PENDING`
- `PUT  /api/expenses/budget` — upsert a budget row (`category` omitted/`ALL` = overall)
- `POST /api/expenses/petty-cash` — manual `IN`/`OUT` entry; returns the updated month summary

Income in the trend comes from `payment` rows (`status='RECEIVED'`), property-scoped
via TENANT `facility_party` membership — the same filter `BillingController` uses.
Insights are heuristics over the aggregates (category MoM rises ≥15%, overall budget
utilization ≥80%, potential savings). All writes go through `AuditService.log`.
