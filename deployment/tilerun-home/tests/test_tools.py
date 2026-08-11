from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


def load_script(name: str):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), SCRIPTS / name)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


class DeploymentToolsTest(unittest.TestCase):
    def test_cloudflare_sso_audit_selects_google_and_never_exposes_credentials(self):
        module = load_script("cloudflare-sso-audit.py")
        provider = module.select_google_provider(
            [
                {"name": "One-time PIN", "type": "onetimepin"},
                {
                    "name": "Google",
                    "type": "google",
                    "config": {
                        "client_id": "sensitive-client-id",
                        "client_secret": "sensitive-client-secret",
                        "prompt": "select_account",
                    },
                },
            ]
        )
        self.assertEqual(provider["name"], "Google")
        self.assertEqual(module.safe_prompt(provider), "select_account")

    def test_cloudflare_sso_audit_handles_missing_prompt(self):
        module = load_script("cloudflare-sso-audit.py")
        self.assertEqual(module.safe_prompt({"config": {"client_id": "hidden"}}), "niet ingesteld")

    def test_cloudflare_sso_audit_selects_foto_application(self):
        module = load_script("cloudflare-sso-audit.py")
        app = module.select_foto_application(
            [{"name": "tilerun.net", "type": "self_hosted"}, {"name": "TileRun / Foto", "type": "saas"}]
        )
        self.assertEqual(app["type"], "saas")

    def test_cloudflare_sso_audit_redacts_authorization_url(self):
        module = load_script("cloudflare-sso-audit.py")
        response = MagicMock()
        response.__enter__.return_value = response
        response.__exit__.return_value = False
        response.read.return_value = json.dumps(
            {
                "url": "https://team.cloudflareaccess.com/authorize?client_id=secret-client&state=secret-state"
                "&prompt=select_account&login_hint=person%40example.com"
            }
        ).encode()
        with patch.object(module.urllib.request, "urlopen", return_value=response):
            inspected = module.inspect_immich_authorization()
        self.assertEqual(inspected["prompt"], "select_account")
        self.assertEqual(inspected["login_hint"], "ingesteld")
        self.assertNotIn("secret-client", inspected.values())
        self.assertNotIn("secret-state", inspected.values())

    def test_cloudflare_access_bridge_is_limited_to_the_login_endpoint(self):
        module = load_script("configure-cloudflare-access-web-login.py")
        payload = module.build_application("google-id", "foto-policy-id")
        self.assertEqual(payload["type"], "self_hosted")
        self.assertEqual(
            payload["destinations"],
            [{"type": "public", "uri": "foto.tilerun.net/api/auth/tilerun-access"}],
        )
        self.assertEqual(payload["allowed_idps"], ["google-id"])
        self.assertEqual(payload["policies"], [{"id": "foto-policy-id", "precedence": 1}])
        self.assertFalse(payload["app_launcher_visible"])

    def test_cloudflare_access_bridge_rejects_broad_existing_application(self):
        module = load_script("configure-cloudflare-access-web-login.py")
        app = {
            "name": module.APP_NAME,
            "type": "self_hosted",
            "destinations": [{"type": "public", "uri": "foto.tilerun.net/*"}],
            "allowed_idps": ["google-id"],
            "policies": [{"id": "foto-policy-id", "precedence": 1}],
            "aud": "audience",
        }
        with self.assertRaises(module.ConfigureError):
            module.validate_existing(app, "google-id", "foto-policy-id")

    def test_rendered_config_uses_supported_queue_names(self):
        module = load_script("render-config.py")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "secrets").mkdir()
            (root / "secrets" / "oidc_client_secret").write_text("test-secret", encoding="utf-8")
            (root / ".env").write_text(
                "TILERUN_FOTO_OIDC_ISSUER=https://access.example/issuer\n"
                "TILERUN_FOTO_OIDC_CLIENT_ID=test-client\n"
                "TILERUN_FOTO_EXTERNAL_URL=https://foto.tilerun.net\n",
                encoding="utf-8",
            )
            module.ROOT = root
            with patch.dict("os.environ", {}, clear=True):
                module.main()
            config = json.loads((root / "runtime" / "immich.json").read_text(encoding="utf-8"))
            supported = {
                "thumbnailGeneration", "metadataExtraction", "videoConversion", "faceDetection", "smartSearch",
                "backgroundTask", "migration", "search", "sidecar", "library", "notifications", "ocr", "workflow",
                "editor", "integrityCheck",
            }
            self.assertLessEqual(set(config["job"]), supported)
            self.assertEqual(config["oauth"]["mobileRedirectUri"], "https://foto.tilerun.net/api/oauth/mobile-redirect")
            self.assertTrue(config["machineLearning"]["facialRecognition"]["enabled"])

    def test_media_manifest_detects_changed_restore(self):
        module = load_script("media-manifest.py")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "album").mkdir()
            photo = root / "album" / "test.jpg"
            photo.write_bytes(b"test-photo")
            expected = module.manifest(root)
            self.assertEqual(expected["file_count"], 1)
            photo.write_bytes(b"changed-photo")
            self.assertNotEqual(module.manifest(root), expected)

    def test_rendered_config_supports_local_bootstrap_without_oidc_secret(self):
        module = load_script("render-config.py")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "secrets").mkdir()
            (root / ".env").write_text(
                "TILERUN_FOTO_OAUTH_ENABLED=false\n"
                "TILERUN_FOTO_PASSWORD_LOGIN=true\n"
                "TILERUN_FOTO_EXTERNAL_URL=https://foto.tilerun.net\n",
                encoding="utf-8",
            )
            module.ROOT = root
            with patch.dict("os.environ", {}, clear=True):
                module.main()
            config = json.loads((root / "runtime" / "immich.json").read_text(encoding="utf-8"))
            self.assertEqual(config["oauth"], {"enabled": False})
            self.assertTrue(config["passwordLogin"]["enabled"])


if __name__ == "__main__":
    unittest.main()
