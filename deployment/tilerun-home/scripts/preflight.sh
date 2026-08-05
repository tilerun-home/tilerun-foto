#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

fail() { printf 'FOUT: %s\n' "$1" >&2; exit 1; }
note() { printf 'OK: %s\n' "$1"; }

[ -f .env ] || fail "Kopieer .env.example naar .env en vul de waarden in."
[ -s secrets/db_password ] || fail "secrets/db_password ontbreekt of is leeg."
[ -s secrets/oidc_client_secret ] || fail "secrets/oidc_client_secret ontbreekt of is leeg."
[ -s runtime/immich.json ] || fail "Voer eerst scripts/render-config.py uit."
command -v docker >/dev/null 2>&1 || fail "Docker/Container Manager ontbreekt."
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 ontbreekt."
command -v python3 >/dev/null 2>&1 || fail "Python 3 ontbreekt voor configuratie- en restorecontroles."

if [ -r /etc/VERSION ]; then
  DSM_MAJOR=$(awk -F= '/^majorversion=/{gsub(/"/,"",$2); print $2}' /etc/VERSION)
  [ "${DSM_MAJOR:-0}" -ge 7 ] || fail "DSM 7 of nieuwer is vereist."
  note "DSM ${DSM_MAJOR} gedetecteerd"
fi

ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ] || fail "Dit prototype ondersteunt alleen amd64; gevonden: $ARCH"
note "amd64-platform"

RAM_KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
[ "${RAM_KB:-0}" -ge 3145728 ] || fail "Minder dan 3 GiB RAM beschikbaar; DS918+ prototypeprofiel is onveilig."
note "minimaal 3 GiB RAM"

set -a
# shellcheck disable=SC1091
. ./.env
set +a

for path in "$UPLOAD_LOCATION" "$DB_DATA_LOCATION" "$MODEL_CACHE_LOCATION" "$BACKUP_LOCATION"; do
  mkdir -p "$path"
  [ -w "$path" ] || fail "Geen schrijfrecht op $path"
done
note "opslagpaden beschikbaar"

FREE_KB=$(df -Pk "$UPLOAD_LOCATION" | awk 'NR==2 {print $4}')
[ "${FREE_KB:-0}" -ge 10485760 ] || fail "Minder dan 10 GiB vrije opslag voor testmedia."
note "minimaal 10 GiB vrije opslag"

FS_TYPE=$(df -T "$UPLOAD_LOCATION" 2>/dev/null | awk 'NR==2 {print $2}' || true)
[ "$FS_TYPE" = btrfs ] && note "Btrfs-mediavolume" || printf 'WAARSCHUWING: volume is %s; Btrfs-snapshots zijn niet beschikbaar.\n' "${FS_TYPE:-onbekend}" >&2

if command -v ss >/dev/null 2>&1 && ss -ltn | awk '{print $4}' | grep -Eq '(^|:)2283$'; then
  docker inspect tilerun-foto-server >/dev/null 2>&1 || fail "TCP-poort 2283 is door een andere service bezet."
fi
note "poort 2283 beschikbaar of door TileRun Foto beheerd"

if command -v nslookup >/dev/null 2>&1; then
  nslookup foto.tilerun.net >/dev/null 2>&1 || fail "DNS voor foto.tilerun.net resolveert niet."
  note "publieke DNS resolveert"
fi

docker ps --format '{{.Names}}' | grep -Eq 'cloudflared|cloudflare.*tunnel' \
  || fail "Geen actieve Cloudflare Tunnel-container gevonden."
note "Cloudflare Tunnel actief"

docker compose --env-file .env -f compose.yml config >/dev/null
note "Compose-configuratie geldig"

if command -v curl >/dev/null 2>&1; then
  curl -fsS --max-time 10 https://github.com/immich-app/immich/releases/tag/v3.1.0 >/dev/null \
    || fail "Immich upstream is niet bereikbaar."
  note "upstream bereikbaar"
fi

printf 'Preflight geslaagd. Gebruik uitsluitend testfoto\047s totdat twee restores geslaagd zijn.\n'
