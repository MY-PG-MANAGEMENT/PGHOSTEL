#!/usr/bin/env bash
# =============================================================================
# rollback.sh — put a previous image back into service
#
#   ./scripts/rollback.sh              # list what is available locally
#   ./scripts/rollback.sh 9f3c1a2      # roll back to that tag
#
# deploy.sh already rolls back automatically when a new image fails its health
# check. This script is for the other case: the deploy succeeded, the container is
# healthy, and the BUG only became apparent afterwards.
#
# SCOPE — read before using. This rolls back the APPLICATION IMAGE ONLY. It does not
# and cannot undo a database migration. Flyway migrations are forward-only, and an
# older image whose entities do not match the migrated schema will fail Hibernate's
# ddl-auto=validate at startup and refuse to boot.
#
# So: rolling back across a release that added a migration requires restoring the
# database too — scripts/restore.sh, using the pre-deploy backup — and that means
# losing everything written since. Check first:
#     docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" pgm-postgres \
#       psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
#       "SELECT version, description, installed_on FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 5;"
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

COMPOSE="docker compose --env-file .env"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# shellcheck disable=SC1091
set -a; source .env; set +a

CURRENT="$(docker inspect -f '{{.Config.Image}}' pgm-api 2>/dev/null || echo 'none')"

# -----------------------------------------------------------------------------
# No argument: show the locally available tags, newest first.
# -----------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo
    echo "Currently running: ${CURRENT}"
    echo
    echo "Locally available images for ${API_IMAGE}:"
    echo "-------------------------------------------------------------"
    docker images "${API_IMAGE}" \
        --format '  {{.Tag}}\t{{.CreatedSince}}\t{{.Size}}' \
        | sort -k2 || echo "  (none)"
    echo
    echo "Only images still present on this host can be rolled back to instantly."
    echo "Anything else is pulled from the registry, which is slower but works:"
    echo "  $0 <tag>"
    echo
    exit 0
fi

TARGET_TAG="$1"
TARGET_IMAGE="${API_IMAGE}:${TARGET_TAG}"

[[ "$CURRENT" == "$TARGET_IMAGE" ]] && fail "${TARGET_IMAGE} is already running."

# -----------------------------------------------------------------------------
# Make sure the image exists before stopping anything.
# -----------------------------------------------------------------------------
if ! docker image inspect "$TARGET_IMAGE" >/dev/null 2>&1; then
    log "${TARGET_IMAGE} not present locally — pulling"
    docker pull "$TARGET_IMAGE" || fail "Cannot pull ${TARGET_IMAGE}. Check the tag exists in the registry."
fi

# -----------------------------------------------------------------------------
# Warn about migrations applied since the target image was built.
#
# Heuristic, not proof: it compares the image's build timestamp against the times
# Flyway recorded. A hit means the older image predates a schema change and will
# very likely fail validation on boot.
# -----------------------------------------------------------------------------
TARGET_BUILT="$(docker inspect -f '{{.Created}}' "$TARGET_IMAGE" 2>/dev/null | cut -dT -f1 || echo '')"
if [[ -n "$TARGET_BUILT" ]]; then
    MIGRATIONS_SINCE=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" pgm-postgres \
        psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -tAc \
        "SELECT COUNT(*) FROM flyway_schema_history
          WHERE success AND installed_on > TIMESTAMP '${TARGET_BUILT} 00:00:00';" 2>/dev/null || echo 0)

    if [[ "${MIGRATIONS_SINCE:-0}" -gt 0 ]]; then
        cat <<WARN

  ============================================================
   ${MIGRATIONS_SINCE} Flyway migration(s) were applied AFTER this image was built.

   The rolled-back image's entities will not match the current
   schema. Hibernate runs with ddl-auto=validate, so it will
   most likely FAIL TO START.

   Rolling the schema back as well means restoring a database
   backup and losing everything written since it was taken.
  ============================================================

WARN
        read -r -p "Proceed anyway? Type 'yes': " CONFIRM
        [[ "$CONFIRM" == "yes" ]] || fail "Cancelled. Nothing changed."
    fi
fi

# -----------------------------------------------------------------------------
# Apply
# -----------------------------------------------------------------------------
log "Rolling back: ${CURRENT}  ->  ${TARGET_IMAGE}"
IMAGE_TAG="$TARGET_TAG" $COMPOSE up -d --no-deps --force-recreate api

log "Waiting for readiness"
DEADLINE=$(( SECONDS + 180 ))
while (( SECONDS < DEADLINE )); do
    case "$(docker inspect -f '{{.State.Health.Status}}' pgm-api 2>/dev/null || echo missing)" in
        healthy)
            sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=${TARGET_TAG}|" .env
            echo "${TARGET_IMAGE}" > "$DEPLOY_DIR/.last-good-image"
            log "Rollback complete — ${TARGET_IMAGE} is serving"
            $COMPOSE ps api
            exit 0
            ;;
        unhealthy|missing)
            break
            ;;
    esac
    sleep 5
done

echo
log "ROLLBACK FAILED — last 60 log lines:"
echo "----------------------------------------------------------------"
$COMPOSE logs --tail=60 --no-color api || true
echo "----------------------------------------------------------------"
echo
fail "If the logs show a Hibernate schema validation error, the older image is
incompatible with the migrated database. Either move forward with a fix, or
restore the matching database backup:
    ./scripts/restore.sh"
