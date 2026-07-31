#!/usr/bin/env bash
# =============================================================================
# backup.sh — nightly PostgreSQL + Redis backup
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
PG_CONTAINER="pgm-postgres"
REDIS_CONTAINER="pgm-redis"

mkdir -p "$BACKUP_DIR/postgres" "$BACKUP_DIR/redis"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

log "===== Backup started ====="

# -----------------------------------------------------------------------------
# Preflight: refuse to start a backup we cannot finish.
#
# A dump that fills the disk takes the database down with it — PostgreSQL cannot
# write its WAL on a full volume, and a WAL-write failure puts the server into a
# PANIC shutdown. Require 3x the current data size as free space.
# -----------------------------------------------------------------------------
DATA_SIZE_MB=$(docker exec "$PG_CONTAINER" du -sm /var/lib/postgresql/data 2>/dev/null | cut -f1 || echo 0)
FREE_MB=$(df -Pm "$BACKUP_DIR" | awk 'NR==2 {print $4}')
REQUIRED_MB=$(( DATA_SIZE_MB * 3 ))

log "Data size ${DATA_SIZE_MB}MB | free ${FREE_MB}MB | required ~${REQUIRED_MB}MB"
if (( FREE_MB < REQUIRED_MB )); then
    fail "Insufficient disk space. Free ${FREE_MB}MB, need ~${REQUIRED_MB}MB. Backup aborted."
fi

docker inspect -f '{{.State.Running}}' "$PG_CONTAINER" >/dev/null 2>&1 \
    || fail "$PG_CONTAINER is not running"

# =============================================================================
# PostgreSQL
# =============================================================================
PG_FILE="$BACKUP_DIR/postgres/${POSTGRES_DB}_${TIMESTAMP}.dump"
log "Dumping PostgreSQL -> $(basename "$PG_FILE")"

# Format and flag rationale — each of these is load-bearing:
#
#   -Fc (custom)     A compressed, indexed archive rather than a stream of SQL. Three
#                    reasons it beats the old `mysqldump | gzip`: pg_restore can list
#                    and verify its table of contents WITHOUT restoring (the integrity
#                    check below), it can restore selectively (one table, after a bad
#                    migration), and it restores in parallel with -j. It is already
#                    compressed, so there is no separate gzip step.
#   --no-owner
#   --no-privileges  The restore target is the same single role that owns everything,
#                    and hard-coding ownership makes a dump un-restorable into a
#                    differently-named role — exactly the situation you are in when
#                    rebuilding a host from scratch.
#   --serializable-deferrable
#                    Waits for a snapshot that cannot see a serialization anomaly, so
#                    the dump is consistent without blocking writers.
#
# NOTE there is no --single-transaction equivalent to remember here: pg_dump ALWAYS
# runs in one snapshot, so a dump where `invoice` and `payment_allocation` disagree is
# not a failure mode on this engine. It also never locks out writers.
#
# PGPASSWORD is exported into `docker exec` rather than passed on the command line so
# the password does not appear in the container's process list.
if ! docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$PG_CONTAINER"         pg_dump             --username="$POSTGRES_USER"             --dbname="$POSTGRES_DB"             --format=custom             --compress=6             --no-owner             --no-privileges             --serializable-deferrable         > "$PG_FILE"; then
    rm -f "$PG_FILE"
    fail "pg_dump failed; partial file removed"
fi

# Verify the archive is readable and non-trivial. A silently truncated backup that is
# only discovered during a restore is worse than no backup, because you stopped
# looking for one.
#
# `pg_restore --list` parses the archive's table of contents and fails on a truncated
# or corrupt file. This is strictly stronger than the old `zgrep "Dump completed"`:
# that only proved the last line arrived, whereas this proves the archive structure is
# intact and enumerable.
docker exec -i "$PG_CONTAINER" pg_restore --list /dev/stdin < "$PG_FILE" >/dev/null 2>&1     || { rm -f "$PG_FILE"; fail "Backup archive is corrupt or truncated"; }

PG_BYTES=$(stat -c%s "$PG_FILE")
(( PG_BYTES > 10240 )) || { rm -f "$PG_FILE"; fail "Backup suspiciously small (${PG_BYTES} bytes)"; }

# Sanity-check the contents, not just the container: an archive that restores cleanly
# but holds three tables is a successful backup of the wrong database.
TOC_TABLES=$(docker exec -i "$PG_CONTAINER" pg_restore --list /dev/stdin < "$PG_FILE"     | grep -c "TABLE DATA" || echo 0)
(( TOC_TABLES > 20 )) || { rm -f "$PG_FILE"; fail "Dump holds only ${TOC_TABLES} tables — expected the full schema"; }

sha256sum "$PG_FILE" > "${PG_FILE}.sha256"
log "PostgreSQL OK — $(du -h "$PG_FILE" | cut -f1), ${TOC_TABLES} tables"

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
        # job here would discard the PostgreSQL dump that already succeeded.
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
# `*.dump` is in this list because the PostgreSQL backup is a pg_dump custom-format
# archive, which is already compressed and therefore is NOT a `.gz`. Leaving it out —
# as the MySQL-era pattern did, since every artefact was gzipped then — means database
# backups are never pruned and the boot volume fills silently over a few months. The
# Redis backup is still a `.gz`, so both patterns are needed.
log "Pruning backups older than ${RETENTION_DAYS} days"
DELETED=$(find "$BACKUP_DIR" -type f \( -name '*.dump' -o -name '*.gz' -o -name '*.sha256' \) \
              -mtime "+${RETENTION_DAYS}" -print -delete | wc -l)
log "Removed ${DELETED} expired file(s)"

REMAINING=$(find "$BACKUP_DIR/postgres" -name '*.dump' | wc -l)
log "Retained ${REMAINING} PostgreSQL backup(s), total $(du -sh "$BACKUP_DIR" | cut -f1)"

# Guard against a silent retention misconfiguration wiping the last copy.
(( REMAINING > 0 )) || fail "No PostgreSQL backups remain after pruning — check RETENTION_DAYS"

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
#   gpg --encrypt --recipient ops@example.com "$PG_FILE"
#
# And put a reminder in the calendar to actually run scripts/restore.sh against a
# throwaway database once a quarter. An untested backup is a hypothesis.
# =============================================================================
