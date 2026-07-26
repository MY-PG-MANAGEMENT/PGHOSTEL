#!/usr/bin/env bash
# =============================================================================
# init-letsencrypt.sh — obtain the first TLS certificate
#
#   ./scripts/init-letsencrypt.sh
#
# RUN THIS ONCE, BEFORE THE FIRST `docker compose up -d`.
#
# The problem it solves: nginx refuses to start when ssl_certificate points at a
# file that does not exist, and Let's Encrypt cannot validate the domain until nginx
# is up to serve /.well-known/acme-challenge. Neither can go first.
#
# The break: stage a self-signed placeholder at the exact paths nginx expects, start
# nginx against it, let certbot validate over plain HTTP, then swap in the real
# certificate and reload. Standard practice, and the reason a bare `compose up` on a
# fresh host fails with "cannot load certificate".
#
# Renewal is NOT handled here — the certbot sidecar in docker-compose.yml does that
# every 12 hours, and nginx reloads every 6.
#
# PREREQUISITES
#   1. DNS A/AAAA for $DOMAIN_NAME resolves to this host's public IP.
#   2. Ports 80 and 443 are open in the Oracle Cloud VCN security list AND in the
#      instance firewall. Oracle images ship with iptables rules that block
#      everything but SSH, and the VCN rule alone is not enough:
#        sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80  -j ACCEPT
#        sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
#        sudo netfilter-persistent save
#   3. If the domain is proxied through Cloudflare (orange cloud), either set it to
#      DNS-only for this run, or leave it proxied — HTTP-01 works through the proxy
#      because Cloudflare forwards /.well-known. Afterwards set Cloudflare SSL mode
#      to "Full (strict)"; "Flexible" would make Cloudflare talk plain HTTP to this
#      origin and cause a redirect loop against the port-80 server block.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

# shellcheck disable=SC1091
set -a; source .env; set +a

COMPOSE="docker compose --env-file .env"
CERT_VOLUME="pgm-certbot-certs"
WEBROOT_VOLUME="pgm-certbot-www"
LIVE_PATH="/etc/letsencrypt/live/${DOMAIN_NAME}"

log()  { echo -e "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "${DOMAIN_NAME:-}"   ]] || fail "DOMAIN_NAME is not set in .env"
[[ -n "${EMAIL_FOR_SSL:-}" ]] || fail "EMAIL_FOR_SSL is not set in .env"

log "Domain: ${DOMAIN_NAME}   Contact: ${EMAIL_FOR_SSL}"

# -----------------------------------------------------------------------------
# Preflight: does DNS point here?
#
# A mismatch is the most common cause of failure, and each failed attempt counts
# against the Let's Encrypt rate limit (5 failed authorisations per hostname per
# hour). Catching it before calling the CA is worth the two seconds.
# -----------------------------------------------------------------------------
PUBLIC_IP="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || echo '')"
RESOLVED="$(getent hosts "$DOMAIN_NAME" | awk '{print $1}' | head -1 || echo '')"

if [[ -n "$PUBLIC_IP" && -n "$RESOLVED" && "$PUBLIC_IP" != "$RESOLVED" ]]; then
    log "WARNING: ${DOMAIN_NAME} resolves to ${RESOLVED}, this host is ${PUBLIC_IP}"
    log "         Expected when proxied through Cloudflare (the orange cloud)."
    log "         Unexpected otherwise — validation will fail."
    read -r -p "Continue? [y/N] " a; [[ "$a" =~ ^[Yy]$ ]] || exit 1
fi

# -----------------------------------------------------------------------------
# Already have one?
# -----------------------------------------------------------------------------
if docker run --rm -v "${CERT_VOLUME}:/etc/letsencrypt" alpine:3.20 \
        test -f "${LIVE_PATH}/fullchain.pem" 2>/dev/null; then
    log "A certificate already exists for ${DOMAIN_NAME}."
    read -r -p "Replace it? [y/N] " a
    [[ "$a" =~ ^[Yy]$ ]] || { log "Keeping the existing certificate."; exit 0; }
    REPLACE="--force-renewal"
else
    REPLACE=""
fi

# -----------------------------------------------------------------------------
# Step 1 — self-signed placeholder
#
# Only has to satisfy nginx's config parser for a few seconds. It is overwritten in
# step 4 and never presented to a real client.
# -----------------------------------------------------------------------------
log "Staging a temporary self-signed certificate"
docker run --rm -v "${CERT_VOLUME}:/etc/letsencrypt" alpine:3.20 \
    sh -c "mkdir -p ${LIVE_PATH}"

docker run --rm -v "${CERT_VOLUME}:/etc/letsencrypt" alpine/openssl:latest \
    req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout "${LIVE_PATH}/privkey.pem" \
        -out    "${LIVE_PATH}/fullchain.pem" \
        -subj   "/CN=${DOMAIN_NAME}" 2>/dev/null

# ssl_trusted_certificate (used for OCSP stapling) must also exist or nginx will not
# load the config. A copy of the self-signed cert is a valid placeholder.
docker run --rm -v "${CERT_VOLUME}:/etc/letsencrypt" alpine:3.20 \
    cp "${LIVE_PATH}/fullchain.pem" "${LIVE_PATH}/chain.pem"

# -----------------------------------------------------------------------------
# Step 2 — start nginx so the challenge path is reachable
# -----------------------------------------------------------------------------
log "Starting nginx with the placeholder"
$COMPOSE up -d nginx
sleep 5

docker exec pgm-nginx nginx -t >/dev/null 2>&1 \
    || { $COMPOSE logs --tail=30 nginx; fail "nginx configuration is invalid"; }

# Prove the ACME path is actually served before asking the CA to fetch from it.
docker run --rm -v "${WEBROOT_VOLUME}:/w" alpine:3.20 \
    sh -c 'mkdir -p /w/.well-known/acme-challenge && echo ok > /w/.well-known/acme-challenge/preflight'

if curl -fsS --max-time 10 "http://${DOMAIN_NAME}/.well-known/acme-challenge/preflight" 2>/dev/null | grep -q ok; then
    log "ACME challenge path is reachable"
else
    log "WARNING: could not fetch the challenge file over HTTP."
    log "         Check ports 80/443, the VCN security list, and the host firewall."
    read -r -p "Continue anyway? [y/N] " a; [[ "$a" =~ ^[Yy]$ ]] || exit 1
fi

docker run --rm -v "${WEBROOT_VOLUME}:/w" alpine:3.20 \
    rm -f /w/.well-known/acme-challenge/preflight

# -----------------------------------------------------------------------------
# Step 3 — remove the placeholder and request the real certificate
#
# certbot refuses to overwrite an existing lineage without --force-renewal, so the
# self-signed files are deleted first.
# -----------------------------------------------------------------------------
log "Removing the placeholder"
docker run --rm -v "${CERT_VOLUME}:/etc/letsencrypt" alpine:3.20 \
    rm -rf "${LIVE_PATH}" "/etc/letsencrypt/archive/${DOMAIN_NAME}" \
           "/etc/letsencrypt/renewal/${DOMAIN_NAME}.conf"

STAGING_FLAG=""
if [[ "${CERTBOT_STAGING:-0}" == "1" ]]; then
    STAGING_FLAG="--staging"
    log "STAGING MODE — the certificate issued will NOT be trusted by browsers."
    log "Set CERTBOT_STAGING=0 in .env and rerun for a real one."
fi

log "Requesting the certificate from Let's Encrypt"
# --key-type ecdsa: smaller, faster handshakes than RSA, and universally supported
#   by anything that also speaks TLS 1.2 with the ECDHE ciphers in snippets/ssl.conf.
# --rsa-key-size is deliberately not set; it applies only to RSA lineages.
docker run --rm \
    -v "${CERT_VOLUME}:/etc/letsencrypt" \
    -v "${WEBROOT_VOLUME}:/var/www/certbot" \
    certbot/certbot:latest \
    certonly \
        --webroot -w /var/www/certbot \
        --email "${EMAIL_FOR_SSL}" \
        --agree-tos \
        --no-eff-email \
        --non-interactive \
        --key-type ecdsa \
        -d "${DOMAIN_NAME}" \
        ${STAGING_FLAG} ${REPLACE} \
    || fail "Certificate issuance failed. Common causes:
  * DNS does not resolve to this host
  * port 80 blocked by the VCN security list or the instance firewall
  * rate limited (5 failed authorisations per hostname per hour) — set
    CERTBOT_STAGING=1 in .env and retry there first"

# -----------------------------------------------------------------------------
# Step 4 — reload nginx onto the real certificate
# -----------------------------------------------------------------------------
log "Reloading nginx"
docker exec pgm-nginx nginx -s reload

sleep 3
if curl -fsS --max-time 10 -o /dev/null "https://${DOMAIN_NAME}/nginx-health" 2>/dev/null \
   || [[ "${CERTBOT_STAGING:-0}" == "1" ]]; then
    log "HTTPS is live"
else
    log "WARNING: HTTPS did not respond as expected — check: docker compose logs nginx"
fi

EXPIRY=$(docker run --rm -v "${CERT_VOLUME}:/etc/letsencrypt" alpine/openssl:latest \
         x509 -enddate -noout -in "${LIVE_PATH}/fullchain.pem" 2>/dev/null | cut -d= -f2 || echo '?')

cat <<DONE

  ============================================================
   Certificate installed for ${DOMAIN_NAME}
   Expires: ${EXPIRY}
  ============================================================

  Renewal is automatic: the certbot sidecar checks twice a day and
  renews at 30 days remaining; nginx reloads every 6 hours.

  Next:
    docker compose --env-file .env up -d
    ./scripts/healthcheck.sh

  If using Cloudflare, set SSL/TLS mode to "Full (strict)" now.
  "Flexible" makes Cloudflare speak plain HTTP to this origin, which
  the port-80 server block answers with a 301 — an infinite loop.

DONE
