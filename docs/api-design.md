# API Design

All phase 1 APIs are JSON REST APIs under `/api`.

## Authentication

- `POST /api/auth/register-owner`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`

## Owner

- `POST /api/owner/onboarding-wizard`
- `GET /api/owner/dashboard`
- `GET /api/owner/properties`

## Facility

- `GET /api/facilities/tree`
- `POST /api/facilities`
- `PUT /api/facilities/{facilityId}`
- `GET /api/properties/{propertyId}/floors`
- `GET /api/floors/{floorId}/rooms`
- `GET /api/rooms/{roomId}/beds`

## Tenant

- `POST /api/tenants`
- `GET /api/tenants`
- `GET /api/tenants/{partyId}`
- `PUT /api/tenants/{partyId}`

## Occupancy

- `POST /api/occupancy/assign-bed`
- `POST /api/occupancy/transfer-bed`
- `POST /api/occupancy/checkout`
- `GET /api/occupancy/history/{partyId}`

## Rent and Payment

- `POST /api/rents`
- `GET /api/rents`
- `POST /api/payments`
- `GET /api/payments`

## Future Super Admin

Reserve `/api/super-admin/**` for future super-admin APIs. These routes are already protected for the `SUPER_ADMIN` role.
