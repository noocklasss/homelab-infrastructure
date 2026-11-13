#!/usr/bin/env bash
# Automated PostgreSQL logical backup (pg_dumpall) for Immich with gzip compression
# and configurable retention pruning.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/immich-db}"
CONTAINER_NAME="${POSTGRES_CONTAINER:-immich_postgres}"
DB_USER="${DB_USERNAME:-postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUT_FILE="${BACKUP_DIR}/immich_pgdump_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[$(date -Iseconds)] Starting PostgreSQL backup from container '${CONTAINER_NAME}'..."
docker exec "$CONTAINER_NAME" pg_dumpall --clean --if-exists --username="$DB_USER" \
  | gzip -9 > "${OUT_FILE}.tmp"
mv "${OUT_FILE}.tmp" "$OUT_FILE"

echo "[$(date -Iseconds)] Backup saved to ${OUT_FILE} ($(du -h "$OUT_FILE" | cut -f1))"

find "$BACKUP_DIR" -maxdepth 1 -name 'immich_pgdump_*.sql.gz' -mtime +"$RETENTION_DAYS" -delete
echo "[$(date -Iseconds)] Pruned backups older than ${RETENTION_DAYS} days."
