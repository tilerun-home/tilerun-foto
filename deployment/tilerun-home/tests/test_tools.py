from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


def load_script(name: str):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), SCRIPTS / name)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


class DeploymentToolsTest(unittest.TestCase):
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
