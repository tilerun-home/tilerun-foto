#!/bin/sh

for docker_dir in /var/packages/ContainerManager/target/usr/bin /var/packages/Docker/target/usr/bin; do
  [ -x "$docker_dir/docker" ] && PATH="$docker_dir:$PATH"
done
export PATH

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    return 127
  fi
}

