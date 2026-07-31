#!/usr/bin/env bash
# =============================================================================

#
#   ./scripts/restore.sh                                  # list available backups
#   ./scripts/restore.sh backups/postgres/pg_manager_20260726_023000.dump
#   ./scripts/restore.sh <file> --redis backups/redis/redis_20260726_023000.rdb.gz
#
# THIS IS DESTRUCTIVE. It replaces the current database with the contents of the
# archive. Everything written since that dump is lost. The script takes a safety
# dump of the present state first and tells you where it put it.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

# shellcheck disable=SC1091
set -a; source .env; set +a

BACKUP_DIR="${BACKUP_DIR:-$DEPLOY_DIR/backups}"
PG_CONTAINER="pgm-postgres"
REDIS_CONTAINER="pgm-redis"
COMPOSE="docker compose --env-file .env"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# No argument: show what is available and stop.
# -----------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo
    echo "Available PostgreSQL backups:"
    echo "-----------------------------"
    find "$BACKUP_DIR/postgres" -name '*.dump' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | cut -d' ' -f2- \
        | while read -r f; do printf '  %-62s %8s\n' "$f" "$(du -h "$f" | cut -f1)"; done
    echo
    echo "Available Redis snapshots:"
    echo "--------------------------"
    find "$BACKUP_DIR/redis" -name '*.rdb.gz' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | cut -d' ' -f2- | sed 's/^/  /'
    echo
    echo "Usage: $0 <postgres-backup.dump> [--redis <redis-backup.rdb.gz>]"
    exit 0
fi

PG_BACKUP="$1"; shift
REDIS_BACKUP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --redis) REDIS_BACKUP="${2:-}"; shift 2 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

[[ -f "$PG_BACKUP" ]] || fail "Backup file not found: $PG_BACKUP"

# -----------------------------------------------------------------------------
# Verify the archive BEFORE touching anything. Discovering the backup is corrupt
# after dropping the live database is the worst possible order of operations.
# -----------------------------------------------------------------------------
# `pg_restore --list` parses the archive's table of contents without restoring
# anything, so it proves the file is a readable, complete custom-format archive.
log "Verifying archive integrity"
docker exec -i "$PG_CONTAINER" pg_restore --list /dev/stdin < "$PG_BACKUP" >/dev/null 2>&1 \
    || fail "Archive is corrupt, truncated, or not a pg_dump custom-format file: $PG_BACKUP"

if [[ -f "${PG_BACKUP}.sha256" ]]; then
    sha256sum -c "${PG_BACKUP}.sha256" >/dev/null \
        || fail "Checksum mismatch — the archive has been altered or damaged"
    log "Checksum verified"
else
    log "WARNING: no .sha256 alongside this archive; integrity unverified"
fi

# -----------------------------------------------------------------------------
# Confirmation
# -----------------------------------------------------------------------------
# The custom-format archive records its own creation time in the TOC header, which is
# more trustworthy than the file's mtime (a copied file carries a new one).
BACKUP_DATE=$(docker exec -i "$PG_CONTAINER" pg_restore --list /dev/stdin < "$PG_BACKUP" 2>/dev/null \
    | sed -n 's/^; *Archive created at //p' | head -1)
BACKUP_DATE="${BACKUP_DATE:-unknown}"

cat <<BANNER

  ============================================================
   DESTRUCTIVE RESTORE
  ============================================================
   Target database : ${POSTGRES_DB}
   Archive         : ${PG_BACKUP}
   Taken at        : ${BACKUP_DATE}
   Redis snapshot  : ${REDIS_BACKUP:-<none>}

   The current contents of '${POSTGRES_DB}' will be REPLACED.
   All data written after the timestamp above will be lost.
  ============================================================

BANNER

read -r -p "Type the database name to confirm: " CONFIRM
[[ "$CONFIRM" == "$POSTGRES_DB" ]] || fail "Confirmation did not match. Nothing changed."

# -----------------------------------------------------------------------------
# Stop the API first.
#
# Restoring underneath a live application means in-flight transactions hit a schema
# mid-replacement, Hibernate's validate can fire against half a schema, and the
# connection pool fills with broken connections. Stop it; PostgreSQL stays up because
# we need it to accept the restore.
#
# Stopping the API is doubly required here: PostgreSQL refuses to DROP a database that
# has ANY open connection, so a single live pool connection makes the restore below
# fail outright rather than merely misbehave.
# -----------------------------------------------------------------------------
log "Stopping API (PostgreSQL stays up to receive the restore)"
$COMPOSE stop api

# -----------------------------------------------------------------------------
# Safety dump of the CURRENT state. This is the undo button for a restore performed
# against the wrong archive — which is a mistake people make under incident pressure.
# -----------------------------------------------------------------------------
SAFETY="$BACKUP_DIR/postgres/pre-restore_$(date +%Y%m%d_%H%M%S).dump"
log "Capturing current state -> $(basename "$SAFETY")"
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$PG_CONTAINER" \
    pg_dump --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
            --format=custom --compress=6 --no-owner --no-privileges \
    > "$SAFETY" || log "WARNING: safety dump failed (database may already be unusable)"

# -----------------------------------------------------------------------------
# Restore
#
# The database is dropped and recreated rather than restored over: tables that exist
# now but are absent from the dump would otherwise survive and leave the schema ahead
# of Flyway's recorded history.
#
# DROP DATABASE must run from a DIFFERENT database, hence `--dbname=postgres`, and it
# fails while any session is still connected — WITH (FORCE) terminates those sessions
# (PostgreSQL 13+). Without FORCE, one leftover psql window aborts the whole restore.
# -----------------------------------------------------------------------------
log "Dropping and recreating ${POSTGRES_DB}"
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i "$PG_CONTAINER" \
    psql --username="$POSTGRES_USER" --dbname=postgres -v ON_ERROR_STOP=1 -q <<SQL
DROP DATABASE IF EXISTS "${POSTGRES_DB}" WITH (FORCE);
CREATE DATABASE "${POSTGRES_DB}" OWNER "${POSTGRES_USER}";
SQL

# pg_stat_statements lives in the database, not the cluster, so a freshly created
# database does not have it — and only the init script (which never runs again) would
# have added it. Recreate it here or the extension silently disappears after the first
# restore, taking the main production diagnostic with it.
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i "$PG_CONTAINER" \
    psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -v ON_ERROR_STOP=1 -q \
    -c 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;'

log "Loading archive (this can take several minutes)"
# --exit-on-error is essential: pg_restore's DEFAULT is to log errors and carry on,
# which would report success while leaving a partially restored database behind.
# --jobs restores table data and indexes in parallel; safe with a custom-format archive.
if ! docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i "$PG_CONTAINER" \
        pg_restore --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
                   --no-owner --no-privileges --exit-on-error --jobs=4 \
        < "$PG_BACKUP"; then
    echo
    fail "Restore FAILED. Recover the previous state with:
    $0 $SAFETY"
fi

log "Archive loaded"

# -----------------------------------------------------------------------------
# Sanity checks on the restored schema
# -----------------------------------------------------------------------------
TABLE_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$PG_CONTAINER" \
    psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")
log "Restored ${TABLE_COUNT} tables"
(( TABLE_COUNT > 10 )) || fail "Only ${TABLE_COUNT} tables restored — this does not look right"

# Flyway will refuse to start the app if its history is inconsistent, so surface the
# version here rather than letting it fail during boot.
FLYWAY_VERSION=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$PG_CONTAINER" \
    psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -tAc \
    "SELECT MAX(version) FROM flyway_schema_history WHERE success;" 2>/dev/null || echo "?")
log "Flyway schema version: ${FLYWAY_VERSION}"

# -----------------------------------------------------------------------------
# Redis (optional)
# -----------------------------------------------------------------------------
if [[ -n "$REDIS_BACKUP" ]]; then
    [[ -f "$REDIS_BACKUP" ]] || fail "Redis snapshot not found: $REDIS_BACKUP"
    log "Restoring Redis snapshot"

    # Redis rewrites dump.rdb on shutdown, so it must be stopped before the file is
    # replaced — otherwise the running server overwrites what we just put there.
    $COMPOSE stop redis
    gunzip -c "$REDIS_BACKUP" > /tmp/dump.rdb
    docker cp /tmp/dump.rdb "$REDIS_CONTAINER:/data/dump.rdb"
    rm -f /tmp/dump.rdb
    $COMPOSE start redis
    log "Redis restored"
else
    # Correct default. The cache holds read models derived from the tables we just
    # replaced; serving them against restored data would show stale figures. Flushing
    # by restart is the safe move — every entry is recomputed on next read.
    log "Clearing Redis cache (stale relative to the restored data)"
    $COMPOSE restart redis
fi

# -----------------------------------------------------------------------------
# Bring the API back
# -----------------------------------------------------------------------------
log "Starting API"
$COMPOSE up -d api

log "Waiting for readiness"
for i in $(seq 1 60); do
    if docker exec pgm-api curl -fsS "http://127.0.0.1:${MANAGEMENT_PORT:-9091}/actuator/health/readiness" >/dev/null 2>&1; then
        log "API is ready"
        break
    fi
    (( i == 60 )) && fail "API did not become ready. Check: docker compose logs api"
    sleep 5
done

cat <<DONE

  Restore complete.

    Database   : ${POSTGRES_DB}  (${TABLE_COUNT} tables, Flyway ${FLYWAY_VERSION})
    Restored   : ${PG_BACKUP}
    Safety copy: ${SAFETY}

  Verify before declaring success:
    curl -fsS https://${DOMAIN_NAME}/health
    docker compose logs --tail=50 api

  If this restored the wrong archive, undo it with:
    $0 ${SAFETY}

DONE
