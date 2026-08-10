#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

for docker_dir in /var/packages/ContainerManager/target/usr/bin /var/packages/Docker/target/usr/bin; do
  [ -x "$docker_dir/docker" ] && PATH="$docker_dir:$PATH"
done
export PATH

command -v docker >/dev/null 2>&1 || {
  printf 'FOUT: Docker is niet gevonden.\n' >&2
  exit 1
}
docker inspect test-webapp >/dev/null 2>&1 || {
  printf 'FOUT: de centrale TileRun-container test-webapp draait niet.\n' >&2
  exit 1
}
[ -s "$ROOT/scripts/cloudflare-sso-audit.py" ] || {
  printf 'FOUT: cloudflare-sso-audit.py ontbreekt.\n' >&2
  exit 1
}

printf 'De Google-logininstelling wordt alleen-lezen gecontroleerd.\n'
docker exec -i test-webapp python - < "$ROOT/scripts/cloudflare-sso-audit.py"
