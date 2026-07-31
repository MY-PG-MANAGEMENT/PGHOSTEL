# Deployment

Spring Boot 3.3 / Java 21 · PostgreSQL 17 · Redis 7 · Docker

```
GitHub ──push to main──> GitHub Actions (tests) ──> Koyeb
                                                      │  builds deployment/Dockerfile
                                                      │  runs the container
                                                      │
                                       JDBC / RESP over TLS
                                                      │
                                    ┌─────────────────┴─────────────────┐
                                    ▼                                   ▼
                         Managed PostgreSQL                    Managed Redis
                      (Neon / Supabase / Koyeb)              (Upstash / Redis Cloud)
```

**There is no database container in production.** Koyeb runs the application only; the
database and cache are managed services reached over the internet. That is why this
directory has no `postgresql.conf`, no nginx, no certbot and no backup scripts — each
of those is now the provider's job, and keeping a second copy in the repo is how the
two drift apart until the committed one is quietly wrong.

| File | Purpose |
|---|---|
| `Dockerfile` | The production image. Koyeb builds this; `docker compose --profile app` builds it locally. |
| `docker-compose.yml` | **Local development only** — PostgreSQL + Redis, optionally the API. |
| `.env.example` | Local development overrides. Not production config. |

---

## 1. Local development

```bash
cd deployment
docker compose up -d                # PostgreSQL + Redis
cd ../backend && ./gradlew bootRun  # the API, from source
```

No `.env` needed. The compose defaults match `backend/src/main/resources/application.yml`
(`localhost:5432`, `postgres`/`postgres`, database `pg_manager`), so Flyway applies the
baseline on first boot and the app comes up on `http://localhost:8080`.

Both ports bind to `127.0.0.1`, not `0.0.0.0` — on a laptop that joins public networks,
the latter would put a database whose password is `postgres` on the LAN.

```bash
docker compose --profile app up -d --build   # run the built image too, as Koyeb does
docker compose down                          # stop, keep data
docker compose down -v                       # stop and DESTROY the local database
docker compose exec postgres psql -U postgres -d pg_manager
```

Swagger is at `http://localhost:8080/swagger-ui.html` in the default profile (off in
`prod`).

---

## 2. Provisioning the managed services

### PostgreSQL

Any managed PostgreSQL 16+ works — Neon, Supabase, Koyeb's own, RDS. Create a database
and copy the **JDBC** connection string.

Two things to check before pasting it into Koyeb:

- **`sslmode=require` must be present.** The database is reached across the public
  internet, and the PostgreSQL driver's default is `prefer`, which silently falls back
  to an *unencrypted* connection if the TLS handshake fails — carrying tenant data and
  payment rows in the clear. `verify-full` is stronger still if your provider documents
  a CA bundle.
- Append `reWriteBatchedInserts=true` if the provider has not. It collapses a JDBC
  batch into one multi-row INSERT, which is what makes the CSV bulk import and the
  `api_request_log` writes cheap.

```
jdbc:postgresql://HOST/pg_manager?sslmode=require&reWriteBatchedInserts=true&ApplicationName=pg-manager-backend
```

If the provider offers a **pooler** (PgBouncer) endpoint, prefer it and raise
`DB_POOL_MAX`. One caveat: a pooler in transaction mode cannot hold server-side
prepared statements across a checkout, so add `prepareThreshold=0` or you will hit
`prepared statement S_1 already exists` under concurrency.

Nothing else to set up — **Flyway creates the entire schema on first boot** from
`V1__baseline.sql`. Do not run schema SQL by hand; `ddl-auto` is `validate`, and
anything created out of band will fail startup.

### Redis

Optional. The cache is fail-open — `CacheErrorHandler` swallows failures and falls
through to a direct database read — so the app is correct without it, just slower on
the cached read models. Set `CACHE_ENABLED=false` to skip it entirely.

With Upstash or Redis Cloud, TLS is required and is on by default in the prod profile
(`REDIS_SSL`). Turning it off would send the password in the first command of the
connection in plaintext, leaking the credential itself rather than just cached values.

---

## 3. Deploying to Koyeb

1. **Create the service** from this GitHub repository.
   - Builder: **Dockerfile**, path `deployment/Dockerfile`, build context the
     repository root (the Dockerfile needs `backend/`).
   - **Turn OFF auto-deploy on push.** GitHub Actions triggers the deploy *after* the
     tests pass; leaving Koyeb's own trigger on bypasses that gate entirely and lets a
     red build reach production.

2. **Declare two ports.** This is the step people get wrong.

   | Port | Route | Purpose |
   |---|---|---|
   | `8080` | public, `/` | the API |
   | `9091` | **no route** | health check → `/actuator/health/readiness` |

   Actuator runs in Spring Boot's *management child context* on 9091, outside both
   `ApiLogFilter` and `SecurityConfig`. That is deliberate and load-bearing:

   - On 8080, every health probe would be written to `api_request_log` — the
     fastest-growing table in the schema — thousands of rows a day for nothing.
   - **A health check pointed at 8080 can never pass.** `SecurityConfig` ends with
     `anyRequest().authenticated()`, so `/actuator/health` returns **401**, the
     instance never goes healthy, and the deploy hangs and rolls back showing an auth
     error that looks nothing like a port misconfiguration.
   - 9091 must have **no public route**: everything on it is unauthenticated, so
     routing it would publish `/actuator/metrics` to the internet.

3. **Set the environment variables.**

   | Variable | Required | Notes |
   |---|---|---|
   | `SPRING_PROFILES_ACTIVE` | yes | `prod` |
   | `SPRING_DATASOURCE_URL` | yes | the JDBC string from §2, with `sslmode=require` |
   | `SPRING_DATASOURCE_USERNAME` | yes | |
   | `SPRING_DATASOURCE_PASSWORD` | yes | |
   | `JWT_SECRET` | yes | `openssl rand -base64 64 \| tr -d '\n'` |
   | `APP_PUBLIC_BASE_URL` | yes | your public HTTPS origin — see the warning below |
   | `REDIS_HOST` / `REDIS_PORT` / `REDIS_PASSWORD` | if caching | `REDIS_SSL` defaults to `true` |
   | `CACHE_ENABLED` | no | `false` to run without Redis |
   | `MANAGEMENT_PORT` | no | leave at `9091`; see step 2 |
   | `DB_POOL_MAX` | no | default `10`; real budget is this × instance count |
   | `MAIL_HOST` / `MAIL_USERNAME` / `MAIL_PASSWORD` / `EMAIL_ENABLED` | if sending mail | |
   | `SWAGGER_ENABLED` | no | **`false`**; see the warning below |
   | `TZ` | no | `Asia/Kolkata` |

   `JWT_SECRET`, `SPRING_DATASOURCE_URL` and `APP_PUBLIC_BASE_URL` have **no default**
   in `application-prod.yml` — a missing one fails the context at startup rather than
   silently running on the development value committed in `application.yml`.

4. **Set the GitHub secret and variable** the workflow needs: `KOYEB_API_TOKEN`
   (secret) and `KOYEB_SERVICE` (variable, as `app-name/service-name`).

5. Push to `main`.

### Two things that will bite you

**`APP_PUBLIC_BASE_URL` is baked into every printed QR code.** It is the origin in the
tenant self check-in URL, and `SelfCheckinTokenService` signs that URL with
`JWT_SECRET`. Changing *either* value invalidates every QR code already printed and
stuck on a wall, along with every issued token. Set both once, before you print
anything.

**`SWAGGER_ENABLED=true` now has nothing behind it.** The old setup also had nginx
returning 403 for those paths, so exposing the API map took two mistakes. There is no
nginx here, and `SecurityConfig` deliberately `permitAll`s `/swagger-ui/**` and
`/v3/api-docs/**` (they are useless behind auth). Turning it on publishes a complete
map of every endpoint, role guard and DTO field. Turn it on to debug, turn it off
again.

---

## 4. Backups

Your provider's, not a script in this repo. Before going live, confirm two things
rather than assuming them:

- **Point-in-time recovery is actually enabled**, and its retention window is long
  enough that you would notice a problem inside it. Several free tiers keep 24 hours,
  or nothing at all.
- **You have restored once.** An untested backup is a hypothesis. Restore into a
  scratch database and point a local app at it.

This matters more than it did with a nightly `pg_dump` on a box you owned, because
there is no longer a copy of the data anywhere you control.

---

## 5. Rolling back

Koyeb redeploys a previous deployment from the dashboard. It swaps the **image only**
and knows nothing about your schema.

Flyway is forward-only and `ddl-auto` is `validate`, so an older image whose entities
predate the current schema **will fail to start** — it fails its health check, Koyeb
keeps the current version serving, and you have lost time. Rolling the schema back too
means a point-in-time restore, which loses everything written since.

Rolling *forward* with a fix is almost always better. Check what you are dealing with
before deciding:

```sql
SELECT version, description, installed_on
FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 5;
```

---

## 6. Operating it

Logs are **stdout only** — Koyeb captures them. The container filesystem is ephemeral,
so a log file written inside it is lost on every deploy and restart while still filling
the container's disk.

The durable audit trail is `api_request_log` in the database: one row per request with
masked payloads, purged after `API_LOG_RETENTION_DAYS` (default 10) by a scheduler at
03:15. That is where to look for what a client actually sent. Support lookup by the
`X-Request-Id` a user quotes:

```
GET /api/super-admin/api-logs/{requestId}
```

Useful queries against the managed database:

```sql
-- slowest statements (needs pg_stat_statements; most providers enable it)
SELECT calls, round(total_exec_time) ms, round(mean_exec_time) avg_ms, left(query, 90)
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;

-- is autovacuum keeping up? n_dead_tup climbing and never falling means it is not
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10;

-- connections, against the provider's ceiling
SELECT count(*) FROM pg_stat_activity;
```

`api_request_log` is by far the largest table — one row per request, no sampling. If
writes slow down, lower `API_LOG_RETENTION_DAYS` before anything else.

### Scaling

Before running more than one instance, read this. `PgManagerApplication` has
`@EnableScheduling`, and the schedulers are **not** distributed-safe: two instances
means `InvoiceAutoGenerationScheduler` fires twice at 01:00. The idempotency guard in
`createRecurringInvoice` counts rows by `(billing_account_id, invoice_month)`, so it
should hold — but it is the only thing between you and double-billing every tenant, and
it was never designed to be load-bearing under a race.

Fix that first: add [ShedLock](https://github.com/lukas-krecan/ShedLock), or move the
schedulers behind a profile and run exactly one instance with it enabled.

Also remember the connection budget is `DB_POOL_MAX × instance count`. Exceeding the
provider's ceiling fails as `too many clients already` under exactly the load you added
instances for.
