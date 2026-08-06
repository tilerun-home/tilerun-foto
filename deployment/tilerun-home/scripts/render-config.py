#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def required(values: dict[str, str], name: str) -> str:
    value = os.environ.get(name, values.get(name, "")).strip()
    if not value or "CHANGE-ME" in value:
        raise SystemExit(f"Ontbrekende of onveilige configuratie: {name}")
    return value


def enabled(values: dict[str, str], name: str, default: bool) -> bool:
    fallback = "true" if default else "false"
    return os.environ.get(name, values.get(name, fallback)).lower() in {"1", "true", "yes", "on"}


def main() -> None:
    values = load_env(ROOT / ".env")
    oauth_enabled = enabled(values, "TILERUN_FOTO_OAUTH_ENABLED", True)
    password_login = enabled(values, "TILERUN_FOTO_PASSWORD_LOGIN", True)
    if not oauth_enabled and not password_login:
        raise SystemExit("OAuth en wachtwoordlogin mogen niet tegelijk uit staan.")

    oauth: dict[str, object] = {"enabled": False}
    if oauth_enabled:
        secret_path = ROOT / "secrets" / "oidc_client_secret"
        if not secret_path.is_file():
            raise SystemExit("Maak secrets/oidc_client_secret aan met chmod 600.")
        client_secret = secret_path.read_text(encoding="utf-8").strip()
        if not client_secret or "CHANGE-ME" in client_secret:
            raise SystemExit("OIDC-clientsecret is leeg of nog een placeholder.")
        oauth = {
            "enabled": True,
            "issuerUrl": required(values, "TILERUN_FOTO_OIDC_ISSUER"),
            "clientId": required(values, "TILERUN_FOTO_OIDC_CLIENT_ID"),
            "clientSecret": client_secret,
            "scope": "openid email profile",
            "buttonText": "Doorgaan met TileRun",
            "autoRegister": True,
            "autoLaunch": True,
            "mobileOverrideEnabled": True,
            "mobileRedirectUri": "https://foto.tilerun.net/api/oauth/mobile-redirect",
            "signingAlgorithm": "RS256",
            "profileSigningAlgorithm": "none",
            "tokenEndpointAuthMethod": "client_secret_post",
            "roleClaim": "immich_role",
        }

    config = {
        "backup": {"database": {"enabled": True, "cronExpression": "0 2 * * *", "keepLastAmount": 14}},
        "job": {
            "backgroundTask": {"concurrency": 2},
            "smartSearch": {"concurrency": 1},
            "metadataExtraction": {"concurrency": 2},
            "faceDetection": {"concurrency": 1},
            "thumbnailGeneration": {"concurrency": 2},
            "videoConversion": {"concurrency": 1},
            "ocr": {"concurrency": 1},
            "search": {"concurrency": 1},
        },
        "machineLearning": {
            "enabled": True,
            "urls": ["http://foto-machine-learning:3003"],
            "clip": {"enabled": True},
            "facialRecognition": {"enabled": True},
        },
        "nightlyTasks": {"startTime": "02:00"},
        "oauth": oauth,
        "passwordLogin": {"enabled": password_login},
        "server": {
            "externalDomain": required(values, "TILERUN_FOTO_EXTERNAL_URL"),
            "loginPageMessage": "TileRun Foto gebruikt je bestaande TileRun-account. Je foto's blijven op je eigen NAS.",
            "publicUsers": False,
        },
        "trash": {"enabled": True, "days": 30},
    }

    runtime = ROOT / "runtime"
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    output = runtime / "immich.json"
    output.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    try:
        output.chmod(0o600)
    except OSError:
        pass
    print(f"Configuratie geschreven: {output}")
    print(f"OAuth: {'aan' if oauth_enabled else 'uit (lokale bootstrap)'}")
    print(f"Wachtwoordlogin: {'aan (bootstrap)' if password_login else 'uit (SSO-only)'}")


if __name__ == "__main__":
    main()
