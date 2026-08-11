#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
set -a
# shellcheck disable=SC1091
. ./.env
set +a

SERVER_STATE=$(docker inspect --format '{{.State.Health.Status}}' tilerun-foto-server 2>/dev/null || printf missing)
DB_STATE=$(docker inspect --format '{{.State.Health.Status}}' tilerun-foto-database 2>/dev/null || printf missing)
ML_STATE=$(docker inspect --format '{{.State.Health.Status}}' tilerun-foto-machine-learning 2>/dev/null || printf missing)
REDIS_STATE=$(docker inspect --format '{{.State.Health.Status}}' tilerun-foto-redis 2>/dev/null || printf missing)
FREE_BYTES=$(df -Pk "$UPLOAD_LOCATION" | awk 'NR==2 {print $4 * 1024}')
LATEST_BACKUP=
for backup in "$BACKUP_LOCATION"/tilerun-foto-*.sql.gz; do
  [ -f "$backup" ] || continue
  if [ -z "$LATEST_BACKUP" ] || [ "$backup" -nt "$LATEST_BACKUP" ]; then
    LATEST_BACKUP=$backup
  fi
done
LATEST_BACKUP=${LATEST_BACKUP##*/}
CHECKED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
STATUS=degraded
[ "$SERVER_STATE" = healthy ] && [ "$DB_STATE" = healthy ] && [ "$ML_STATE" = healthy ] && [ "$REDIS_STATE" = healthy ] && STATUS=ok

mkdir -p "$ROOT/runtime"
TMP_STATUS="$ROOT/runtime/health.json.tmp.$$"
trap 'rm -f "$TMP_STATUS"' EXIT HUP INT TERM
printf '{"status":"%s","version":"%s","container_status":{"server":"%s","database":"%s","machine_learning":"%s","redis":"%s"},"database":"%s","free_storage_bytes":%.0f,"last_backup_at":"%s","ai_worker":"%s","checked_at":"%s"}\n' \
  "$STATUS" "$TILERUN_FOTO_VERSION" "$SERVER_STATE" "$DB_STATE" "$ML_STATE" "$REDIS_STATE" "$DB_STATE" "${FREE_BYTES:-0}" "${LATEST_BACKUP:-}" "$ML_STATE" "$CHECKED_AT" > "$TMP_STATUS"
mv "$TMP_STATUS" "$ROOT/runtime/health.json"
trap - EXIT HUP INT TERM

cat "$ROOT/runtime/health.json"

[ "$STATUS" = ok ]
