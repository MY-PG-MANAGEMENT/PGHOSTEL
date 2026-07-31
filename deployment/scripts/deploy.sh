#!/usr/bin/env bash
# =============================================================================
# deploy.sh — pull a published image and roll the API onto it
#
#   ./scripts/deploy.sh                  # deploy IMAGE_TAG from .env
#   ./scripts/deploy.sh 9f3c1a2          # deploy a specific tag
#
# Invoked by the GitHub Actions workflow over SSH, and safe to run by hand.
#
# Rollout model: this replaces a single API container, so there IS a gap — roughly
# the JVM's boot time, 20-40s — during which nginx returns the JSON 503 from
# @upstream_down. That is an honest description of a single-instance deployment.
# Zero-downtime needs two replicas behind the nginx upstream and a scheduler lock;
# see the scaling section in deployment/README.md, because with @EnableScheduling as
# it stands today a second replica would double-generate invoices.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

COMPOSE="docker compose --env-file .env"
STATE_FILE="$DEPLOY_DIR/.last-good-image"
HEALTH_TIMEOUT=180        # seconds to wait for readiness before rolling back

log()  { echo -e "[$(date '+%H:%M:%S')] $*"; }
fail() { echo -e "[$(date '+%H:%M:%S')] ERROR: $*" >&2; exit 1; }

[[ -f .env ]] || fail ".env not found in $DEPLOY_DIR"
# shellcheck disable=SC1091
set -a; source .env; set +a

# -----------------------------------------------------------------------------
# Resolve the tag to deploy
# -----------------------------------------------------------------------------
NEW_TAG="${1:-${IMAGE_TAG:-latest}}"
if [[ "$NEW_TAG" == "latest" ]]; then
    log "WARNING: deploying 'latest'. Rollback cannot be precise with a moving tag —"
    log "         CI should pass an immutable commit SHA."
fi
NEW_IMAGE="${API_IMAGE}:${NEW_TAG}"

# -----------------------------------------------------------------------------
# Record what is running now, so rollback has a target.
#
# Read from the live container rather than from .env: .env states intent, the
# container states reality, and after a failed deploy those two disagree — which is
# exactly when rollback is needed.
# -----------------------------------------------------------------------------
CURRENT_IMAGE="$(docker inspect -f '{{.Config.Image}}' pgm-api 2>/dev/null || echo '')"
if [[ -n "$CURRENT_IMAGE" ]]; then
    log "Currently running: $CURRENT_IMAGE"
else
    log "No API container running — this is a first deploy"
fi

log "Deploying:         $NEW_IMAGE"

# -----------------------------------------------------------------------------
# Host-side prerequisites
#
# PostgreSQL runs as uid 70 in the alpine image (not 999, which was MySQL's uid in
# the Debian-based image) and writes its server log into a bind mount. On a fresh
# host that directory is root-owned and PostgreSQL
# fails to start with a permission error that reads like a corruption problem.
# -----------------------------------------------------------------------------
mkdir -p logs/postgres logs/nginx logs/api backups/postgres backups/redis
if [[ "$(stat -c '%u' logs/postgres)" != "70" ]]; then
    log "Fixing ownership on logs/postgres (uid 70)"
    sudo chown -R 70:70 logs/postgres
fi

chmod 600 .env 2>/dev/null || true

# -----------------------------------------------------------------------------
# Pull. Done before anything is stopped, so a registry outage or a bad tag fails
# while the current version is still serving traffic.
# -----------------------------------------------------------------------------
log "Pulling image"
IMAGE_TAG="$NEW_TAG" $COMPOSE pull api \
    || fail "Pull failed. Nothing was changed; the previous version is still running."

# Validate the compose file with the new tag before applying it.
IMAGE_TAG="$NEW_TAG" $COMPOSE config --quiet \
    || fail "docker compose config is invalid — refusing to deploy"

# -----------------------------------------------------------------------------
# Apply
#
# --no-deps: do not restart postgres, redis or nginx. Only the API changed, and
# needlessly bouncing PostgreSQL would add a checkpoint + recovery cycle to every
# deploy.
# -----------------------------------------------------------------------------
log "Starting new container"
IMAGE_TAG="$NEW_TAG" $COMPOSE up -d --no-deps --force-recreate api

# -----------------------------------------------------------------------------
# Wait for readiness.
#
# Polls Docker's own health status, which is driven by the HEALTHCHECK in the
# Dockerfile (readiness group: includes the database, excludes Redis). Waiting on
# "container started" instead would declare success before Flyway had run.
# -----------------------------------------------------------------------------
log "Waiting for readiness (timeout ${HEALTH_TIMEOUT}s)"
DEADLINE=$(( SECONDS + HEALTH_TIMEOUT ))
HEALTHY=false

while (( SECONDS < DEADLINE )); do
    STATUS="$(docker inspect -f '{{.State.Health.Status}}' pgm-api 2>/dev/null || echo 'missing')"
    case "$STATUS" in
        healthy)
            HEALTHY=true
            break
            ;;
        unhealthy)
            # Docker retries before reporting unhealthy, so this is already a
            # settled verdict — no point burning the rest of the timeout.
            log "Container reported unhealthy"
            break
            ;;
        missing)
            log "Container disappeared — it exited on startup"
            break
            ;;
    esac
    sleep 5
done

# -----------------------------------------------------------------------------
# Roll back on failure
# -----------------------------------------------------------------------------
if [[ "$HEALTHY" != true ]]; then
    echo
    log "DEPLOY FAILED — last 60 log lines:"
    echo "----------------------------------------------------------------"
    $COMPOSE logs --tail=60 --no-color api || true
    echo "----------------------------------------------------------------"

    if [[ -z "$CURRENT_IMAGE" ]]; then
        fail "No previous image to roll back to (first deploy). The stack is down; fix the image and rerun."
    fi

    PREV_TAG="${CURRENT_IMAGE##*:}"
    log "Rolling back to ${CURRENT_IMAGE}"

    IMAGE_TAG="$PREV_TAG" $COMPOSE up -d --no-deps --force-recreate api

    DEADLINE=$(( SECONDS + 120 ))
    while (( SECONDS < DEADLINE )); do
        [[ "$(docker inspect -f '{{.State.Health.Status}}' pgm-api 2>/dev/null)" == "healthy" ]] && {
            log "Rollback succeeded — ${CURRENT_IMAGE} is serving again"

            # Leave .env pointing at what is actually running, or the next `compose up`
            # would silently reapply the broken tag.
            sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=${PREV_TAG}|" .env
            fail "Deploy of ${NEW_TAG} failed and was rolled back to ${PREV_TAG}."
        }
        sleep 5
    done

    fail "ROLLBACK ALSO FAILED. The API is down. Investigate immediately:
    docker compose logs api
    docker compose ps"
fi

# -----------------------------------------------------------------------------
# Success
# -----------------------------------------------------------------------------
log "API is healthy"

# Persist the new tag so a plain `docker compose up -d` after a host reboot brings
# up the version that is actually deployed.
sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=${NEW_TAG}|" .env
echo "${NEW_IMAGE}" > "$STATE_FILE"

# End-to-end check through nginx and TLS, not just the container's internal probe.
# This catches a broken certificate or an nginx misconfiguration that the container
# healthcheck cannot see.
if curl -fsS --max-time 10 "https://${DOMAIN_NAME}/health" >/dev/null 2>&1; then
    log "Public endpoint OK — https://${DOMAIN_NAME}/health"
else
    log "WARNING: public /health did not respond. The API is up, so suspect nginx, DNS or TLS."
    log "         docker compose logs nginx"
fi

# -----------------------------------------------------------------------------
# Prune
#
# Images only, and only dangling ones. Never `docker system prune -a --volumes`:
# that removes named volumes, and the named volumes here are the database.
# `--filter until=168h` keeps a week of previous images so rollback stays possible.
# -----------------------------------------------------------------------------
log "Pruning unused images older than 7 days"
docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true

log "Deployed ${NEW_IMAGE}"
$COMPOSE ps
