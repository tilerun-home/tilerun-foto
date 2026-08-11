#!/bin/sh
set -eu

PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/packages/Docker/target/usr/bin:/var/packages/ContainerManager/target/usr/bin:${PATH:-}"
export PATH

ROOT=/volume1/docker/projects/test-webapp
FOTO_ROOT="$ROOT/immich"
STAGING="$FOTO_ROOT/.local-upload"
STAMP=$(date +%Y%m%d-%H%M%S)

[ -s "$STAGING/foto_sync.py" ] || { echo 'FOUT: centrale Foto-sync ontbreekt.' >&2; exit 1; }
[ -s "$STAGING/profiles.py" ] || { echo 'FOUT: centrale profielcontrole ontbreekt.' >&2; exit 1; }
[ -s "$STAGING/api.py" ] || { echo 'FOUT: centrale Foto-API ontbreekt.' >&2; exit 1; }
[ -s "$STAGING/server-dist.tar.gz" ] || { echo 'FOUT: Foto-serverbuild ontbreekt.' >&2; exit 1; }

cp "$ROOT/app/tilerun_access/foto_sync.py" "$ROOT/app/tilerun_access/foto_sync.py.before-family-$STAMP"
cp "$ROOT/app/tilerun_access/profiles.py" "$ROOT/app/tilerun_access/profiles.py.before-family-$STAMP"
cp "$ROOT/app/tilerun_access/api.py" "$ROOT/app/tilerun_access/api.py.before-family-$STAMP"
install -m 644 "$STAGING/foto_sync.py" "$ROOT/app/tilerun_access/foto_sync.py"
install -m 644 "$STAGING/profiles.py" "$ROOT/app/tilerun_access/profiles.py"
install -m 644 "$STAGING/api.py" "$ROOT/app/tilerun_access/api.py"

echo 'TileRun Home wordt bijgewerkt en maakt eerst een databaseback-up.'
cd "$ROOT"
sh deploy.sh core

install -m 600 "$STAGING/server-dist.tar.gz" "$FOTO_ROOT/local-overlay/server-dist.tar.gz"
install -m 600 "$STAGING/web-build.tar.gz" "$FOTO_ROOT/local-overlay/web-build.tar.gz"
install -m 700 "$STAGING/deploy-local-overlay.sh" "$FOTO_ROOT/scripts/deploy-local-overlay.sh"
install -m 600 "$STAGING/compose.yml" "$FOTO_ROOT/compose.yml"

echo 'TileRun Foto wordt met de gezinskoppeling bijgewerkt.'
cd "$FOTO_ROOT"
sh scripts/deploy-local-overlay.sh

if command -v docker >/dev/null 2>&1; then
  DOCKER=$(command -v docker)
elif [ -x /var/packages/ContainerManager/target/usr/bin/docker ]; then
  DOCKER=/var/packages/ContainerManager/target/usr/bin/docker
else
  DOCKER=/var/packages/Docker/target/usr/bin/docker
fi

echo 'De vier toegestane TileRun-gebruikers en het gezinsalbum worden nu verzoend.'
"$DOCKER" exec tilerun-access-worker python -c "import json,os; from tilerun_access.config import AccessConfig; from tilerun_access.db import configure; from tilerun_access.foto_sync import sync_users; p=os.environ.get('TILERUN_STATE_DB_PATH','/state/tilerun_web.db'); c=AccessConfig.from_env(p); configure(c.state_db_path); print(json.dumps(sync_users(c),ensure_ascii=False))"

echo 'OK: accountkoppeling en veilig gezinsalbum zijn actief.'
echo 'Privéfoto’s zijn niet automatisch aan het album toegevoegd.'
