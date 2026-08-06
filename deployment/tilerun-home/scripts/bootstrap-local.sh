#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

for docker_dir in /var/packages/ContainerManager/target/usr/bin /var/packages/Docker/target/usr/bin; do
  [ -x "$docker_dir/docker" ] && PATH="$docker_dir:$PATH"
done
export PATH

[ -f .env ] || { printf 'FOUT: .env ontbreekt.\n' >&2; exit 1; }
mkdir -p secrets runtime backups
umask 077

if [ ! -s secrets/db_password ]; then
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32 > secrets/db_password
  else
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > secrets/db_password
  fi
fi

chmod 600 secrets/db_password
chmod 700 scripts/*.sh
python3 scripts/render-config.py

printf 'Lokale bootstrap gereed; containers worden nu gestart.\n'
exec ./scripts/deploy.sh
