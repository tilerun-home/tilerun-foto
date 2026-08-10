#!/usr/bin/env python3
"""Create or verify the narrow Cloudflare Access bridge used by TileRun Foto."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


API_BASE = os.environ.get("CLOUDFLARE_API_BASE_URL", "https://api.cloudflare.com/client/v4").rstrip("/")
APP_NAME = "TileRun / Foto Web"
POLICY_NAME = "TileRun / Foto gebruikers"
DESTINATION = "foto.tilerun.net/api/auth/tilerun-access"


class ConfigureError(RuntimeError):
    pass


def read_secret() -> str:
    token = os.environ.get("TILERUN_CF_API_TOKEN", "").strip()
    token_file = os.environ.get("TILERUN_CF_API_TOKEN_FILE", "").strip()
    if not token and token_file:
        try:
            with open(token_file, "r", encoding="utf-8") as handle:
                token = handle.read().strip()
        except OSError as exc:
            raise ConfigureError("Cloudflare API-tokenbestand kan niet worden gelezen.") from exc
    if not token:
        raise ConfigureError("Cloudflare API-token ontbreekt in de TileRun-container.")
    return token


def api_request(method: str, path: str, token: str, body: dict | None = None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(
        f"{API_BASE}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            payload = json.load(exc)
            detail = "; ".join(
                str(item.get("message", "")) for item in payload.get("errors", []) if item.get("message")
            )
        except Exception:
            detail = ""
        suffix = f": {detail}" if detail else ""
        raise ConfigureError(f"Cloudflare API gaf HTTP {exc.code}{suffix}") from exc
    except (OSError, ValueError) as exc:
        raise ConfigureError("Cloudflare API kon niet veilig worden benaderd.") from exc

    if not payload.get("success"):
        raise ConfigureError("Cloudflare API meldde dat de configuratie niet is geslaagd.")
    return payload.get("result")


def select_exact(items: list[dict], name: str, description: str) -> dict:
    matches = [item for item in items if str(item.get("name", "")).strip().lower() == name.lower()]
    if len(matches) != 1:
        raise ConfigureError(f"{description} kon niet eenduidig worden gevonden.")
    return matches[0]


def select_google_provider(providers: list[dict]) -> dict:
    google = [provider for provider in providers if provider.get("type") in {"google", "google-apps"}]
    exact = [provider for provider in google if str(provider.get("name", "")).strip().lower() == "google"]
    if len(exact) == 1:
        return exact[0]
    if len(google) == 1:
        return google[0]
    raise ConfigureError("De Google-loginmethode kon niet eenduidig worden gevonden.")


def build_application(provider_id: str, policy_id: str) -> dict:
    return {
        "name": APP_NAME,
        "type": "self_hosted",
        "destinations": [{"type": "public", "uri": DESTINATION}],
        "session_duration": "24h",
        "allowed_idps": [provider_id],
        "auto_redirect_to_identity": True,
        "app_launcher_visible": False,
        "policies": [{"id": policy_id, "precedence": 1}],
    }


def validate_existing(app: dict, provider_id: str, policy_id: str) -> str:
    if app.get("type") != "self_hosted":
        raise ConfigureError(f"De bestaande Cloudflare-app {APP_NAME} heeft niet het type self-hosted.")

    destinations = app.get("destinations")
    destination_uris = {
        str(item.get("uri", "")).strip().rstrip("/")
        for item in destinations or []
        if isinstance(item, dict) and item.get("type") == "public"
    }
    legacy_domain = str(app.get("domain", "")).strip().rstrip("/")
    if DESTINATION not in destination_uris and legacy_domain != DESTINATION:
        raise ConfigureError(f"De bestaande Cloudflare-app {APP_NAME} beschermt niet uitsluitend de Foto-loginroute.")

    allowed_idps = app.get("allowed_idps")
    if not isinstance(allowed_idps, list) or allowed_idps != [provider_id]:
        raise ConfigureError(f"De bestaande Cloudflare-app {APP_NAME} gebruikt niet uitsluitend Google.")

    policies = app.get("policies") or []
    policy_ids = {item if isinstance(item, str) else item.get("id") for item in policies}
    if policy_id not in policy_ids:
        raise ConfigureError(f"De bestaande Cloudflare-app {APP_NAME} mist het Foto-gebruikersbeleid.")

    audience = str(app.get("aud", "")).strip()
    if not audience:
        raise ConfigureError(f"De bestaande Cloudflare-app {APP_NAME} heeft geen audience-tag.")
    return audience


def main() -> int:
    account_id = os.environ.get("TILERUN_CF_ACCOUNT_ID", "").strip()
    if not account_id:
        raise ConfigureError("TILERUN_CF_ACCOUNT_ID ontbreekt in de TileRun-container.")

    token = read_secret()
    providers = api_request(
        "GET", f"/accounts/{account_id}/access/identity_providers?per_page=100", token
    )
    policies = api_request("GET", f"/accounts/{account_id}/access/policies?per_page=100", token)
    applications = api_request("GET", f"/accounts/{account_id}/access/apps?per_page=100", token)
    if not all(isinstance(items, list) for items in (providers, policies, applications)):
        raise ConfigureError("Cloudflare gaf een onverwacht lijstantwoord.")

    provider = select_google_provider(providers)
    policy = select_exact(policies, POLICY_NAME, f"Het herbruikbare beleid {POLICY_NAME}")
    existing = [app for app in applications if str(app.get("name", "")).strip().lower() == APP_NAME.lower()]
    if len(existing) > 1:
        raise ConfigureError(f"Meerdere Cloudflare-apps met de naam {APP_NAME} gevonden.")

    if existing:
        application_id = str(existing[0].get("id", ""))
        if not application_id:
            raise ConfigureError(f"De bestaande Cloudflare-app {APP_NAME} heeft geen ID.")
        application = api_request("GET", f"/accounts/{account_id}/access/apps/{application_id}", token)
        if not isinstance(application, dict):
            raise ConfigureError("Cloudflare gaf geen geldige bestaande Access-app terug.")
        audience = validate_existing(application, str(provider["id"]), str(policy["id"]))
        print(f"OK: bestaande Cloudflare-app {APP_NAME} is correct.", file=sys.stderr)
    else:
        created = api_request(
            "POST",
            f"/accounts/{account_id}/access/apps",
            token,
            build_application(str(provider["id"]), str(policy["id"])),
        )
        if not isinstance(created, dict):
            raise ConfigureError("Cloudflare gaf geen geldige nieuwe Access-app terug.")
        application_id = str(created.get("id", ""))
        if not application_id:
            raise ConfigureError("De nieuwe Cloudflare-app heeft geen ID.")
        application = api_request("GET", f"/accounts/{account_id}/access/apps/{application_id}", token)
        if not isinstance(application, dict):
            raise ConfigureError("Cloudflare gaf geen geldige nieuwe Access-app terug.")
        audience = validate_existing(application, str(provider["id"]), str(policy["id"]))
        print(f"OK: Cloudflare-app {APP_NAME} is aangemaakt.", file=sys.stderr)

    print(audience)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ConfigureError as exc:
        print(f"FOUT: {exc}", file=sys.stderr)
        raise SystemExit(1)
