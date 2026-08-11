#!/usr/bin/env python3
"""Audit the Cloudflare Google IdP without exposing credentials."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


API_BASE = os.environ.get("CLOUDFLARE_API_BASE_URL", "https://api.cloudflare.com/client/v4").rstrip("/")


class AuditError(RuntimeError):
    pass


def read_secret() -> str:
    token = os.environ.get("TILERUN_CF_API_TOKEN", "").strip()
    token_file = os.environ.get("TILERUN_CF_API_TOKEN_FILE", "").strip()
    if not token and token_file:
        try:
            with open(token_file, "r", encoding="utf-8") as handle:
                token = handle.read().strip()
        except OSError as exc:
            raise AuditError("Cloudflare API-tokenbestand kan niet worden gelezen.") from exc
    if not token:
        raise AuditError("Cloudflare API-token ontbreekt in de TileRun-container.")
    return token


def api_get_result(path: str, token: str):
    request = urllib.request.Request(
        f"{API_BASE}{path}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            payload = json.load(exc)
            messages = [str(item.get("message", "")) for item in payload.get("errors", [])]
            detail = "; ".join(message for message in messages if message)
        except Exception:
            detail = ""
        suffix = f": {detail}" if detail else ""
        raise AuditError(f"Cloudflare API gaf HTTP {exc.code}{suffix}") from exc
    except (OSError, ValueError) as exc:
        raise AuditError("Cloudflare API kon niet veilig worden uitgelezen.") from exc

    if not payload.get("success"):
        raise AuditError("Cloudflare API meldde dat de controle niet is geslaagd.")
    return payload.get("result")


def api_get_list(path: str, token: str) -> list[dict]:
    result = api_get_result(path, token)
    if not isinstance(result, list):
        raise AuditError("Onverwacht lijstantwoord van Cloudflare API.")
    return result


def api_get_object(path: str, token: str) -> dict:
    result = api_get_result(path, token)
    if not isinstance(result, dict):
        raise AuditError("Onverwacht objectantwoord van Cloudflare API.")
    return result


def inspect_immich_authorization() -> dict[str, str]:
    endpoint = os.environ.get("TILERUN_FOTO_INTERNAL_URL", "http://192.168.1.2:2283").rstrip("/")
    body = json.dumps({"redirectUri": "https://foto.tilerun.net/auth/login"}).encode("utf-8")
    request = urllib.request.Request(
        f"{endpoint}/api/oauth/authorize",
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.load(response)
    except (urllib.error.HTTPError, OSError, ValueError) as exc:
        raise AuditError("De actuele OAuth-autorisatie-URL van TileRun Foto kon niet worden gecontroleerd.") from exc
    url = payload.get("url")
    if not isinstance(url, str):
        raise AuditError("TileRun Foto gaf geen geldige OAuth-autorisatie-URL terug.")
    parsed = urllib.parse.urlparse(url)
    query = urllib.parse.parse_qs(parsed.query)
    return {
        "host": parsed.hostname or "onbekend",
        "prompt": query.get("prompt", ["niet ingesteld"])[0],
        "max_age": query.get("max_age", ["niet ingesteld"])[0],
        "login_hint": "ingesteld" if query.get("login_hint") else "niet ingesteld",
    }


def select_google_provider(providers: list[dict]) -> dict:
    google = [provider for provider in providers if provider.get("type") in {"google", "google-apps"}]
    exact = [provider for provider in google if str(provider.get("name", "")).strip().lower() == "google"]
    if len(exact) == 1:
        return exact[0]
    if len(google) == 1:
        return google[0]
    if not google:
        raise AuditError("Geen Google identity provider gevonden.")
    names = ", ".join(sorted(str(provider.get("name", "zonder naam")) for provider in google))
    raise AuditError(f"Meerdere Google identity providers gevonden ({names}); er is niets gewijzigd.")


def safe_prompt(provider: dict) -> str:
    config = provider.get("config")
    if not isinstance(config, dict):
        return "niet ingesteld"
    prompt = config.get("prompt")
    return str(prompt) if prompt in {"login", "select_account", "none"} else "niet ingesteld"


def select_foto_application(applications: list[dict]) -> dict:
    matches = [app for app in applications if str(app.get("name", "")).strip().lower() == "tilerun / foto"]
    if len(matches) != 1:
        raise AuditError("De Cloudflare-app TileRun / Foto kon niet eenduidig worden gevonden.")
    return matches[0]


def main() -> int:
    account_id = os.environ.get("TILERUN_CF_ACCOUNT_ID", "").strip()
    if not account_id:
        raise AuditError("TILERUN_CF_ACCOUNT_ID ontbreekt in de TileRun-container.")

    token = read_secret()
    providers = api_get_list(f"/accounts/{account_id}/access/identity_providers", token)
    provider = select_google_provider(providers)
    prompt = safe_prompt(provider)
    applications = api_get_list(f"/accounts/{account_id}/access/apps", token)
    foto_app = select_foto_application(applications)
    organization = api_get_object(f"/accounts/{account_id}/access/organizations", token)
    immich_authorization = inspect_immich_authorization()
    allowed_idps = foto_app.get("allowed_idps")
    allowed_count = len(allowed_idps) if isinstance(allowed_idps, list) else 0

    print("Cloudflare Google SSO-controle")
    print(f"Provider: {provider.get('name', 'Google')}")
    print(f"Type: {provider.get('type', 'onbekend')}")
    print(f"Geforceerde Google-prompt: {prompt}")
    print(f"Foto-app type: {foto_app.get('type', 'onbekend')}")
    print(f"Foto-app sessieduur: {foto_app.get('session_duration', 'standaard')}")
    print(f"Globale Cloudflare-sessieduur: {organization.get('session_duration', 'standaard (24h)')}")
    print(f"Foto-app directe IdP-doorstuur: {'aan' if foto_app.get('auto_redirect_to_identity') else 'uit'}")
    print(f"Foto-app aantal geselecteerde loginmethoden: {allowed_count or 'alle beschikbare'}")
    print(f"Foto OAuth-host: {immich_authorization['host']}")
    print(f"Foto OAuth prompt: {immich_authorization['prompt']}")
    print(f"Foto OAuth max_age: {immich_authorization['max_age']}")
    print(f"Foto OAuth login_hint: {immich_authorization['login_hint']}")
    if prompt == "select_account":
        print("UITKOMST: oorzaak gevonden; Cloudflare dwingt de Google-accountkiezer af.")
    elif prompt == "login":
        print("UITKOMST: oorzaak gevonden; Cloudflare dwingt een nieuwe Google-login af.")
    elif prompt == "none":
        print("UITKOMST: Cloudflare vraagt Google om stille authenticatie; dit veld veroorzaakt geen accountkiezer.")
    else:
        print("UITKOMST: deze provider bevat geen geforceerde prompt; er moet verder naar de Access-appsessie worden gekeken.")
    print("Er is niets gewijzigd en er zijn geen sleutels weergegeven.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AuditError as exc:
        print(f"FOUT: {exc}", file=sys.stderr)
        raise SystemExit(1)
