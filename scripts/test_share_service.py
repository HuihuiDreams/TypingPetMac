#!/usr/bin/env python3
"""Exercise actual HTTP against an isolated share service; never print credentials."""
import concurrent.futures
import hashlib
import io
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request
import uuid
import zipfile
from PIL import Image

ROOT = Path(__file__).resolve().parent


def package(message="hello", bad_selection=False):
    image = io.BytesIO()
    Image.new("RGBA", (2, 2), "blue").save(image, format="PNG")
    selection = {"mode": "cycle", "presetIDs": ["missing" if bad_selection else "one"]}
    manifest = {"format": "typing-pet-pack", "formatVersion": 1, "name": "Test pack",
                "creatorMessage": message, "images": {"one": "images/one.png"},
                "configuration": {"name": "Test pack", "presets": [
                    {"id": "one", "name": "One", "fileName": "one.png", "source": "imageSet"}],
                    "idle": selection, "unassigned": selection, "mappings": []}}
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("manifest.json", json.dumps(manifest).encode())
        archive.writestr("images/one.png", image.getvalue())
    return data.getvalue()


class ShareServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="typingpet-share-test-")
        sock = socket.socket(); sock.bind(("127.0.0.1", 0)); port = sock.getsockname()[1]; sock.close()
        cls.base = f"http://127.0.0.1:{port}"
        cls.process = subprocess.Popen([sys.executable, str(ROOT / "share_dev_server.py")],
            env={**os.environ, "TYPINGPET_SHARE_STATE_DIR": cls.temp.name, "TYPINGPET_SHARE_PORT": str(port)},
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            try:
                urllib.request.urlopen(cls.base + "/health", timeout=1).close(); break
            except OSError: time.sleep(.05)
        else: raise RuntimeError("Test service did not start")

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate(); cls.process.wait(timeout=5); cls.temp.cleanup()

    def request(self, path, method="GET", body=None, headers=None):
        request = urllib.request.Request(self.base + path, data=body, method=method, headers=headers or {})
        try: response = urllib.request.urlopen(request, timeout=15)
        except urllib.error.HTTPError as error: response = error
        with response:
            data = response.read()
            return response.status, json.loads(data) if response.headers.get_content_type() == "application/json" else data

    def create(self, data=None, headers=None):
        headers = headers or {"X-Request-ID": str(uuid.uuid4()), "X-Request-Secret": uuid.uuid4().hex}
        status, result = self.request("/v1/shares", "POST", data or package(), headers)
        self.assertIn(status, (200, 201))
        return result, headers

    def test_snapshot_revision_authentication_and_deletion(self):
        v1 = package("제작자의 한마디")
        created, _ = self.create(v1)
        code, password = created["code"], created["managementPassword"]
        self.assertRegex(code, r"^[A-Z0-9]{6}$")
        self.assertGreaterEqual(len(password), 24)
        path = "/v1/shares/" + code
        status, preview = self.request(path)
        self.assertEqual(status, 200); self.assertEqual(preview["latestVersion"], 1)
        self.assertEqual(preview["manifest"]["creatorMessage"], "제작자의 한마디")
        self.assertEqual(preview["sha256"], hashlib.sha256(v1).hexdigest())
        self.assertEqual(self.request(path + "/versions/1"), (200, v1))
        self.assertEqual(self.request(path + "/versions", "POST", package("v2"),
            {"X-Share-Password": "incorrect", "X-Base-Version": "1"})[0], 403)
        headers = {"X-Share-Password": password, "X-Base-Version": "1"}
        status, updated = self.request(path + "/versions", "POST", package("v2"), headers)
        self.assertEqual(status, 201); self.assertEqual(updated["latestVersion"], 2)
        self.assertEqual(self.request(path + "/versions", "POST", package("stale"), headers)[0], 409)
        self.assertEqual(self.request(path + "/versions/1"), (200, v1), "Published versions are immutable")
        self.assertEqual(self.request(path + "/versions/999")[0], 404)
        self.assertEqual(self.request(path, "DELETE", headers={"X-Share-Password": "bad"})[0], 403)
        self.assertEqual(self.request(path, "DELETE", headers={"X-Share-Password": password})[0], 200)
        self.assertEqual(self.request(path)[0], 410)
        self.assertEqual(self.request(path + "/versions/1")[0], 404)
        self.assertEqual(hashlib.sha256(v1).hexdigest(), preview["sha256"])
        for file in Path(self.temp.name).glob("*.sqlite3*"):
            self.assertNotIn(password.encode(), file.read_bytes())

    def test_retry_returns_same_code_and_password_without_duplicate_share(self):
        data = package()
        first, headers = self.create(data)
        second, _ = self.create(data, headers)
        self.assertEqual(first["code"], second["code"])
        self.assertEqual(first["managementPassword"], second["managementPassword"])
        self.assertEqual(self.request("/v1/shares", "POST", package("changed"), headers)[0], 409)

    def test_concurrent_creation_retry_and_version_conflict(self):
        headers = {"X-Request-ID": str(uuid.uuid4()), "X-Request-Secret": uuid.uuid4().hex}
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            results = list(pool.map(lambda _: self.create(package(), headers)[0], range(2)))
        self.assertEqual(results[0]["code"], results[1]["code"])
        result = results[0]
        path = "/v1/shares/" + result["code"] + "/versions"
        auth = {"X-Share-Password": result["managementPassword"], "X-Base-Version": "1"}
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            statuses = list(pool.map(lambda _: self.request(path, "POST", package("next"), auth)[0], range(2)))
        self.assertEqual(sorted(statuses), [201, 409])

    def test_backup_can_restore_code_and_files_in_another_directory(self):
        created, _ = self.create()
        with tempfile.TemporaryDirectory(prefix="typingpet-backup-test-") as folder:
            root = Path(folder)
            (root / "data").symlink_to(Path(self.temp.name), target_is_directory=True)
            subprocess.run([sys.executable, str(ROOT / "backup_share_service.py")],
                env={**os.environ, "TYPINGPET_SHARE_SERVICE_ROOT": str(root)}, check=True)
            backup = next((root / "backups").iterdir())
            # Move files away from original paths: restored service must use its own state.
            sock = socket.socket(); sock.bind(("127.0.0.1", 0)); port = sock.getsockname()[1]; sock.close()
            restored = subprocess.Popen([sys.executable, str(ROOT / "share_dev_server.py")],
                env={**os.environ, "TYPINGPET_SHARE_STATE_DIR": str(backup), "TYPINGPET_SHARE_PORT": str(port)},
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            original_base = self.base
            self.base = f"http://127.0.0.1:{port}"
            try:
                for _ in range(100):
                    try:
                        urllib.request.urlopen(self.base + "/health", timeout=1).close(); break
                    except OSError: time.sleep(.05)
                path = "/v1/shares/" + created["code"]
                status, preview = self.request(path)
                self.assertEqual(status, 200)
                status, data = self.request(path + "/versions/1")
                self.assertEqual(status, 200)
                self.assertEqual(hashlib.sha256(data).hexdigest(), preview["sha256"])
                self.assertEqual(self.request(path, "DELETE", headers={"X-Share-Password": created["managementPassword"]})[0], 200)
            finally:
                self.base = original_base
                restored.terminate(); restored.wait(timeout=5)
        self.request("/v1/shares/" + created["code"], "DELETE", headers={"X-Share-Password": created["managementPassword"]})

    def test_rejects_invalid_packages_and_long_message(self):
        headers = {"X-Request-ID": str(uuid.uuid4()), "X-Request-Secret": uuid.uuid4().hex}
        for data in [b"invalid", package("x" * 501), package(bad_selection=True)]:
            self.assertEqual(self.request("/v1/shares", "POST", data, headers)[0], 400)
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive: archive.writestr("../escape", "bad")
        self.assertEqual(self.request("/v1/shares", "POST", data.getvalue(), headers)[0], 400)
        self.assertEqual(self.request("/v1/shares/invalid-code")[0], 404)


if __name__ == "__main__": unittest.main(verbosity=2)
