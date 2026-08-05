#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
set -a
# shellcheck disable=SC1091
. ./.env
set +a

BACKUP=${1:-$(find "$BACKUP_LOCATION" -maxdepth 1 -type f -name 'tilerun-foto-*.sql.gz' -print | sort | tail -n 1)}
[ -n "$BACKUP" ] && [ -f "$BACKUP" ] || { printf 'Geen databaseback-up gevonden.\n' >&2; exit 1; }
[ -f "$BACKUP.sha256" ] || { printf 'Checksum ontbreekt: %s.sha256\n' "$BACKUP" >&2; exit 1; }
[ -f "$BACKUP.media.json" ] || { printf 'Mediamanifest ontbreekt: %s.media.json\n' "$BACKUP" >&2; exit 1; }
[ -f "$BACKUP.media.json.sha256" ] || { printf 'Checksum van mediamanifest ontbreekt.\n' >&2; exit 1; }

RESTORED_MEDIA=${2:-${RESTORE_MEDIA_LOCATION:-}}
[ -n "$RESTORED_MEDIA" ] && [ -d "$RESTORED_MEDIA" ] || {
  printf 'Geef als tweede argument de medi map van de lege herstelinstallatie op.\n' >&2
  exit 1
}

(cd "$(dirname "$BACKUP")" && sha256sum -c "$(basename "$BACKUP").sha256")
gzip -t "$BACKUP"
(cd "$(dirname "$BACKUP")" && sha256sum -c "$(basename "$BACKUP").media.json.sha256")
python3 scripts/media-manifest.py verify "$RESTORED_MEDIA" "$BACKUP.media.json"

TEST_CONTAINER="tilerun-foto-restore-test-$$"
cleanup() { docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

PASSWORD=$(cat secrets/db_password)
docker run -d --name "$TEST_CONTAINER" \
  -e POSTGRES_PASSWORD="$PASSWORD" \
  -e POSTGRES_USER="$DB_USERNAME" \
  -e POSTGRES_DB="$DB_DATABASE_NAME" \
  ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23 >/dev/null

tries=0
until docker exec "$TEST_CONTAINER" pg_isready --username "$DB_USERNAME" >/dev/null 2>&1; do
  tries=$((tries + 1)); [ "$tries" -lt 30 ] || exit 1; sleep 2
done

gzip -dc "$BACKUP" | docker exec -i "$TEST_CONTAINER" psql --username "$DB_USERNAME" --dbname postgres >/dev/null
TABLE_COUNT=$(docker exec "$TEST_CONTAINER" psql --username "$DB_USERNAME" --dbname "$DB_DATABASE_NAME" -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")
[ "${TABLE_COUNT:-0}" -gt 0 ] || { printf 'Restore bevat geen applicatietabellen.\n' >&2; exit 1; }

COUNT_FILE="$BACKUP_LOCATION/restore-success.count"
COUNT=0
[ ! -f "$COUNT_FILE" ] || COUNT=$(cat "$COUNT_FILE")
COUNT=$((COUNT + 1))
printf '%s\n' "$COUNT" > "$COUNT_FILE"
printf 'Restoretest geslaagd (%s/2). Gebruik pas onvervangbare media na twee geslaagde tests.\n' "$COUNT"
