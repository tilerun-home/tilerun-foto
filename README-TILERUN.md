# TileRun Foto

TileRun Foto is the photo and video module for TileRun Home. It is a deliberately light web fork of Immich: photos stay on the customer's NAS, the official Immich mobile clients remain compatible, and authentication is delegated to the same Cloudflare Access identity used by TileRun Home.

## Prototype profile

- Upstream: Immich `v3.1.0`
- Public URL: `https://foto.tilerun.net`
- Target hardware: Synology DS918+, amd64, DSM 7.2+
- Managed media: `/volume1/tilerun-data/photos/library`
- Runtime state: `/volume1/docker/projects/test-webapp/immich`
- Local fallback: `http://192.168.1.2:2283`
- Machine learning: local smart search and face recognition, one worker and two inference threads

## Deployment

The product deployment is in `deployment/tilerun-home`. Copy `.env.example` to `.env`, create the required secret files, render the runtime configuration, and run the preflight before starting the stack. The scripts refuse to continue when secrets are placeholders, storage is too small, the CPU is not amd64, or port 2283 is occupied.

```sh
cd deployment/tilerun-home
cp .env.example .env
mkdir -p secrets runtime
python3 scripts/render-config.py
./scripts/preflight.sh
./scripts/deploy.sh
```

Password login intentionally remains enabled for bootstrap. After web OAuth, mobile OAuth, and maintenance recovery have all passed, set `TILERUN_FOTO_PASSWORD_LOGIN=false`, render the configuration again, and redeploy.

Cloudflare setup, callbacks, the Foto users group, Tunnel ingress, and the least-privilege session-revocation key are documented in `deployment/tilerun-home/CLOUDFLARE.md`.

Never import irreplaceable media until `scripts/restore-test.sh` has succeeded twice against disposable test data.

## Upstream maintenance

Keep `upstream` pointed at `https://github.com/immich-app/immich.git`. TileRun releases use tags such as `v3.1.0-tilerun.1`; every release publishes its source, container image, SBOM, notices, and security scan results.
