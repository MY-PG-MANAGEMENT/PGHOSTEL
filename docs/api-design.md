# API Design

All endpoints are JSON REST resources under `/api`; responses use `{ success, message, data }`. Owner requests derive organization scope from the authenticated JWT. Super-admin routes never accept a client-supplied owner scope implicitly.

## Authentication and account

- `POST /auth/register-owner`, `/auth/login`, `/auth/refresh`, `/auth/logout`
- `POST /auth/password/forgot`, `/auth/password/reset`
- `GET|PATCH /account/profile`, `POST /account/change-password`
- `GET|PATCH /account/preferences`, `GET /account/sessions`, `POST /account/devices`

Forgot-password responses do not reveal account existence. WhatsApp delivery is provider-ready but disabled.

## Inventory and tenancy

- Existing generic facility CRUD remains under `/facilities`, `/properties`, `/floors`, and `/rooms`.
- `/inventory/properties/{id}`, `/inventory/rooms/{id}`, `/inventory/beds/available`
- `GET|PUT /inventory/facilities/{id}/amenities`
- Existing tenant CRUD remains under `/tenants`.
- `/tenants/{partyId}/emergency-contacts`, `/employment`, `/documents`, `/agreements`
- `POST /tenants/{partyId}/admissions`, `/admissions/{id}/sign`, `/checkout`, `/checkout/{id}/settle`

Signing an admission atomically creates occupancy and a billing account. Media responses explicitly return `storageEnabled: false`.

## Billing

- `GET /billing/dashboard`, `/billing/invoices`, `/billing/invoices/{id}`
- `POST /billing/payments/cash` with a mandatory idempotency key
- `POST /billing/advances`, `/billing/payments/{id}/refunds`
- `GET /billing/payments/{id}/receipt`

V1 accepts cash only. A payment cannot exceed an invoice balance; excess money is recorded as advance.

## Notifications and platform

- `GET /notifications`, `/notifications/{id}`, `/notifications/preferences`
- `PATCH /notifications/{id}/read`, `/archive`, `/notifications/preferences`
- `DELETE /notifications/archives`, `POST /notifications`
- `/super-admin/dashboard`, `/organizations`, `/properties`, `/users`, `/roles`, `/plans`, `/reports/revenue`, `/audit-logs`, `/system-settings`

Interactive OpenAPI documentation is served at `/swagger-ui.html`.

