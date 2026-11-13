#!/usr/bin/env bash
# Updates DuckDNS dynamic DNS record using environment variables.
set -euo pipefail

: "${DUCKDNS_SUBDOMAIN:?DUCKDNS_SUBDOMAIN environment variable is required}"
: "${DUCKDNS_TOKEN:?DUCKDNS_TOKEN environment variable is required}"
LOG_FILE="${DUCKDNS_LOG_FILE:-$HOME/duckdns/duck.log}"

mkdir -p "$(dirname "$LOG_FILE")"
RESPONSE="$(curl -fsSL "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=")"
printf '%s - %s\n' "$(date -Iseconds)" "$RESPONSE" > "$LOG_FILE"

if [[ "$RESPONSE" != "OK" ]]; then
  echo "DuckDNS update failed: $RESPONSE" >&2
  exit 1
fi
