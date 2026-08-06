#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
# shellcheck disable=SC1091
. "$ROOT/scripts/lib-compose.sh"

./scripts/preflight.sh

PREVIOUS_IMAGE=$(docker inspect --format '{{.Config.Image}}' tilerun-foto-server 2>/dev/null || true)
if docker inspect tilerun-foto-database >/dev/null 2>&1; then
  ./scripts/backup.sh >/dev/null
fi

if ! docker pull "$(awk -F= '/^TILERUN_FOTO_IMAGE=/{print $2}' .env)"; then
  printf 'Registry-image niet beschikbaar; lokale TileRun-build wordt gebruikt.\n'
  compose --env-file .env -p tilerun-foto -f compose.yml -f compose.build.yml build foto-server
  set -- -f compose.yml -f compose.build.yml
else
  set -- -f compose.yml
fi

compose --env-file .env -p tilerun-foto "$@" up -d --remove-orphans

tries=0
until ./scripts/health.sh >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -ge 30 ]; then
    compose --env-file .env -p tilerun-foto "$@" logs --tail=120 foto-server foto-database foto-machine-learning >&2
    if [ -n "$PREVIOUS_IMAGE" ]; then
      printf 'Healthcheck mislukt; vorige image wordt hersteld: %s\n' "$PREVIOUS_IMAGE" >&2
      TILERUN_FOTO_IMAGE="$PREVIOUS_IMAGE" compose --env-file .env -p tilerun-foto -f compose.yml up -d foto-server
    fi
    exit 1
  fi
  sleep 4
done

./scripts/health.sh
