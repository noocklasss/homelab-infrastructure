#!/usr/bin/env bash
# Verifies end-to-end health of the Immich stack and the remote ML worker tunnel.
set -euo pipefail

SERVER_HOST="${IMMICH_SERVER_SSH_HOST:-homeserver}"

echo "==> Checking local Remote ML worker (127.0.0.1:3003)..."
LOCAL_PING="$(curl -fsS http://127.0.0.1:3003/ping)"
echo "    Local ML worker: ${LOCAL_PING}"

echo "==> Checking remote containers and ML tunnel on '${SERVER_HOST}'..."
ssh -o BatchMode=yes "$SERVER_HOST" '
  set -euo pipefail
  echo "    Immich API version: $(curl -fsS http://127.0.0.1:2283/api/server/version)"
  echo "    Container -> ML Tunnel ping: $(docker exec immich_server curl -fsS http://immich-machine-learning:3003/ping)"
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
'
echo "==> All health checks passed."
