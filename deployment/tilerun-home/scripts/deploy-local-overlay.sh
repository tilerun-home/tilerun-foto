#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
# shellcheck disable=SC1091
. "$ROOT/scripts/lib-compose.sh"

[ -s local-overlay/server-dist.tar.gz ] || { printf 'FOUT: local-overlay/server-dist.tar.gz ontbreekt.\n' >&2; exit 1; }
[ -s local-overlay/web-build.tar.gz ] || { printf 'FOUT: local-overlay/web-build.tar.gz ontbreekt.\n' >&2; exit 1; }
[ -s "${TILERUN_PROFILE_SECRET_PATH:-/volume1/docker/projects/test-webapp/state/secrets/foto_profile_secret}" ] || {
  printf 'FOUT: centraal profielsecret ontbreekt; voer eerst de TileRun core-deploy uit.\n' >&2
  exit 1
}

BASE_IMAGE=$(awk -F= '/^TILERUN_FOTO_IMAGE=/{print $2}' .env)
LOCAL_IMAGE=tilerun-foto-server:local-validation
docker build --build-arg "BASE_IMAGE=$BASE_IMAGE" -f overlay.Dockerfile -t "$LOCAL_IMAGE" local-overlay
TILERUN_FOTO_IMAGE="$LOCAL_IMAGE" compose --env-file .env -p tilerun-foto -f compose.yml up -d --no-deps --force-recreate foto-server

tries=0
until ./scripts/health.sh >/dev/null 2>&1; do
  tries=$((tries + 1))
  [ "$tries" -lt 45 ] || {
    compose --env-file .env -p tilerun-foto -f compose.yml logs --tail=120 foto-server >&2
    exit 1
  }
  sleep 4
done

./scripts/health.sh
docker exec tilerun-foto-server sh -c "grep -R -F -q '/api/auth/tilerun-access' /build/www" || {
  printf 'FOUT: de draaiende container bevat de TileRun Access-login niet.\n' >&2
  exit 1
}
printf 'OK: de draaiende container bevat de TileRun Access-login.\n'
docker exec tilerun-foto-server sh -c "grep -R -F -q 'syncTileRunFamilyAlbum' /usr/src/app/server/dist" || {
  printf 'FOUT: de draaiende container bevat de gezinskoppeling niet.\n' >&2
  exit 1
}
printf 'OK: de draaiende container bevat de gezinskoppeling.\n'
printf 'Lokale validatie-image is actief; er is niets naar GitHub gepubliceerd.\n'
