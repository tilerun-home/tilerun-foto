#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

REPLACE_SECRET=false
case "${1:-}" in
  '') ;;
  --replace-secret) REPLACE_SECRET=true ;;
  *) printf 'Gebruik: %s [--replace-secret]\n' "$0" >&2; exit 1 ;;
esac

TTY=/dev/tty
[ -r "$TTY" ] && [ -w "$TTY" ] || {
  printf 'FOUT: voer dit script uit in een interactieve SSH-sessie met -tt.\n' >&2
  exit 1
}

for docker_dir in /var/packages/ContainerManager/target/usr/bin /var/packages/Docker/target/usr/bin; do
  [ -x "$docker_dir/docker" ] && PATH="$docker_dir:$PATH"
done
export PATH

[ -f .env ] || { printf 'FOUT: .env ontbreekt.\n' >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { printf 'FOUT: curl ontbreekt.\n' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FOUT: Python 3 ontbreekt.\n' >&2; exit 1; }
mkdir -p secrets runtime backups
umask 077

TEAM_ISSUER=$(awk -F= '/^TILERUN_CF_ACCESS_ISSUER=/{print $2}' "$ROOT/../.env" 2>/dev/null || true)
case "$TEAM_ISSUER" in
  https://*.cloudflareaccess.com) ;;
  *)
    printf 'FOUT: TILERUN_CF_ACCESS_ISSUER ontbreekt in de bovenliggende TileRun-configuratie.\n' >&2
    exit 1
    ;;
esac

CLIENT_ID=$(awk -F= '/^TILERUN_FOTO_OIDC_CLIENT_ID=/{print $2}' .env)
case "$CLIENT_ID" in
  ''|*CHANGE-ME*)
    printf 'Plak de Cloudflare Client ID en druk op Enter: ' > "$TTY"
    IFS= read -r CLIENT_ID < "$TTY"
    ;;
  *) printf 'OK: opgeslagen Cloudflare Client ID wordt hergebruikt.\n' ;;
esac
case "$CLIENT_ID" in
  ''|*[!A-Za-z0-9_-]*)
    printf 'FOUT: ongeldige Client ID.\n' >&2
    exit 1
    ;;
esac

if [ "$REPLACE_SECRET" = false ] && [ -s secrets/oidc_client_secret ]; then
  OIDC_SECRET=$(sed -n '1p' secrets/oidc_client_secret)
  printf 'OK: opgeslagen Cloudflare Client secret wordt hergebruikt.\n'
else
  restore_tty() {
    stty echo < "$TTY" 2>/dev/null || true
  }
  trap restore_tty EXIT HUP INT TERM
  printf 'Plak het NIEUWE Client secret (invoer blijft verborgen) en druk op Enter: ' > "$TTY"
  stty -echo < "$TTY"
  IFS= read -r OIDC_SECRET < "$TTY"
  stty echo < "$TTY"
  printf '\n' > "$TTY"
fi

[ "${#OIDC_SECRET}" -ge 32 ] || {
  printf 'FOUT: het Client secret is onverwacht kort.\n' >&2
  exit 1
}

OIDC_ISSUER="$TEAM_ISSUER/cdn-cgi/access/sso/oidc/$CLIENT_ID"
cp .env "backups/env-before-sso-$(date '+%Y%m%d-%H%M%S').txt"
printf '%s\n' "$OIDC_SECRET" > secrets/oidc_client_secret
chmod 600 secrets/oidc_client_secret
unset OIDC_SECRET

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

set_env TILERUN_FOTO_OIDC_ISSUER "$OIDC_ISSUER"
set_env TILERUN_FOTO_OIDC_CLIENT_ID "$CLIENT_ID"
set_env TILERUN_FOTO_OAUTH_ENABLED true
set_env TILERUN_FOTO_PASSWORD_LOGIN false
set_env TILERUN_FOTO_REQUIRE_PUBLIC_EDGE true

SERVER_CONFIG=$(curl -fsS --max-time 10 http://192.168.1.2:2283/api/server/config)
if printf '%s' "$SERVER_CONFIG" | grep -Eq '"isInitialized"[[:space:]]*:[[:space:]]*false'; then
  ADMIN_EMAIL=$(awk -F= '/^TILERUN_FOTO_SUPERUSER_EMAIL=/{print $2}' .env)
  ADMIN_NAME=$(awk -F= '/^TILERUN_FOTO_SUPERUSER_NAME=/{sub(/^[^=]*=/, ""); print}' .env)
  ADMIN_NAME=${ADMIN_NAME:-TileRun beheerder}
  [ -n "$ADMIN_EMAIL" ] || { printf 'FOUT: TILERUN_FOTO_SUPERUSER_EMAIL ontbreekt.\n' >&2; exit 1; }

  if command -v openssl >/dev/null 2>&1; then
    ADMIN_PASSWORD=$(openssl rand -hex 32)
  else
    ADMIN_PASSWORD=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
  fi
  printf '%s\n' "$ADMIN_PASSWORD" > secrets/bootstrap_admin_password
  chmod 600 secrets/bootstrap_admin_password

  PAYLOAD=$(ADMIN_EMAIL="$ADMIN_EMAIL" ADMIN_NAME="$ADMIN_NAME" ADMIN_PASSWORD="$ADMIN_PASSWORD" python3 -c 'import json, os; print(json.dumps({"email": os.environ["ADMIN_EMAIL"], "name": os.environ["ADMIN_NAME"], "password": os.environ["ADMIN_PASSWORD"]}))')
  HTTP_STATUS=$(curl -sS --max-time 15 -o runtime/admin-bootstrap-response.json -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' --data "$PAYLOAD" \
    http://192.168.1.2:2283/api/auth/admin-sign-up)
  unset ADMIN_PASSWORD PAYLOAD
  case "$HTTP_STATUS" in
    200|201) printf 'OK: intern beheerprofiel voor %s aangemaakt.\n' "$ADMIN_EMAIL" ;;
    *)
      printf 'FOUT: intern beheerprofiel kon niet worden aangemaakt (HTTP %s).\n' "$HTTP_STATUS" >&2
      exit 1
      ;;
  esac
else
  printf 'OK: intern beheerprofiel bestaat al.\n'
fi

python3 scripts/render-config.py
./scripts/deploy.sh

printf '\nTileRun SSO is actief. Wachtwoordlogin en losse registratie zijn uitgeschakeld.\n'
printf 'Open https://foto.tilerun.net en meld aan met het bestaande TileRun-account.\n'
