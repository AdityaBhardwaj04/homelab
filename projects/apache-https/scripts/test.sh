#!/bin/sh
# Smoke test for the reproducible build. Run on the Docker host after starting
# the container as described in README.md.
#
#   scripts/test.sh [container-name] [image]
#
# HTTPS is checked with full certificate validation against the container's own
# self-signed certificate (copied out with `docker cp`), rather than curl -k.
set -eu

NAME="${1:-apache-https}"
IMAGE="${2:-apache-https:local}"
HTTP_PORT="${HTTP_PORT:-8090}"
HTTPS_PORT="${HTTPS_PORT:-8443}"
EXPECT="Apache HTTPS homelab"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check() {
    printf '%-58s' "$1"
    shift
    if "$@" >"$TMP/out" 2>&1; then echo "PASS"; else echo "FAIL"; cat "$TMP/out"; exit 1; fi
}

docker cp "$NAME:/usr/local/apache2/conf/ssl/server.crt" "$TMP/server.crt" >/dev/null

check "Config syntax (httpd -t)" \
    docker exec "$NAME" httpd -t
# PID 1 is httpd itself (the entrypoint execs it), so its owner is the user
# Apache actually runs as, not just the default user for `docker exec`.
check "Apache (PID 1) runs as www-data" \
    sh -c "docker exec '$NAME' stat -c %U /proc/1 | grep -qx www-data"
check "HTTP  :$HTTP_PORT returns the page" \
    sh -c "curl -fsS 'http://localhost:$HTTP_PORT/' | grep -q '$EXPECT'"
check "HTTPS :$HTTPS_PORT returns the page (certificate verified)" \
    sh -c "curl -fsS --cacert '$TMP/server.crt' 'https://localhost:$HTTPS_PORT/' | grep -q '$EXPECT'"
check "HTTPS without trusting the cert is rejected" \
    sh -c "! curl -fsS 'https://localhost:$HTTPS_PORT/' >/dev/null 2>&1"
check "Server header does not reveal the version" \
    sh -c "curl -fsSI 'http://localhost:$HTTP_PORT/' | tr -d '\r' | grep -qix 'server: apache'"
check "Image contains no private key" \
    docker run --rm --entrypoint sh "$IMAGE" -c '! ls /usr/local/apache2/conf/ssl/*.key 2>/dev/null'

echo "All checks passed."
