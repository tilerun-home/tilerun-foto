#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
# shellcheck disable=SC1091
. "$ROOT/scripts/lib-compose.sh"

command -v docker >/dev/null 2>&1 || {
  printf 'FOUT: Docker/Container Manager kon niet worden gevonden.\n' >&2
  exit 1
}

AUDIENCE=${1:-}
if [ -z "$AUDIENCE" ]; then
  [ -s "$ROOT/scripts/configure-cloudflare-access-web-login.py" ] || {
    printf 'FOUT: Cloudflare-configuratiehulp ontbreekt.\n' >&2
    exit 1
  }
  printf 'Cloudflare Access-app voor de beveiligde Foto-login wordt gecontroleerd.\n' >&2
  AUDIENCE=$(docker exec -i test-webapp python - < "$ROOT/scripts/configure-cloudflare-access-web-login.py")
fi
case "$AUDIENCE" in
  ''|*[!A-Za-z0-9_-]*)
    printf 'FOUT: ongeldige Cloudflare Access-audience.\n' >&2
    exit 1
    ;;
esac
[ "${#AUDIENCE}" -ge 32 ] && [ "${#AUDIENCE}" -le 128 ] || {
  printf 'FOUT: ongeldige lengte voor Cloudflare Access-audience.\n' >&2
  exit 1
}

ISSUER=$(awk -F= '/^TILERUN_CF_ACCESS_ISSUER=/{print $2}' "$ROOT/../.env" 2>/dev/null || true)
case "$ISSUER" in
  https://*.cloudflareaccess.com) ;;
  *)
    printf 'FOUT: TILERUN_CF_ACCESS_ISSUER ontbreekt in de centrale TileRun-configuratie.\n' >&2
    exit 1
    ;;
esac

set_env() {
  key=$1
  value=$2
  tmp=".env.tmp.$$"
  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    index($0, key "=") == 1 { print key "=" value; found = 1; next }
    { print }
    END { if (!found) print key "=" value }
  ' .env > "$tmp"
  mv "$tmp" .env
}

mkdir -p backups
cp .env "backups/env-before-access-web-login-$(date '+%Y%m%d-%H%M%S').txt"
set_env TILERUN_CF_ACCESS_ISSUER "$ISSUER"
set_env TILERUN_CF_ACCESS_AUD "$AUDIENCE"
sh scripts/deploy-local-overlay.sh

printf 'TileRun Access-weblogin is geactiveerd voor uitsluitend /api/auth/tilerun-access.\n'
