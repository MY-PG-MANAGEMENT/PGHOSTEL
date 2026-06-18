# Implementation Notes

## Local Setup Later

Install later:

- JDK 21.
- Gradle or use a generated Gradle wrapper later.
- MySQL 8+.
- Flutter SDK.

No build, test, dependency install, or server run was performed during scaffold creation.

## Backend Configuration

Update `backend/src/main/resources/application.yml` before running:

- MySQL username.
- MySQL password.
- Database URL if needed.
- JWT secret for non-local environments.

## Suggested First Run Later

From `PG_ManagerNew/backend`:

```bash
gradle bootRun
```

From `PG_ManagerNew/owner_app`:

```bash
flutter pub get
flutter run
```

For Android emulator, change the Flutter API base URL from `http://localhost:8080/api` to `http://10.0.2.2:8080/api`.

## Deferred Items

- Docker and Docker Compose.
- React Admin Dashboard.
- Flutter Tenant App.
- Expense workflows.
- Staff workflows.
- Reports.
- Notifications.
- WhatsApp integration.
- Online payment gateway.
- Super-admin UI.

## Development Sequence

1. Install required software.
2. Configure MySQL.
3. Run backend Flyway migrations by starting Spring Boot.
4. Test auth APIs through Swagger.
5. Connect Flutter app to backend URL.
6. Run owner journey: register, onboard, create tenant, assign bed, create rent, record payment.
