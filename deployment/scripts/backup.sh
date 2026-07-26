#!/usr/bin/env bash
# =============================================================================
# backup.sh — nightly MySQL + Redis backup
#
#   ./scripts/backup.sh
#
# Install as a host cron entry (NOT a container — a backup job that dies with the
# stack it is backing up is no backup at all):
#
#   sudo crontab -e
#   30 2 * * * /opt/pgmanager/deployment/scripts/backup.sh >> /opt/pgmanager/deployment/logs/backup.log 2>&1
#
# 02:30 is chosen to sit clear of every scheduler in the application:
#   00:05 BedTransferScheduler   01:00 InvoiceAutoGenerationScheduler
#   03:15 ApiLogCleanupScheduler 09:00 RentReminderScheduler
#
# READ THIS: a backup on the same host as the database is protection against a bad
# migration or a DROP TABLE, and against nothing else. It does not survive the
# instance being terminated, the boot volume failing, or the account being
# compromised. See the off-host section at the bottom of this file.
# =============================================================================

set -euo pipefail

# --- Locate the deployment directory regardless of where cron invoked us from ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

# --- Load configuration -------------------------------------------------------
if [[ ! -f .env ]]; then
    echo "FATAL: .env not found in $DEPLOY_DIR" >&2
    exit 1
fi
# shellcheck disable=SC1091
set -a; source .env; set +a

BACKUP_DIR="${BACKUP_DIR:-$DEPLOY_DIR/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
MYSQL_CONTAINER="pgm-mysql"
REDIS_CONTAINER="pgm-redis"

mkdir -p "$BACKUP_DIR/mysql" "$BACKUP_DIR/redis"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

log "===== Backup started ====="

# -----------------------------------------------------------------------------
# Preflight: refuse to start a backup we cannot finish.
#
# A dump that fills the disk takes the database down with it — MySQL cannot write
# its redo log on a full volume. Require 3x the current data size as free space.
# -----------------------------------------------------------------------------
DATA_SIZE_MB=$(docker exec "$MYSQL_CONTAINER" du -sm /var/lib/mysql 2>/dev/null | cut -f1 || echo 0)
FREE_MB=$(df -Pm "$BACKUP_DIR" | awk 'NR==2 {print $4}')
REQUIRED_MB=$(( DATA_SIZE_MB * 3 ))

log "Data size ${DATA_SIZE_MB}MB | free ${FREE_MB}MB | required ~${REQUIRED_MB}MB"
if (( FREE_MB < REQUIRED_MB )); then
    fail "Insufficient disk space. Free ${FREE_MB}MB, need ~${REQUIRED_MB}MB. Backup aborted."
fi

docker inspect -f '{{.State.Running}}' "$MYSQL_CONTAINER" >/dev/null 2>&1 \
    || fail "$MYSQL_CONTAINER is not running"

# =============================================================================
# MySQL
# =============================================================================
MYSQL_FILE="$BACKUP_DIR/mysql/${MYSQL_DATABASE}_${TIMESTAMP}.sql.gz"
log "Dumping MySQL -> $(basename "$MYSQL_FILE")"

# Flag rationale — each of these is load-bearing:
#
#   --single-transaction   Takes the dump inside one REPEATABLE READ transaction, so
#                          every table is consistent as of the same instant WITHOUT
#                          locking writes. Valid because every table here is InnoDB.
#                          Omitting it on a live database gives you a dump where
#                          `invoice` and `payment_allocation` disagree.
#   --routines --triggers
#   --events               Objects that live outside table definitions. Not currently
#                          used by this schema, but included so the dump stays
#                          complete if one is ever added.
#   --set-gtid-purged=OFF  my.cnf enables gtid_mode. The default (AUTO) writes a
#                          SET @@GLOBAL.GTID_PURGED statement into the dump, which
#                          FAILS on restore into a server that already has a GTID
#                          history — i.e. every real recovery. OFF makes the dump a
#                          plain logical restore.
#   --no-tablespaces       Avoids needing the global PROCESS privilege.
#   --hex-blob             Binary-safe; prevents charset mangling of blob columns.
#   --quick                Stream rows instead of buffering a whole table in RAM.
#                          api_request_log is by far the largest table here.
#
# MYSQL_PWD is exported into `docker exec` rather than passed as -p so the password
# does not appear in the container's process list.
if ! docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$MYSQL_CONTAINER" \
        mysqldump \
            --user=root \
            --single-transaction \
            --routines --triggers --events \
            --set-gtid-purged=OFF \
            --no-tablespaces \
            --hex-blob \
            --quick \
            --default-character-set=utf8mb4 \
            --databases "$MYSQL_DATABASE" \
        | gzip -6 > "$MYSQL_FILE"; then
    rm -f "$MYSQL_FILE"
    fail "mysqldump failed; partial file removed"
fi

# Verify the archive is readable and non-trivial. A silently truncated backup that is
# only discovered during a restore is worse than no backup, because you stopped
# looking for one.
gzip -t "$MYSQL_FILE" || { rm -f "$MYSQL_FILE"; fail "Backup archive is corrupt"; }

MYSQL_BYTES=$(stat -c%s "$MYSQL_FILE")
(( MYSQL_BYTES > 10240 )) || { rm -f "$MYSQL_FILE"; fail "Backup suspiciously small (${MYSQL_BYTES} bytes)"; }

# The dump must contain the end-of-dump marker mysqldump writes last. Its presence
# is the only proof the dump ran to completion rather than being cut off mid-table.
zgrep -q "Dump completed" "$MYSQL_FILE" \
    || { rm -f "$MYSQL_FILE"; fail "Dump is incomplete (no completion marker)"; }

sha256sum "$MYSQL_FILE" > "${MYSQL_FILE}.sha256"
log "MySQL OK — $(du -h "$MYSQL_FILE" | cut -f1)"

# =============================================================================
# Redis
#
# Cache only, so this is a convenience (a warm restart), not a recovery requirement.
# Losing it costs one round of cache misses.
# =============================================================================
REDIS_FILE="$BACKUP_DIR/redis/redis_${TIMESTAMP}.rdb.gz"

if docker inspect -f '{{.State.Running}}' "$REDIS_CONTAINER" >/dev/null 2>&1; then
    log "Snapshotting Redis -> $(basename "$REDIS_FILE")"

    LAST_SAVE=$(docker exec "$REDIS_CONTAINER" \
        redis-cli -a "$REDIS_PASSWORD" --no-auth-warning LASTSAVE | tr -d '\r')

    # BGSAVE forks and returns immediately; it does NOT block the event loop.
    docker exec "$REDIS_CONTAINER" \
        redis-cli -a "$REDIS_PASSWORD" --no-auth-warning BGSAVE >/dev/null

    # Poll LASTSAVE rather than sleeping a fixed interval — the fork takes as long as
    # the dataset needs, and copying dump.rdb mid-write yields a corrupt snapshot.
    for _ in $(seq 1 60); do
        NOW_SAVE=$(docker exec "$REDIS_CONTAINER" \
            redis-cli -a "$REDIS_PASSWORD" --no-auth-warning LASTSAVE | tr -d '\r')
        [[ "$NOW_SAVE" != "$LAST_SAVE" ]] && break
        sleep 1
    done

    if docker cp "$REDIS_CONTAINER:/data/dump.rdb" - 2>/dev/null | gzip -6 > "$REDIS_FILE"; then
        sha256sum "$REDIS_FILE" > "${REDIS_FILE}.sha256"
        log "Redis OK — $(du -h "$REDIS_FILE" | cut -f1)"
    else
        # Non-fatal on purpose: the cache is reconstructible, and failing the whole
        # job here would discard the MySQL dump that already succeeded.
        log "WARNING: Redis snapshot failed (cache only — continuing)"
        rm -f "$REDIS_FILE"
    fi
else
    log "Redis not running — skipped"
fi

# =============================================================================
# Retention
#
# Deletion runs LAST and only after both verification steps above passed, so a failed
# backup can never take the previous good ones with it.
# =============================================================================
log "Pruning backups older than ${RETENTION_DAYS} days"
DELETED=$(find "$BACKUP_DIR" -type f \( -name '*.gz' -o -name '*.sha256' \) \
              -mtime "+${RETENTION_DAYS}" -print -delete | wc -l)
log "Removed ${DELETED} expired file(s)"

REMAINING=$(find "$BACKUP_DIR/mysql" -name '*.sql.gz' | wc -l)
log "Retained ${REMAINING} MySQL backup(s), total $(du -sh "$BACKUP_DIR" | cut -f1)"

# Guard against a silent retention misconfiguration wiping the last copy.
(( REMAINING > 0 )) || fail "No MySQL backups remain after pruning — check RETENTION_DAYS"

log "===== Backup completed ====="

# =============================================================================
# OFF-HOST COPY — configure this. Everything above is still one `terminate
# instance` away from total loss.
#
# Oracle Object Storage (same tenancy, free tier includes 20 GB):
#   oci os object bulk-upload --bucket-name pgmanager-backups \
#       --src-dir "$BACKUP_DIR" --overwrite
#
# Any S3-compatible target (Backblaze B2, Cloudflare R2, Wasabi):
#   rclone sync "$BACKUP_DIR" remote:pgmanager-backups --transfers 4
#
# Encrypt before it leaves the host — the dump contains every tenant's personal
# data, and this is a hosted third party:
#   gpg --encrypt --recipient ops@example.com "$MYSQL_FILE"
#
# And put a reminder in the calendar to actually run scripts/restore.sh against a
# throwaway database once a quarter. An untested backup is a hypothesis.
# =============================================================================
