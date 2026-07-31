#!/usr/bin/env bash
# =============================================================================
# healthcheck.sh — one-shot status report for the whole stack
#
#   ./scripts/healthcheck.sh          # human-readable
#   ./scripts/healthcheck.sh --quiet  # exit code only, for cron/monitoring
#
# Exit 0 = everything healthy, 1 = at least one problem. Distinct from the Docker
# HEALTHCHECKs, which each see one container: this checks the things that only show
# up between components — TLS expiry, disk headroom, the public path through nginx.
#
# Cron suggestion (alerts only when something is wrong):
#   */10 * * * * /opt/pgmanager/deployment/scripts/healthcheck.sh --quiet || \
#       curl -fsS -m 10 --retry 3 https://hc-ping.com/<uuid>/fail
# =============================================================================

set -uo pipefail        # NOT -e: every check must run even after one fails

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

# shellcheck disable=SC1091
set -a; source .env 2>/dev/null || true; set +a

QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

FAILURES=0
WARNINGS=0

if [[ -t 1 ]] && ! $QUIET; then
    G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'
else
    G=''; R=''; Y=''; B=''; N=''
fi

say()  { $QUIET || echo -e "$*"; }
ok()   { say "  ${G}[  OK  ]${N} $*"; }
bad()  { say "  ${R}[ FAIL ]${N} $*"; FAILURES=$((FAILURES+1)); }
warn() { say "  ${Y}[ WARN ]${N} $*"; WARNINGS=$((WARNINGS+1)); }
head_() { say "\n${B}$*${N}"; }

say "\n=============================================="
say " PG Manager stack health — $(date '+%Y-%m-%d %H:%M:%S %Z')"
say "=============================================="

# -----------------------------------------------------------------------------
# Containers
# -----------------------------------------------------------------------------
head_ "Containers"
for c in pgm-postgres pgm-redis pgm-api pgm-nginx; do
    if ! docker inspect "$c" >/dev/null 2>&1; then
        bad "$c does not exist"
        continue
    fi

    STATE=$(docker inspect -f '{{.State.Status}}' "$c")
    HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c")
    RESTARTS=$(docker inspect -f '{{.RestartCount}}' "$c")

    if [[ "$STATE" != "running" ]]; then
        bad "$c is $STATE"
    elif [[ "$HEALTH" == "unhealthy" ]]; then
        bad "$c is running but unhealthy"
    elif [[ "$HEALTH" == "starting" ]]; then
        warn "$c is still starting"
    else
        # A climbing restart count means a crash loop that `docker ps` hides, because
        # each restart shows as a freshly-started healthy container.
        if (( RESTARTS > 5 )); then
            warn "$c healthy but has restarted ${RESTARTS} times — check for a crash loop"
        else
            ok "$c ($HEALTH, ${RESTARTS} restarts)"
        fi
    fi
done

# -----------------------------------------------------------------------------
# PostgreSQL
# -----------------------------------------------------------------------------
head_ "PostgreSQL"
if docker exec -e PGPASSWORD="${POSTGRES_PASSWORD:-}" pgm-postgres \
        psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -tAc "SELECT 1" >/dev/null 2>&1; then
    ok "accepting queries"

    CONNS=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" pgm-postgres psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -tAc \
            "SELECT COUNT(*) FROM pg_stat_activity;" 2>/dev/null || echo '?')
    MAXC=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" pgm-postgres psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -tAc \
            "SELECT setting FROM pg_settings WHERE name='max_connections';" 2>/dev/null || echo '?')
    if [[ "$CONNS" != '?' && "$MAXC" != '?' ]] && (( CONNS * 100 / MAXC > 80 )); then
        warn "connections ${CONNS}/${MAXC} — over 80% of max_connections"
    else
        ok "connections ${CONNS}/${MAXC}"
    fi

    FLYWAY=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" pgm-postgres psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -tAc \
            "SELECT MAX(version) FROM flyway_schema_history WHERE success;" 2>/dev/null || echo '?')
    ok "schema version ${FLYWAY}"

    # A failed migration leaves a success=0 row and blocks every subsequent boot
    # until it is repaired — worth surfacing before the next deploy hits it.
    FAILED_MIG=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" pgm-postgres psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -tAc \
            "SELECT COUNT(*) FROM flyway_schema_history WHERE NOT success;" 2>/dev/null || echo 0)
    (( FAILED_MIG > 0 )) && bad "${FAILED_MIG} FAILED migration(s) in flyway_schema_history — run flyway repair"

    # api_request_log is the fastest-growing table in the schema: one row per request,
    # no sampling. If the cleanup scheduler stops, this is where it shows first.
    LOG_ROWS=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" pgm-postgres psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -tAc \
            "SELECT COUNT(*) FROM api_request_log;" 2>/dev/null || echo 0)
    if (( LOG_ROWS > 5000000 )); then
        warn "api_request_log has ${LOG_ROWS} rows — is ApiLogCleanupScheduler (03:15) running?"
    else
        ok "api_request_log ${LOG_ROWS} rows"
    fi
else
    bad "not accepting queries"
fi

# -----------------------------------------------------------------------------
# Redis
#
# A Redis failure is a WARNING, never a failure of the stack: the cache layer is
# fail-open and the application serves correctly (just slower) without it.
# -----------------------------------------------------------------------------
head_ "Redis"
if docker exec pgm-redis redis-cli -a "${REDIS_PASSWORD:-}" --no-auth-warning PING 2>/dev/null | grep -q PONG; then
    USED=$(docker exec pgm-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO memory 2>/dev/null \
           | grep -m1 '^used_memory_human:' | cut -d: -f2 | tr -d '\r')
    PEAK=$(docker exec pgm-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO memory 2>/dev/null \
           | grep -m1 '^used_memory_peak_human:' | cut -d: -f2 | tr -d '\r')
    KEYS=$(docker exec pgm-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning DBSIZE 2>/dev/null | tr -d '\r')
    ok "responding — ${KEYS} keys, ${USED} used (peak ${PEAK})"

    HITS=$(docker exec pgm-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO stats 2>/dev/null \
           | grep -m1 '^keyspace_hits:' | cut -d: -f2 | tr -d '\r')
    MISSES=$(docker exec pgm-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO stats 2>/dev/null \
           | grep -m1 '^keyspace_misses:' | cut -d: -f2 | tr -d '\r')
    if [[ -n "${HITS:-}" && -n "${MISSES:-}" ]] && (( HITS + MISSES > 1000 )); then
        RATE=$(( HITS * 100 / (HITS + MISSES) ))
        (( RATE < 50 )) && warn "cache hit rate ${RATE}% — evicting too aggressively, or TTLs are too short" \
                        || ok "cache hit rate ${RATE}%"
    fi
else
    warn "not responding (cache is fail-open — the API still serves, from the database)"
fi

# -----------------------------------------------------------------------------
# API
# -----------------------------------------------------------------------------
head_ "API"
if docker exec pgm-api curl -fsS --max-time 5 \
        "http://127.0.0.1:${MANAGEMENT_PORT:-9091}/actuator/health/liveness" >/dev/null 2>&1; then
    ok "liveness"
else
    bad "liveness probe failed"
fi

if docker exec pgm-api curl -fsS --max-time 5 \
        "http://127.0.0.1:${MANAGEMENT_PORT:-9091}/actuator/health/readiness" >/dev/null 2>&1; then
    ok "readiness (database reachable)"
else
    bad "readiness probe failed — the API cannot reach PostgreSQL"
fi

# JVM heap. Sustained pressure here precedes an OOM kill; the JVM is configured to
# exit on OutOfMemoryError, so the symptom is a restarting container.
HEAP_USED=$(docker exec pgm-api curl -fsS --max-time 5 \
    "http://127.0.0.1:${MANAGEMENT_PORT:-9091}/actuator/metrics/jvm.memory.used?tag=area:heap" 2>/dev/null \
    | grep -o '"value":[0-9.E]*' | head -1 | cut -d: -f2)
HEAP_MAX=$(docker exec pgm-api curl -fsS --max-time 5 \
    "http://127.0.0.1:${MANAGEMENT_PORT:-9091}/actuator/metrics/jvm.memory.max?tag=area:heap" 2>/dev/null \
    | grep -o '"value":[0-9.E]*' | head -1 | cut -d: -f2)
if [[ -n "${HEAP_USED:-}" && -n "${HEAP_MAX:-}" ]]; then
    PCT=$(awk -v u="$HEAP_USED" -v m="$HEAP_MAX" 'BEGIN{ if (m>0) printf "%d", (u/m)*100; else print 0 }')
    (( PCT > 85 )) && warn "heap ${PCT}% used" || ok "heap ${PCT}% used"
fi

# -----------------------------------------------------------------------------
# Nginx and the public path
# -----------------------------------------------------------------------------
head_ "Nginx / public endpoint"
docker exec pgm-nginx nginx -t >/dev/null 2>&1 \
    && ok "configuration valid" \
    || bad "nginx -t reports an invalid configuration"

if [[ -n "${DOMAIN_NAME:-}" ]]; then
    CODE=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 10 "https://${DOMAIN_NAME}/health" 2>/dev/null || echo 000)
    [[ "$CODE" == "200" ]] && ok "https://${DOMAIN_NAME}/health -> 200" \
                           || bad "https://${DOMAIN_NAME}/health -> ${CODE}"

    # HTTP must redirect, not serve.
    RCODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://${DOMAIN_NAME}/" 2>/dev/null || echo 000)
    [[ "$RCODE" == "301" ]] && ok "http -> https redirect in place" \
                            || warn "http returned ${RCODE}, expected 301"
fi

# -----------------------------------------------------------------------------
# TLS expiry
#
# certbot renews at 30 days remaining. Anything under 20 means renewal has been
# failing for over a week — usually a DNS change or a blocked /.well-known path.
# -----------------------------------------------------------------------------
head_ "TLS certificate"
if [[ -n "${DOMAIN_NAME:-}" ]]; then
    EXPIRY=$(echo | openssl s_client -servername "$DOMAIN_NAME" -connect "${DOMAIN_NAME}:443" 2>/dev/null \
             | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [[ -n "$EXPIRY" ]]; then
        DAYS=$(( ( $(date -d "$EXPIRY" +%s) - $(date +%s) ) / 86400 ))
        if   (( DAYS < 7 ));  then bad  "expires in ${DAYS} days — renewal is broken"
        elif (( DAYS < 20 )); then warn "expires in ${DAYS} days — certbot should have renewed by now"
        else                       ok   "valid for ${DAYS} more days"
        fi
    else
        bad "could not read the certificate"
    fi
fi

# -----------------------------------------------------------------------------
# Host resources
# -----------------------------------------------------------------------------
head_ "Host"
DISK=$(df -P / | awk 'NR==2 {print $5}' | tr -d '%')
if   (( DISK > 90 )); then bad  "root filesystem ${DISK}% full"
elif (( DISK > 80 )); then warn "root filesystem ${DISK}% full"
else                       ok   "root filesystem ${DISK}% used"
fi

MEM=$(free | awk '/^Mem:/ {printf "%d", $3/$2*100}')
(( MEM > 90 )) && warn "memory ${MEM}% used" || ok "memory ${MEM}% used"

LOAD=$(awk '{print $1}' /proc/loadavg)
CORES=$(nproc)
ok "load ${LOAD} across ${CORES} cores"

# Most recent backup. A backup job that has silently stopped is invisible until the
# day you need it.
LATEST_BACKUP=$(find "${BACKUP_DIR:-$DEPLOY_DIR/backups}/postgres" -name '*.dump' -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
if [[ -n "$LATEST_BACKUP" ]]; then
    AGE_H=$(( ( $(date +%s) - ${LATEST_BACKUP%.*} ) / 3600 ))
    (( AGE_H > 48 )) && bad  "last backup was ${AGE_H}h ago — the backup cron is not running" \
                     || ok   "last backup ${AGE_H}h ago"
else
    bad "no PostgreSQL backup found"
fi

# -----------------------------------------------------------------------------
say "\n=============================================="
if (( FAILURES > 0 )); then
    say " ${R}${FAILURES} failure(s), ${WARNINGS} warning(s)${N}"
    say "==============================================\n"
    exit 1
elif (( WARNINGS > 0 )); then
    say " ${Y}Healthy, with ${WARNINGS} warning(s)${N}"
    say "==============================================\n"
    exit 0
else
    say " ${G}All checks passed${N}"
    say "==============================================\n"
    exit 0
fi
