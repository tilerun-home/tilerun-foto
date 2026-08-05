#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
set -a
# shellcheck disable=SC1091
. ./.env
set +a

mkdir -p "$BACKUP_LOCATION"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
TARGET="$BACKUP_LOCATION/tilerun-foto-$STAMP.sql.gz"
TMP="$TARGET.partial"

docker exec tilerun-foto-database pg_dumpall --clean --if-exists --username "$DB_USERNAME" | gzip -9 > "$TMP"
gzip -t "$TMP"
mv "$TMP" "$TARGET"
sha256sum "$TARGET" > "$TARGET.sha256"
python3 scripts/media-manifest.py create "$UPLOAD_LOCATION" "$TARGET.media.json"
sha256sum "$TARGET.media.json" > "$TARGET.media.json.sha256"

find "$BACKUP_LOCATION" -maxdepth 1 -type f -name 'tilerun-foto-*.sql.gz' -mtime +30 -delete
find "$BACKUP_LOCATION" -maxdepth 1 -type f -name 'tilerun-foto-*.sql.gz.sha256' -mtime +30 -delete
find "$BACKUP_LOCATION" -maxdepth 1 -type f -name 'tilerun-foto-*.sql.gz.media.json*' -mtime +30 -delete
printf '%s\n' "$TARGET"
