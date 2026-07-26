#!/usr/bin/env bash
# =============================================================================
# restore.sh — restore MySQL (and optionally Redis) from a backup
#
#   ./scripts/restore.sh                                  # list available backups
#   ./scripts/restore.sh backups/mysql/pg_manager_20260726_023000.sql.gz
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
MYSQL_CONTAINER="pgm-mysql"
REDIS_CONTAINER="pgm-redis"
COMPOSE="docker compose --env-file .env"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# No argument: show what is available and stop.
# -----------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo
    echo "Available MySQL backups:"
    echo "------------------------"
    find "$BACKUP_DIR/mysql" -name '*.sql.gz' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | cut -d' ' -f2- \
        | while read -r f; do printf '  %-62s %8s\n' "$f" "$(du -h "$f" | cut -f1)"; done
    echo
    echo "Available Redis snapshots:"
    echo "--------------------------"
    find "$BACKUP_DIR/redis" -name '*.rdb.gz' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | cut -d' ' -f2- | sed 's/^/  /'
    echo
    echo "Usage: $0 <mysql-backup.sql.gz> [--redis <redis-backup.rdb.gz>]"
    exit 0
fi

MYSQL_BACKUP="$1"; shift
REDIS_BACKUP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --redis) REDIS_BACKUP="${2:-}"; shift 2 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

[[ -f "$MYSQL_BACKUP" ]] || fail "Backup file not found: $MYSQL_BACKUP"

# -----------------------------------------------------------------------------
# Verify the archive BEFORE touching anything. Discovering the backup is corrupt
# after dropping the live database is the worst possible order of operations.
# -----------------------------------------------------------------------------
log "Verifying archive integrity"
gzip -t "$MYSQL_BACKUP" || fail "Archive is corrupt: $MYSQL_BACKUP"

if [[ -f "${MYSQL_BACKUP}.sha256" ]]; then
    sha256sum -c "${MYSQL_BACKUP}.sha256" >/dev/null \
        || fail "Checksum mismatch — the archive has been altered or damaged"
    log "Checksum verified"
else
    log "WARNING: no .sha256 alongside this archive; integrity unverified"
fi

zgrep -q "Dump completed" "$MYSQL_BACKUP" || fail "Archive has no completion marker — it is truncated"

# -----------------------------------------------------------------------------
# Confirmation
# -----------------------------------------------------------------------------
BACKUP_DATE=$(zgrep -m1 -o "Dump completed on [0-9: -]*" "$MYSQL_BACKUP" | sed 's/Dump completed on //' || echo "unknown")

cat <<BANNER

  ============================================================
   DESTRUCTIVE RESTORE
  ============================================================
   Target database : ${MYSQL_DATABASE}
   Archive         : ${MYSQL_BACKUP}
   Taken at        : ${BACKUP_DATE}
   Redis snapshot  : ${REDIS_BACKUP:-<none>}

   The current contents of '${MYSQL_DATABASE}' will be REPLACED.
   All data written after the timestamp above will be lost.
  ============================================================

BANNER

read -r -p "Type the database name to confirm: " CONFIRM
[[ "$CONFIRM" == "$MYSQL_DATABASE" ]] || fail "Confirmation did not match. Nothing changed."

# -----------------------------------------------------------------------------
# Stop the API first.
#
# Restoring underneath a live application means in-flight transactions hit a schema
# mid-replacement, Hibernate's validate can fire against half a schema, and the
# connection pool fills with broken connections. Stop it; MySQL stays up because we
# need it to accept the restore.
# -----------------------------------------------------------------------------
log "Stopping API (MySQL stays up to receive the restore)"
$COMPOSE stop api

# -----------------------------------------------------------------------------
# Safety dump of the CURRENT state. This is the undo button for a restore performed
# against the wrong archive — which is a mistake people make under incident pressure.
# -----------------------------------------------------------------------------
SAFETY="$BACKUP_DIR/mysql/pre-restore_$(date +%Y%m%d_%H%M%S).sql.gz"
log "Capturing current state -> $(basename "$SAFETY")"
docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$MYSQL_CONTAINER" \
    mysqldump --user=root --single-transaction --routines --triggers --events \
              --set-gtid-purged=OFF --no-tablespaces --hex-blob --quick \
              --default-character-set=utf8mb4 --databases "$MYSQL_DATABASE" \
    | gzip -6 > "$SAFETY" || log "WARNING: safety dump failed (database may already be unusable)"

# -----------------------------------------------------------------------------
# Restore
#
# The archive was produced with --databases, so it contains its own CREATE DATABASE
# and USE statements. Those DROP nothing, which is why the explicit DROP/CREATE below
# is required: without it, tables present now but absent from the dump would survive
# and leave the schema ahead of Flyway's recorded history.
# -----------------------------------------------------------------------------
log "Dropping and recreating ${MYSQL_DATABASE}"
docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" -i "$MYSQL_CONTAINER" \
    mysql --user=root -e "
        DROP DATABASE IF EXISTS \`${MYSQL_DATABASE}\`;
        CREATE DATABASE \`${MYSQL_DATABASE}\`
            CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    "

log "Loading archive (this can take several minutes)"
if ! gunzip -c "$MYSQL_BACKUP" \
    | docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" -i "$MYSQL_CONTAINER" \
        mysql --user=root --default-character-set=utf8mb4; then
    echo
    fail "Restore FAILED. Recover the previous state with:
    $0 $SAFETY"
fi

log "Archive loaded"

# -----------------------------------------------------------------------------
# Sanity checks on the restored schema
# -----------------------------------------------------------------------------
TABLE_COUNT=$(docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$MYSQL_CONTAINER" \
    mysql --user=root -N -B -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE}';")
log "Restored ${TABLE_COUNT} tables"
(( TABLE_COUNT > 10 )) || fail "Only ${TABLE_COUNT} tables restored — this does not look right"

# Flyway will refuse to start the app if its history is inconsistent, so surface the
# version here rather than letting it fail during boot.
FLYWAY_VERSION=$(docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$MYSQL_CONTAINER" \
    mysql --user=root -N -B -e \
    "SELECT MAX(version) FROM \`${MYSQL_DATABASE}\`.flyway_schema_history WHERE success=1;" 2>/dev/null || echo "?")
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

    Database   : ${MYSQL_DATABASE}  (${TABLE_COUNT} tables, Flyway ${FLYWAY_VERSION})
    Restored   : ${MYSQL_BACKUP}
    Safety copy: ${SAFETY}

  Verify before declaring success:
    curl -fsS https://${DOMAIN_NAME}/health
    docker compose logs --tail=50 api

  If this restored the wrong archive, undo it with:
    $0 ${SAFETY}

DONE
