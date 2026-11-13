#!/usr/bin/env bash
# Automated PostgreSQL logical backup (pg_dumpall) for Immich with gzip compression,
# an integrity check, and configurable retention pruning.
# Restore steps: see "Restoring a backup" in the README.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/immich-db}"
CONTAINER_NAME="${POSTGRES_CONTAINER:-immich_postgres}"
DB_USER="${DB_USERNAME:-postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUT_FILE="${BACKUP_DIR}/immich_pgdump_${TIMESTAMP}.sql.gz"
TMP_FILE="${OUT_FILE}.tmp"

mkdir -p "$BACKUP_DIR"
# Never leave a half-written dump behind if the dump or the check fails.
trap 'rm -f "$TMP_FILE"' EXIT

echo "[$(date -Iseconds)] Starting PostgreSQL backup from container '${CONTAINER_NAME}'..."
docker exec "$CONTAINER_NAME" pg_dumpall --clean --if-exists --username="$DB_USER" \
  | gzip -9 > "$TMP_FILE"

# The archive must be readable and must start like a real pg_dumpall dump.
# (pipefail is off inside the check: grep -q stops reading early, which ends gzip with SIGPIPE.)
gzip -t "$TMP_FILE"
if ! (set +o pipefail; gzip -dc "$TMP_FILE" | head -c 65536 | grep -q "PostgreSQL database cluster dump"); then
  echo "[$(date -Iseconds)] Backup looks empty or invalid; previous backups are kept." >&2
  exit 1
fi
mv "$TMP_FILE" "$OUT_FILE"

echo "[$(date -Iseconds)] Backup saved to ${OUT_FILE} ($(du -h "$OUT_FILE" | cut -f1))"

find "$BACKUP_DIR" -maxdepth 1 -name 'immich_pgdump_*.sql.gz' -mtime +"$RETENTION_DAYS" -delete
echo "[$(date -Iseconds)] Pruned backups older than ${RETENTION_DAYS} days."
