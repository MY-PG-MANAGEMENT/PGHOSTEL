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

Swagger UI is served at `http://localhost:8080/swagger-ui.html` when the server is running.

### Configuration

`src/main/resources/application.yml` — expects a local MySQL on port 3306, database `pg_manager`, user `root`/`root`. The JWT secret and token lifetimes (`access-token-minutes: 30`, `refresh-token-days: 14`) live under `app.security`.

### Database Migrations

Flyway migrations live in `src/main/resources/db/migration/`. Always add new migrations as `V<n>__description.sql` — never edit existing ones. `ddl-auto` is `validate`, so Hibernate will reject schema drift.

### Package Structure

Each feature is a self-contained package under `com.pgmanager`. The key cross-cutting concepts:

**`party` + `facility` — the two backbone models**

- `party` is a generic actor (PERSON or future ORGANIZATION). `person` holds human details with a 1:1 FK to `party`.
- `facility` is a single polymorphic table covering the full hierarchy: ORGANIZATION → PROPERTY → FLOOR → ROOM → BED. The `facility_type_id` column distinguishes levels. Parent–child relationships are in `facility_group_member` (dated, allowing history). An owner's organization is itself a `Facility` row with `facility_type_id = ORGANIZATION`.

**`facility_party` — occupancy join table**

- Links a `party` to a `facility` with a role and a date range (`from_date` / `thru_date`). Active bed assignments have a null `thru_date`.

**`security`**

- `JwtAuthenticationFilter` extracts the JWT on every request and populates `AppUserPrincipal` (contains `userLoginId`, `organizationId`, `roleTypeId`).
- `RoleType` constants (SUPER_ADMIN, OWNER, PROPERTY_MANAGER, MANAGER, ACCOUNTANT, SUPPORT, VIEWER, TENANT).
- Role-based URL guards are in `SecurityConfig`; fine-grained method-level guards use `@PreAuthorize` enabled by `@EnableMethodSecurity`.
- All owner business APIs derive `organizationId` from the authenticated principal — never trust a client-supplied org ID.

**Common patterns**

- All controllers return `ApiResponse<T>` (`{ success, message, data }`).
- Entities extend `BaseEntity` (provides `createdAt`, `updatedAt` via JPA auditing).
- `GlobalExceptionHandler` maps `NotFoundException` → 404, `BadRequestException` → 400.
- Refresh tokens are stored as SHA-256 hashes (`HashUtil.sha256`); raw tokens are never persisted.
- `AuditService.log(...)` should be called for significant state changes.

## Flutter Owner App

### Commands (run from `owner_app/`)

```bash
flutter run                    # run on connected device/emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api   # override API base
flutter test                   # run all widget/unit tests
flutter build apk              # Android release APK
flutter build ios              # iOS release
flutter analyze                # lint
```

The default API base URL is `http://192.168.1.34:8080/api` (local network dev machine). Override with `--dart-define=API_BASE_URL=<url>`.

### Architecture

**State management** — single `AppState extends ChangeNotifier` (Provider). It owns `ApiClient` and `AuthRepository`, holds auth state (`isLoggedIn`, `roleTypeId`), and is provided at the root.

**Navigation** — `go_router` with a `redirect` guard driven by `AppState`. Unauthenticated users are sent to `/login`; SUPER_ADMIN users are locked to `/admin`.

**API layer**

- `ApiClient` — low-level HTTP wrapper that reads the `accessToken` from `FlutterSecureStorage`, injects `Authorization: Bearer`, and on 401 automatically calls `/auth/refresh` then retries once before giving up.
- `AuthRepository` — wraps `/auth/login` and `/auth/register-owner`, persists `accessToken`, `refreshToken`, `organizationId`, and `roleTypeId` to secure storage.
- Response shape expected: `{ success: bool, message: string, data: T }`.

**Layout** — `AppShell` provides responsive chrome: sidebar nav at ≥900 px width, bottom `NavigationBar` + `Drawer` below that. Screens that use the shell wrap their content in `AppShell`.

**Biometric** — `AppState.setBiometricEnabled` / `biometricLogin` use `local_auth`. When biometric is enabled, `restoreSession` marks the user as *not* logged in (requiring a fingerprint/PIN unlock), even if an access token is present.

## Multi-tenancy

Shared-database multi-tenancy. Each organization is a `Facility(ORGANIZATION)`. Every business table carries `organization_id`. The backend enforces org scope from the JWT principal — controllers must not accept org IDs from request bodies for owner actions.
