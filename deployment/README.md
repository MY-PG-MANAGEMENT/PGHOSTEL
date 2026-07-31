# PG Manager — Production Deployment

Spring Boot 3.3 / Java 21 · PostgreSQL 17 · Redis 7.4 · nginx 1.27 · Docker Compose v2
Target host: Oracle Cloud Always Free, Ampere A1 (arm64), Ubuntu 24.04 LTS, Cloudflare DNS.

---

## Contents

1. [What is in here](#1-what-is-in-here)
2. [Application changes this deployment required](#2-application-changes-this-deployment-required)
3. [First-time deployment](#3-first-time-deployment)
4. [Everyday commands](#4-everyday-commands)
5. [Updating](#5-updating)
6. [Rolling back](#6-rolling-back)
7. [Backup](#7-backup)
8. [Restore](#8-restore)
9. [Scaling](#9-scaling)
10. [Security checklist](#10-security-checklist)
11. [Performance tuning](#11-performance-tuning)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. What is in here

```
deployment/
├── Dockerfile                    4-stage build; jlink-free, layered, non-root, arm64
├── docker-compose.yml            api + postgres + redis + nginx + certbot
├── .env.example                  template — copy to .env, never commit .env
├── nginx/
│   ├── nginx.conf                worker/gzip/rate-limit/upstream tuning
│   ├── conf.d/
│   │   └── pgmanager.conf.template   vhost; envsubst renders ${DOMAIN_NAME} at boot
│   ├── snippets/
│   │   ├── ssl.conf              TLS 1.2/1.3, OCSP stapling, no DHE
│   │   ├── security-headers.conf HSTS, CSP, frame/sniff/referrer policy
│   │   ├── proxy-common.conf     X-Forwarded-*, timeouts, upstream keepalive
│   │   └── cloudflare-realip.conf  restore the true client IP behind the proxy
│   └── www/                      static root (drop the Flutter web build here)
├── postgres/
│   ├── postgresql.conf           memory, WAL, autovacuum, timeouts, slow-query log
│   └── init/01-init.sql          runs once on an empty data dir; extension + grants
├── redis/redis.conf              AOF+RDB, LRU, no password in the file
├── scripts/
│   ├── deploy.sh                 pull → recreate → health-gate → auto-rollback
│   ├── rollback.sh               previous image, with a migration-safety warning
│   ├── backup.sh                 verified pg_dump + Redis snapshot + retention
│   ├── restore.sh                destructive restore, with a pre-restore safety dump
│   ├── healthcheck.sh            whole-stack report incl. TLS expiry and disk
│   └── init-letsencrypt.sh       first certificate (run before the first `up`)
├── logs/                         bind-mounted nginx + postgres logs (gitignored)
└── backups/                      local dumps (gitignored)

.github/workflows/deploy.yml      test → build arm64 → push GHCR → ssh deploy
```

---

## 2. Application changes this deployment required

Three things in the codebase had to change. They are small, but the deployment does
not work without them, and each is a decision worth understanding.

**`spring-boot-starter-actuator` added to `backend/build.gradle`.**
There were no health endpoints at all. Every health gate here — the Docker
`HEALTHCHECK`, `depends_on: service_healthy`, the deploy script's rollout gate,
nginx's `/health` — depends on `/actuator/health`.

**`backend/src/main/resources/application-prod.yml` added.**
`application.yml` hardcodes `jdbc:postgresql://localhost:5432`, and its JWT secret is a
literal committed to the repository. Inheriting either in production would mean the
app cannot reach the database, and that anyone with the repo can forge an admin
token for any organization. The prod profile declares `${JWT_SECRET}` with **no
default**, so a missing value fails the context at startup instead of silently
falling back.

**Actuator runs on a separate port (9091), not on 8080.**
This is the one non-obvious choice. `ApiLogFilter` writes one `api_request_log` row
per request and has no path exclusions — `shouldNotFilter` consults only
`logging.api.enabled`. A health probe on the main port every 15 seconds would add
~5,700 rows a day per probe source to the fastest-growing table in the schema.
Spring Boot puts management endpoints in a *child* context, and filter beans from
the parent are not registered there, so probes on 9091 bypass the filter entirely.

The same isolation means the management port is **outside `SecurityConfig`'s filter
chain** — everything on it is unauthenticated. That is safe here only because the
port is never published to the host and nginx proxies exactly one path to it
(`/actuator/health/readiness`), never the prefix. If you ever collapse the ports
back together, add a `permitAll` for `/actuator/health` in `SecurityConfig` and
accept the log rows.

---

## 3. First-time deployment

### 3.1 Host preparation

```bash
sudo apt-get update && sudo apt-get upgrade -y

# Docker Engine + Compose v2 from Docker's own repository. Ubuntu's docker.io
# package ships the legacy docker-compose v1, which does not honour the
# `deploy.resources` limits in docker-compose.yml.
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
newgrp docker

docker --version && docker compose version   # expect Compose v2.x
```

### 3.2 Open the ports — both layers

Oracle Cloud blocks traffic in two independent places, and missing the second is the
most common reason a new instance appears unreachable.

```bash
# 1. VCN security list (in the OCI console):
#    Networking → VCN → Security Lists → add Ingress 0.0.0.0/0 TCP 80 and 443

# 2. The instance firewall. Oracle's Ubuntu image ships iptables rules that
#    drop everything except SSH:
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80  -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

### 3.3 Fetch the repository and configure

```bash
sudo mkdir -p /opt/pgmanager && sudo chown "$USER:$USER" /opt/pgmanager
git clone <your-repo-url> /opt/pgmanager
cd /opt/pgmanager/deployment

cp .env.example .env
chmod 600 .env

# Generate real secrets — do not invent them by hand
echo "POSTGRES_PASSWORD=$(openssl rand -base64 36 | tr -d '\n/+=' | cut -c1-32)"
echo "REDIS_PASSWORD=$(openssl rand -base64 36 | tr -d '\n/+=' | cut -c1-32)"
echo "JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')"

nano .env      # paste those in, then set DOMAIN_NAME, EMAIL_FOR_SSL, API_IMAGE
```

`postgres/init/01-init.sql` runs against `POSTGRES_DB` as `POSTGRES_USER`, so unlike
the MySQL script it replaced it needs no edit when you rename either. PostgreSQL
cannot interpolate environment
variables into a `.sql` file, and a mismatch aborts the whole first-boot
initialisation.

### 3.4 DNS

Point an A record at the instance's public IP. If you proxy it through Cloudflare
(orange cloud), set **SSL/TLS mode to "Full (strict)"** once the certificate is
issued. "Flexible" makes Cloudflare speak plain HTTP to this origin, which the
port-80 server block answers with a 301 — an infinite redirect loop.

### 3.5 Certificate, then start

```bash
chmod +x scripts/*.sh

# PostgreSQL runs as uid 70 in the alpine image and writes its server log into a
# bind mount. On a fresh host that directory is root-owned, and PostgreSQL fails to start
# with a permission error that reads like data corruption. `deploy.sh` fixes this on
# every later deploy, but the first boot happens before deploy.sh ever runs.
mkdir -p logs/postgres logs/nginx logs/api backups/postgres backups/redis
sudo chown -R 70:70 logs/postgres

# Must run BEFORE the first `up`: nginx will not start without a certificate file,
# and Let's Encrypt cannot validate the domain until nginx is serving. The script
# breaks that circle with a self-signed placeholder.
./scripts/init-letsencrypt.sh

docker compose --env-file .env up -d
docker compose logs -f api          # watch Flyway apply V1..V31

./scripts/healthcheck.sh
```

### 3.6 Schedule the backup

```bash
sudo crontab -e
# 02:30 — clear of every application scheduler (00:05, 01:00, 03:15, 09:00)
30 2 * * * /opt/pgmanager/deployment/scripts/backup.sh >> /opt/pgmanager/deployment/logs/backup.log 2>&1
```

### 3.7 CI/CD

Add the secrets and variables listed at the top of `.github/workflows/deploy.yml`,
then confirm the host can pull from GHCR:

```bash
echo "<a-github-PAT-with-read:packages>" | docker login ghcr.io -u <username> --password-stdin
```

---

## 4. Everyday commands

```bash
cd /opt/pgmanager/deployment

docker compose ps                      # what is running, and its health
docker compose logs -f api             # follow application logs
docker compose logs --tail=100 nginx
./scripts/healthcheck.sh               # full stack report

docker compose restart api             # restart one service
docker compose up -d                   # reconcile to the compose file
docker stats --no-stream               # live CPU/memory against the limits

# PostgreSQL shell
docker exec -it -e PGPASSWORD="$(grep ^POSTGRES_PASSWORD .env | cut -d= -f2)" \
  pgm-postgres psql -U pgmanager -d pg_manager

# Redis shell
docker exec -it pgm-redis redis-cli -a "$(grep ^REDIS_PASSWORD .env | cut -d= -f2)" --no-auth-warning

# Slow queries
docker exec pgm-postgres tail -f /var/log/postgresql/postgresql-$(date +%F).log

# Validate nginx after editing a config, before reloading
docker exec pgm-nginx nginx -t && docker exec pgm-nginx nginx -s reload
```

**Never run `docker system prune -a --volumes`.** It removes named volumes, and the
named volumes here are the database. `deploy.sh` prunes images only, with a 7-day
floor so rollback targets survive.

---

## 5. Updating

**Normal path — push to `main`.** CI runs the tests (including the Testcontainers
integration tests, which only execute on the runner), builds the arm64 image,
publishes it to GHCR tagged with the commit SHA, takes a pre-deploy database backup,
and runs `deploy.sh` over SSH.

**Manual:**

```bash
cd /opt/pgmanager/deployment
./scripts/deploy.sh 9f3c1a2      # a specific tag; avoid `latest`
```

`deploy.sh` pulls first (so a bad tag fails while the current version is still
serving), recreates only the `api` service, waits up to 180 s on the readiness
healthcheck, and **rolls back automatically** if the container does not come up.

**Expect a short gap.** This is a single API container, so there is roughly 20–40 s
between the old container stopping and the new one passing readiness, during which
nginx returns the JSON 503 from `@upstream_down`. Eliminating it requires two
replicas — see [Scaling](#9-scaling), and read the scheduler warning there first.

**Changing infrastructure config** (`postgresql.conf`, `redis.conf`, nginx, `.env`):

```bash
nano postgres/postgresql.conf
docker compose up -d --force-recreate postgres  # config is mounted, not baked in
```

---

## 6. Rolling back

```bash
./scripts/rollback.sh              # list locally available tags
./scripts/rollback.sh 9f3c1a2
```

**Read this before rolling back across a migration.** `rollback.sh` reverts the
*application image only*. Flyway migrations are forward-only, and Hibernate runs
with `ddl-auto=validate` — so an older image whose entities do not match the
migrated schema **will fail to start**. The script detects this case (comparing the
image build date against `flyway_schema_history`) and makes you confirm.

Rolling the schema back too means restoring a database backup, which loses
everything written since it was taken. Check what you are dealing with:

```bash
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" pgm-postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT version, description, installed_on FROM flyway_schema_history
   ORDER BY installed_rank DESC LIMIT 5;"
```

In most cases rolling *forward* with a fix is the better option.

---

## 7. Backup

`scripts/backup.sh`, nightly at 02:30 via host cron.

- `pg_dump --format=custom` — a compressed, indexed archive. `pg_restore` can verify
  its table of contents without restoring (that is the integrity check), restore one
  table selectively, and restore in parallel. There is no `--single-transaction` to
  remember: pg_dump always runs in one snapshot and never blocks writers.
- `--no-owner --no-privileges` — hard-coding ownership makes an archive un-restorable
  into a differently-named role, which is exactly the situation you are in when
  rebuilding a host from scratch
- verified three ways before anything is pruned: `pg_restore --list` (parses the
  archive's table of contents, so it proves the file is complete and enumerable —
  strictly stronger than the end-of-file marker the MySQL dump was checked for), a
  minimum size, and a minimum table count so a successful backup of the *wrong*
  database is caught too
- SHA-256 written alongside each archive
- Redis snapshotted via `BGSAVE`, polling `LASTSAVE` rather than sleeping
- retention runs **last**, so a failed backup can never delete the good ones

```bash
./scripts/backup.sh              # run now
ls -lh backups/postgres/
```

**Local backups are not a backup strategy.** They protect against a bad migration or
a `DROP TABLE`, and against nothing else — not instance termination, not a failed
boot volume, not a compromised account. Configure the off-host copy at the bottom of
`backup.sh` (Oracle Object Storage, or rclone to any S3-compatible target), and
encrypt before it leaves the host: the dump contains every tenant's personal data.

Test a restore into a throwaway database once a quarter. An untested backup is a
hypothesis.

---

## 8. Restore

```bash
./scripts/restore.sh                                          # list what is available
./scripts/restore.sh backups/postgres/pg_manager_20260726_023000.dump
```

Destructive, and it says so. The script verifies the archive **before** touching
anything, stops the API (leaving PostgreSQL up to receive the load), takes a
**pre-restore safety dump** of the current state, drops and recreates the schema,
loads the archive, checks the table count and Flyway version, and restarts.

If you restored the wrong archive, the safety dump is the undo — the script prints
its path.

Redis is *flushed* rather than restored by default: its contents are read models
derived from the tables you just replaced, so serving them would show stale figures.
Every entry is recomputed on next read.

---

## 9. Scaling

**Before adding a second API replica, read this.** `PgManagerApplication` is
annotated `@EnableScheduling`, and four schedulers run inside the application:

| Time  | Scheduler | Effect of running twice |
|-------|-----------|-------------------------|
| 00:05 | `BedTransferScheduler` | duplicate bed transfers |
| 01:00 | `InvoiceAutoGenerationScheduler` | **duplicate invoices** — real money |
| 03:15 | `ApiLogCleanupScheduler` | harmless, wasteful |
| 09:00 | `RentReminderScheduler` | duplicate tenant notifications |

Invoice generation is idempotent per `(billing_account_id, invoice_month)`, so a
second replica is unlikely to produce a duplicate row — but two schedulers racing on
the same insert will produce constraint violations and duplicate notifications, and
that guard is the only thing standing between you and double-billing every tenant.

**Do this first:** add [ShedLock](https://github.com/lukas-krecan/ShedLock) (a
`shedlock` table plus `@SchedulerLock` on each `@Scheduled` method), *or* move the
schedulers behind a profile and run exactly one instance with it enabled.

### Vertical scaling (do this first)

The Always Free shape is 4 OCPU / 24 GB, and this stack currently allocates ~13.5 GB.
The order that pays off:

1. `shared_buffers` in `postgres/postgresql.conf` — raise toward 25% of the
   PostgreSQL container's limit (NOT 60%: unlike InnoDB's buffer pool, PostgreSQL
   deliberately leans on the OS page cache as a second tier, so oversizing this
   double-buffers and makes things worse). Raise `effective_cache_size` to ~65% of
   the limit alongside it, and the container's `deploy.resources.limits.memory` with
   both. Nothing else comes close for read latency.
2. `DB_POOL_MAX` in `.env` — only if `healthcheck.sh` shows pool exhaustion.
   A larger pool against a saturated database just moves the queue.
3. `JAVA_OPTS` `MaxRAMPercentage` — leave at 70. The other 30% is metaspace, code
   cache, thread stacks and Netty's direct buffers, not slack.

### Horizontal scaling (after ShedLock)

```yaml
api:
  deploy:
    replicas: 3
  # remove container_name — it conflicts with replicas
```

nginx already load-balances via the `pgmanager_api` upstream; add the replicas'
addresses or switch to Docker's DNS round-robin. Note `proxy_next_upstream` in
`snippets/proxy-common.conf` deliberately **excludes** `non_idempotent`: with several
replicas, retrying a failed POST could duplicate a payment.

### Database scaling

`postgresql.conf` already sets `wal_level = replica` and retains WAL
(`wal_keep_size`), so a streaming read replica needs no config change on the primary
beyond a replication role and a slot. Route reports and dashboards there; keep every
write and the money queries on the primary.

Be aware of the trade this introduces, which had no MySQL analogue: a long-running
report on the replica either delays replay or gets cancelled by recovery conflict,
depending on `hot_standby_feedback` — and turning that on makes the *primary* hold
back vacuum. Pick deliberately.

---

## 10. Security checklist

**Before going live**

- [ ] `.env` is `chmod 600` and gitignored (verify: `git check-ignore deployment/.env`)
- [ ] Every password and `JWT_SECRET` regenerated — no `.env.example` value survives
- [ ] `SWAGGER_ENABLED=false`
- [ ] `POSTGRES_USER` is not `postgres` (the default superuser name)
- [ ] `DOMAIN_NAME` correct; `APP_PUBLIC_BASE_URL` is the HTTPS origin, not a LAN IP
- [ ] Cloudflare SSL mode is **Full (strict)**
- [ ] Only 80, 443 and SSH open in the VCN security list
- [ ] SSH: key-only, `PasswordAuthentication no`

**Applied by this configuration**

- [x] Non-root container user (uid 10001), no login shell
- [x] Read-only root filesystem on api, redis and nginx; tmpfs mounted `noexec` where writable
- [x] `no-new-privileges` and `cap_drop: ALL` on every service, capabilities re-added individually
- [x] PostgreSQL and Redis on an `internal: true` network — no route to the internet even after an RCE
- [x] Only nginx publishes ports; the API, database and cache are unreachable from the host
- [x] Actuator on an unpublished port, one path proxied
- [x] TLS 1.2/1.3 only, ECDHE+AEAD ciphers, OCSP stapling, 0-RTT off (replay-unsafe for non-idempotent POSTs)
- [x] HSTS, CSP, frame/sniff/referrer/permissions policies, all with `always`
- [x] Rate limiting: 30 r/s general, 12 r/min auth, 20 r/min public self check-in
- [x] Real client IP restored behind Cloudflare, so rate limits apply per user, not per edge node
- [x] `FLUSHALL`, `FLUSHDB`, `KEYS`, `CONFIG`, `DEBUG` removed from Redis
- [x] Application DB account scoped to one schema, no `GRANT OPTION`
- [x] Secrets never in an image layer — `.dockerignore` excludes `.env`, keys and certs
- [x] Log rotation on every container (10 MB × 5)

**Ongoing**

- [ ] `sudo unattended-upgrades` enabled for host security patches
- [ ] Base images rebuilt monthly (`nginx`, `postgres`, `redis`, `eclipse-temurin` all get CVE fixes)
- [ ] Cloudflare IP ranges in `snippets/cloudflare-realip.conf` refreshed periodically
  (the refresh command is in the file; a stale list fails closed, never open)
- [ ] Backup restore tested quarterly
- [ ] `api_request_log` growth watched — `healthcheck.sh` warns past 5M rows

**Known gaps, stated honestly**

- `ApiLogDemoController` exposes `/api/api-logs/demo/echo` and `/demo/boom` to any
  authenticated non-tenant role. Harmless, but they are demo endpoints in a
  production build — consider `@Profile("!prod")`.
- An access token stays valid for its full 30 minutes after an organization is
  deactivated; `JwtAuthenticationFilter` checks neither user nor org status per
  request. Documented in `CLAUDE.md`; unchanged here.
- Traffic between nginx and Spring Boot, and between Spring Boot and PostgreSQL, is
  plaintext inside the Docker network. Acceptable on a single host; if these ever
  span hosts, enable TLS on both hops.

---

## 11. Performance tuning

**Measure before changing anything.**

```bash
./scripts/healthcheck.sh                    # heap %, pool usage, cache hit rate
docker stats --no-stream                    # against the compose limits
docker exec pgm-postgres tail -100 /var/log/postgresql/postgresql-$(date +%F).log
docker exec pgm-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO stats
awk '{print $NF}' logs/nginx/access.log | sort -rn | head   # slowest requests
```

**PostgreSQL.** `shared_buffers` (1.5 GB) plus the OS page cache dominates read
latency. `pg_stat_statements` is created by `postgres/init/01-init.sql`, and it is the
single most useful thing here during an incident:

```sql
-- slowest statements by total time
SELECT calls, round(total_exec_time) ms, round(mean_exec_time) avg_ms,
       left(query, 90) FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;

-- cache hit ratio: want > 0.99
SELECT sum(blks_hit)::float / nullif(sum(blks_hit + blks_read), 0) FROM pg_stat_database;

-- table bloat / vacuum health: n_dead_tup climbing means autovacuum is behind
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10;

-- connections vs max_connections
SELECT count(*), (SELECT setting FROM pg_settings WHERE name='max_connections')
FROM pg_stat_activity;
```

The thing with no MySQL equivalent, and the one most likely to bite: **autovacuum**.
Every UPDATE and DELETE leaves a dead tuple behind, and the nightly `api_request_log`
retention sweep deletes in large batches. If `n_dead_tup` on a table climbs and never
falls, autovacuum is losing — that is a bloating table and a degrading index, not a
cosmetic number. `postgresql.conf` already runs it more aggressively than the
defaults; the next lever is `autovacuum_vacuum_cost_limit`.

The second one: an **idle-in-transaction** session holds its locks *and* blocks vacuum
from reclaiming any tuple newer than it, so one forgotten `BEGIN` can bloat the whole
database. `idle_in_transaction_session_timeout` is set to 60 s for exactly this.

There is no query cache to look for and no equivalent to configure. The read caches
here are `shared_buffers`, the OS page cache, the application's Redis layer, and
indexes (see the `facility_party` composites in the baseline, added after the planner
was found filtering the tenant-list hot path in memory).

**Redis.** A hit rate under 50% (reported by `healthcheck.sh`) means eviction
pressure — raise `maxmemory` and the container limit together, keeping `maxmemory`
comfortably below the limit so a background save's copy-on-write pages have room.

**JVM.** Sustained heap above 85% precedes an OOM kill. The JVM is configured with
`-XX:+ExitOnOutOfMemoryError`, so the symptom is a restarting container and the
evidence is the heap dump on the `api_logs` volume.

**Application-specific.**
- `api_request_log` is the largest table in the schema by a wide margin — one row per
  request, no sampling. If writes slow down, lower `API_LOG_RETENTION_DAYS` before
  anything else.
- The money dashboards (billing, expenses, transactions, property reports) are
  deliberately **not** cached. Do not "fix" that with a cache; they are write-heavy
  and correctness matters more than latency.
- Report endpoints aggregate a whole month and are the slowest in the API — nginx
  gives `/api/reports/` a 180 s read timeout for this reason.

---

## 12. Troubleshooting

**nginx: `cannot load certificate`** — you ran `docker compose up` before
`./scripts/init-letsencrypt.sh`. Run it, then start the stack.

**API exits immediately, logs show `Could not resolve placeholder 'JWT_SECRET'`** —
working as designed. Set it in `.env`.

**API cannot reach PostgreSQL** — check `depends_on` actually waited:
`docker inspect -f '{{.State.Health.Status}}' pgm-postgres`. On a cold start, crash
recovery after an unclean stop can exceed the 120 s `start_period`. If the container
sits in `starting` forever on a *clean* first boot, read the healthcheck output
(`docker inspect --format='{{json .State.Health}}' pgm-postgres`) — the `psql` leg
needs `PGPASSWORD`, because `POSTGRES_INITDB_ARGS` sets scram-sha-256 for local
connections too.

**`connection has been closed` under load** — Hikari `max-lifetime` (540 s) has
drifted above PostgreSQL's `idle_session_timeout` (600 s). Keep the first below the
second.

**Flyway `Validate failed: checksum mismatch`** — an already-applied migration file
was edited. Do **not** set `validate-on-migrate: false`. Find the changed file,
confirm the live schema is correct, then `flyway repair`.

**PostgreSQL will not start, permission errors on `/var/log/postgresql`** — the bind
mount is root-owned. `sudo chown -R 70:70 logs/postgres` (`deploy.sh` does this
automatically). Note the uid is **70** (alpine's `postgres`), not the 999 the MySQL
image used.

**`initdb: directory not empty`** — `PGDATA` points at a subdirectory of the volume
(`/var/lib/postgresql/data/pgdata`) precisely to avoid this. If you removed that, a
`lost+found` or any stray file at the mount point makes initdb refuse to run.

**Redirect loop through Cloudflare** — SSL mode is "Flexible". Set it to
"Full (strict)".

**Rate limited in normal use** — check `snippets/cloudflare-realip.conf` is being
applied. Without it every request buckets under a handful of Cloudflare edge IPs and
users are throttled in blocks.

**Deploy succeeded, `/health` returns 502** — the container is healthy, so the
problem is nginx, DNS or TLS, not the app. `docker compose logs nginx`.
