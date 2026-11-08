#!/usr/bin/env python3
"""Exercise actual HTTP against an isolated share service; never print credentials."""
import concurrent.futures
import base64
import hashlib
import hmac
import sqlite3
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

    def test_custom_password_authorization_and_version_history(self):
        identity = {"X-Request-ID": str(uuid.uuid4()), "X-Request-Secret": uuid.uuid4().hex}
        for password in [""]:
            headers = {**identity, "X-Share-Password-Base64": base64.b64encode(password.encode()).decode()}
            status, result = self.request("/v1/shares", "POST", package(), headers)
            self.assertEqual(status, 400)
            self.assertEqual(result["error"], "password_length")
        password = "한글네자"
        auth = {"X-Share-Password-Base64": base64.b64encode(password.encode()).decode()}
        v1 = package("original")
        created, _ = self.create(v1, {**identity, **auth})
        self.assertEqual(created["managementPassword"], password)
        path = "/v1/shares/" + created["code"]
        self.assertEqual(self.request(path + "/authorize", "POST")[0], 403)
        self.assertEqual(self.request(path + "/authorize", "POST", headers={"X-Share-Password": "wrong"})[0], 403)
        self.assertEqual(self.request(path + "/authorize", "POST", headers=auth)[0], 200)
        self.assertEqual(self.request(path + "/versions", "POST", package("changed"), {**auth, "X-Base-Version": "1"})[0], 201)
        status, history = self.request(path + "/versions")
        self.assertEqual(status, 200)
        self.assertEqual([item["version"] for item in history["versions"]], [2, 1])
        self.assertEqual(history["versions"][1]["creatorMessage"], "original")
        self.assertNotIn("manifest", history["versions"][0])
        status, old = self.request(path + "/versions/1/metadata")
        self.assertEqual(status, 200)
        self.assertEqual(old["latestVersion"], 1)
        self.assertEqual(old["sha256"], hashlib.sha256(v1).hexdigest())
        self.assertEqual(self.request(path)[1]["latestVersion"], 2)
        self.assertEqual(self.request(path + "/versions/99/metadata")[0], 404)
        self.assertEqual(self.request(path + "/versions/not-a-number/metadata")[0], 404)
        self.assertEqual(self.request(path, "DELETE", headers=auth)[0], 200)
        self.assertEqual(self.request(path + "/authorize", "POST", headers=auth)[0], 404)
        self.assertEqual(self.request(path + "/versions")[0], 404)

    def test_custom_password_has_no_character_count_restriction(self):
        for password in ["a", "가나다", "한" * 600]:
            auth = {"X-Share-Password-Base64": base64.b64encode(password.encode()).decode()}
            identity = {"X-Request-ID": str(uuid.uuid4()), "X-Request-Secret": uuid.uuid4().hex}
            created, _ = self.create(package(), {**identity, **auth})
            path = "/v1/shares/" + created["code"]
            self.assertEqual(self.request(path + "/authorize", "POST", headers=auth)[0], 200)
            self.assertEqual(self.request(path, "DELETE", headers=auth)[0], 200)

    def test_community_visibility_requires_password_and_unpublishing_hides_cover(self):
        created, _ = self.create()
        code = created["code"]; path = "/v1/shares/" + code
        self.assertFalse(self.request(path)[1]["isPublic"])
        self.assertNotIn(code, [p["code"] for p in self.request("/v1/community")[1]["packs"]])
        payload = json.dumps({"isPublic": True}).encode()
        self.assertEqual(self.request(path + "/visibility", "POST", payload)[0], 403)
        auth = {"X-Share-Password": created["managementPassword"]}
        self.assertEqual(self.request(path + "/visibility", "POST", payload, auth)[0], 200)
        self.assertTrue(self.request(path)[1]["isPublic"])
        listed = next(p for p in self.request("/v1/community")[1]["packs"] if p["code"] == code)
        self.assertEqual(listed["version"], 1)
        status, cover = self.request("/v1/community/" + code + "/cover")
        self.assertEqual(status, 200); self.assertTrue(cover.startswith(b"\x89PNG"))
        self.assertEqual(self.request(path + "/visibility", "POST", b'{"isPublic":"true"}', auth)[0], 400)
        self.assertEqual(self.request(path + "/versions", "POST", package("public v2"), {**auth,"X-Base-Version":"1"})[0], 201)
        listed = next(p for p in self.request("/v1/community")[1]["packs"] if p["code"] == code)
        self.assertEqual((listed["version"], listed["creatorMessage"]), (2, "public v2"))
        self.assertEqual(self.request(path + "/visibility", "POST", b'{"isPublic":false}', auth)[0], 200)
        self.assertNotIn(code, [p["code"] for p in self.request("/v1/community")[1]["packs"]])
        self.assertEqual(self.request("/v1/community/" + code + "/cover")[0], 404)
        self.assertEqual(self.request(path)[0], 200, "Unpublishing keeps code-based access")
        self.assertEqual(self.request("/v1/community?page=0")[0], 400)
        self.request(path, "DELETE", headers=auth)

    def test_admin_gateway_identity_csrf_review_and_deletion(self):
        created, _ = self.create(package("moderation fixture"))
        key = (Path(self.temp.name) / "lookup.key").read_bytes()
        gateway = hmac.new(key, b"typing-pet-admin-gateway-v1", hashlib.sha256).hexdigest()
        headers = {"Host":"typing-pet-admin.miel.ing","X-Authentik-Username":"akadmin","X-Admin-Gateway":gateway}
        self.assertEqual(self.request("/admin/")[0], 403)
        self.assertEqual(self.request("/admin/", headers={**headers,"X-Admin-Gateway":"forged"})[0], 403)
        self.assertEqual(self.request("/admin/", headers={**headers,"X-Authentik-Username":"ordinary-user"})[0], 403)
        self.assertEqual(self.request("/admin/", headers={**headers,"Host":"pet.miel.ing"})[0], 403)
        self.assertEqual(self.request("/admin/", headers=headers)[0], 200)
        token = self.request("/admin/api/session", headers=headers)[1]["csrfToken"]
        packs = self.request("/admin/api/packs", headers=headers)[1]["packs"]
        own = next(p for p in packs if p["code"] == created["code"])
        path = "/admin/api/packs/" + own["id"]
        self.assertEqual(self.request(path + "/versions", headers=headers)[1]["versions"][0]["version"], 1)
        detail = self.request(path + "/versions/1", headers=headers)[1]
        self.assertEqual(detail["manifest"]["creatorMessage"], "moderation fixture")
        self.assertTrue(self.request(path + "/versions/1/images/one", headers=headers)[1].startswith(b"\x89PNG"))
        self.assertEqual(self.request(path, "DELETE", headers=headers)[0], 403)
        self.assertEqual(self.request(path,"DELETE",headers={**headers,"X-Admin-CSRF":token,"Origin":"https://evil.example"})[0],403)
        self.assertEqual(self.request(path,"DELETE",headers={**headers,"X-Admin-CSRF":token,"Origin":"https://typing-pet-admin.miel.ing"})[0],200)
        self.assertEqual(self.request("/v1/shares/" + created["code"])[0],410)
        with sqlite3.connect(Path(self.temp.name) / "shares.sqlite3") as db:
            self.assertEqual(db.execute("SELECT actor,action FROM moderation_actions WHERE share_id=?", (own["id"],)).fetchone(),("akadmin","delete"))

    def test_legacy_community_migration_runs_once_and_preserves_later_unpublishing(self):
        created, _ = self.create()
        auth = {"X-Share-Password": created["managementPassword"]}
        path = "/v1/shares/" + created["code"]
        with sqlite3.connect(Path(self.temp.name) / "shares.sqlite3") as db:
            db.execute("DELETE FROM service_metadata WHERE key='legacy-community-public-v1'")
        def restart():
            type(self).process.terminate(); type(self).process.wait(timeout=5)
            port = self.base.rsplit(":",1)[1]
            type(self).process = subprocess.Popen([sys.executable,str(ROOT / "share_dev_server.py")],
                env={**os.environ,"TYPINGPET_SHARE_STATE_DIR":self.temp.name,"TYPINGPET_SHARE_PORT":port},stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            for _ in range(100):
                try: urllib.request.urlopen(self.base+"/health",timeout=1).close();return
                except OSError:time.sleep(.05)
            raise RuntimeError("Migration service did not restart")
        restart()
        self.assertTrue(self.request(path)[1]["isPublic"])
        self.assertIn(created["code"],[p["code"] for p in self.request("/v1/community")[1]["packs"]])
        self.request(path+"/visibility","POST",b'{"isPublic":false}',auth)
        restart()
        self.assertFalse(self.request(path)[1]["isPublic"])
        self.request(path,"DELETE",headers=auth)

    def test_rejects_invalid_packages_and_long_message(self):
        headers = {"X-Request-ID": str(uuid.uuid4()), "X-Request-Secret": uuid.uuid4().hex}
        for data in [b"invalid", package("x" * 501), package(bad_selection=True)]:
            self.assertEqual(self.request("/v1/shares", "POST", data, headers)[0], 400)
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive: archive.writestr("../escape", "bad")
        self.assertEqual(self.request("/v1/shares", "POST", data.getvalue(), headers)[0], 400)
        self.assertEqual(self.request("/v1/shares/invalid-code")[0], 404)


if __name__ == "__main__": unittest.main(verbosity=2)
