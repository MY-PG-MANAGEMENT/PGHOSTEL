# Test Plan & Coverage Matrix

How we test PG Manager, screen by screen and endpoint by endpoint. Legend:
`✅` covered now · `🟡` partial · `⬜` planned · `🔴` needs Docker (CI only).

## How to run

```bash
# Backend (no Docker needed for unit/slice/validation tests)
cd backend && ./gradlew test

# Backend full integration (needs Docker for Testcontainers MySQL)
cd backend && ./gradlew test            # integration tests auto-run when Docker is present,
                                         # and auto-skip (not fail) when it is absent

# Flutter
cd owner_app && flutter test
```

## Test layers (the pyramid)

| Layer | Tool | Scope | Docker? |
|---|---|---|---|
| Unit — validation | Jakarta `Validator` | DTO constraints | no |
| Unit — logic | Mockito | Service business rules | no |
| Slice — contract | standalone `MockMvc` | Controller `@Valid` + delegation | no |
| Integration | Testcontainers + Flyway + `MockMvc` | Full stack vs real MySQL | **yes (CI)** |
| Widget | `flutter_test` | Screen render / validation / states | no |

## The scenario template (apply to every screen & endpoint)

```
Render states:  loading · data · empty · error
Each field:     valid · required-missing · format-invalid · boundary
Actions:        submit-success · submit-failure(server) · cancel
Navigation:     lands correctly · guard/redirect (auth, role)
Permissions:    allowed role · forbidden role (403)
```

---

## Backend — endpoint × scenario (critical paths first)

### Auth (`/api/auth/**`) — permitAll
| Endpoint | Happy | Validation | Bad creds / dup | Where |
|---|---|---|---|---|
| POST register-owner | 🔴 | ✅ | 🔴 | `AuthControllerTest`, `DtoValidationTest`, `AuthFlowIntegrationTest` |
| POST login | 🔴 | ✅ | 🔴 | `AuthControllerTest`, `AuthFlowIntegrationTest` |
| POST refresh | ⬜ | ⬜ | ⬜ | |
| POST logout | ⬜ | ⬜ | ⬜ | |

### Tenants (`/api/tenants`)
| Endpoint | Happy | Validation | Org-scope | Where |
|---|---|---|---|---|
| POST / (create) | ✅ | ✅ | ✅ (dup mobile, foreign property) | `TenantServiceTest`, `TenantControllerTest`, `DtoValidationTest` |
| GET / (list) | 🟡 | — | ⬜ | covered indirectly via service |
| GET /{id} | ✅ | — | ✅ (foreign tenant → 404) | `TenantServiceTest` |
| PUT/PATCH /{id} | 🟡 | ✅ | ✅ (assertTenantInOrganization) | `TenantServiceTest` (org-scope) |

### Occupancy (`/api/occupancy`)
| Endpoint | Happy | Guards | Where |
|---|---|---|---|
| POST assign-bed | ✅ | ✅ tenant-not-in-org, bed-not-found, not-a-bed, tenant-has-bed, bed-occupied | `OccupancyServiceTest`, `DtoValidationTest` |
| POST checkout | ✅ | ✅ no-active-occupancy + delegation + missing-partyId | `OccupancyServiceTest`, `OccupancyControllerTest` |
| POST transfer-bed | ✅ | ✅ no-active-occupancy, new-bed-occupied, ends-old+creates-new | `OccupancyServiceTest` |
| PUT expected-checkout | ✅ | ✅ bad-date-format, after-next-payment-date, no-active-assignment(404), clear-date | `OccupancyControllerTest` |

### Billing / Payments
| Endpoint | Happy | Guards / validation | Where |
|---|---|---|---|
| POST payments (JPA `PaymentService`) | ✅ | ✅ amount>0, party/mode required, rent-settle PAID/PARTIAL, unknown-rent 404 | `PaymentServiceTest`, `PaymentControllerTest`, `DtoValidationTest` |
| POST billing/payments (collect+allocate) | ✅✅ | ✅ unit: PAID/PARTIAL math, exceeds-balance 400, unknown-invoice 404, missing-idempotency/zero-amount 400 · 🔴 integration: real DB persist + status + idempotent-replay | `BillingControllerTest`, `BillingIntegrationTest` |
| GET billing/dashboard | ⬜ | aggregate SQL — integration test | |
| POST billing refund / write-off / mark-paid | ⬜ | clone `BillingIntegrationTest` | |

### Super Admin (`/api/super-admin/**`) — SUPER_ADMIN only
| Endpoint | Status | Where |
|---|---|---|
| PATCH organizations/{id}/status | ✅ status whitelist (invalid 400, valid ok, missing 404) | `SuperAdminControllerTest` |
| GET organizations/{id} | 🟡 queries parameterized; integration test pending | |
| POST broadcast | ✅ blank-title 400, single-org send | `SuperAdminControllerTest` |
| role/403 enforcement | 🔴 OWNER token → 403, anonymous → 401 (real filter chain, CI) | `SuperAdminAccessIntegrationTest` |

---

## Flutter — screen × scenario

| Screen | Render | Validation | Submit | Status |
|---|---|---|---|---|
| Login | ✅ | ✅ | ✅ | `test/login_screen_test.dart` (4) — empty/valid/failure→SnackBar/navigate |
| Register | ✅ | ✅ | ✅ | `test/register_screen_test.dart` (5) — all fields, mismatch, navigate |
| Forgot password | ⬜ | ⬜ | ⬜ | |
| Onboarding wizard | ⬜ | ⬜ | ⬜ | |
| Dashboard | ⬜ | — | — | loading/error/empty |
| Properties | ⬜ | 🟡 | ⬜ | |
| Property workspace | ⬜ | — | — | |
| Rooms / Assign bed | ⬜ | 🟡 | ⬜ | |
| Tenants | ✅ | 🟡 | ⬜ | `test/tenant_screen_test.dart` (5) — loading/data/error/retry/empty via `FakeApiClient` |
| Billing | ⬜ | 🟡 | ⬜ | money flows — high priority |
| Checkout sheet | ⬜ | ⬜ | ⬜ | |
| Notifications | ⬜ | — | — | |
| Settings / Profile / Password | ⬜ | 🟡 | ⬜ | |
| Admin (8 sections) | ⬜ | ⬜ | ⬜ | |
| ErrorRetryView (app-wide) | ✅ | — | — | `test/error_retry_view_test.dart` (6) — network/server/generic + loading→data/error |
| **Validators util** | — | ✅ | — | `test/validators_test.dart` (29 tests) |

> Flutter harness: `test/support/test_harness.dart` provides `FakeAppState`, `FakeApiClient` (per-path `stubGet`/`stubGetError`/`stubGetPending`/`stubPost`), `pumpScreen(...)` and `pumpDataScreen(...)`. `AppState` now has a constructor `AppState({ApiClient? apiClient})` (default = real client, unchanged behavior) so data screens can be tested with a fake — used by `tenant_screen_test.dart`.

---

## What's covered today (baseline)

- **Backend: 69 tests passing + 8 skipped (Docker/CI) = 77** — `DtoValidationTest` (21), `OccupancyServiceTest` (11), `OccupancyControllerTest` (6), `BillingControllerTest` (6), `TenantServiceTest` (5), `PaymentServiceTest` (4), `PaymentControllerTest` (4), `AuthControllerTest` (4), `SuperAdminControllerTest` (5), `TenantControllerTest` (3); integration (Docker/CI): `AuthFlowIntegrationTest` (2), `BillingIntegrationTest` (4), `SuperAdminAccessIntegrationTest` (2).
- **Flutter: 49 tests passing** — `validators_test.dart` (29), `error_retry_view_test.dart` (6), `tenant_screen_test.dart` (5), `register_screen_test.dart` (5), `login_screen_test.dart` (4).

## Next increments (priority order)

1. ~~Billing/payment money correctness~~ ✅ unit + integration done.
2. ~~`expected-checkout` next-payment-date rule~~ ✅ done.
3. ~~Super-admin status whitelist + broadcast + role/403~~ ✅ done (403/401 in integration).
4. ~~Inject `ApiClient`; Flutter data-screen tests~~ ✅ done (TenantScreen). Extend to billing/assign-bed screens.
5. Billing dashboard / refund / write-off / mark-paid integration tests (clone `BillingIntegrationTest`).
6. Onboarding wizard + full assign-bed→invoice→collect end-to-end integration test.
7. Wire `./gradlew test` + `flutter test` into CI (where Docker enables the integration layer).
