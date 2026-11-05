#!/usr/bin/env python3
"""Typing Pet pack exchange service. Bind only to loopback behind a TLS proxy."""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit
import hashlib
import hmac
import json
import os
import secrets
import shutil
import sqlite3
import stat
import sys
import threading
import time
import zipfile
import warnings
import fcntl
from functools import wraps
from PIL import Image
Image.MAX_IMAGE_PIXELS = 16_000_000

HOST = "127.0.0.1"
PORT = int(os.environ.get("TYPINGPET_SHARE_PORT", "17868"))
STATE = Path(os.environ.get(
    "TYPINGPET_SHARE_STATE_DIR",
    str(Path.home() / "Library/Application Support/TypingPetDev/ShareService"),
)).expanduser().resolve()
DB_PATH = STATE / "shares.sqlite3"
KEY_PATH = STATE / "lookup.key"
CODE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
MAX_PACKAGE = 50 * 1024 * 1024
MAX_FILES = 200
MAX_EXPANDED = 200 * 1024 * 1024


def initialize() -> bytes:
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(STATE, 0o700)
    try:
        fd = os.open(KEY_PATH, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(fd, "wb") as key_file:
            key_file.write(secrets.token_bytes(32))
    key = KEY_PATH.read_bytes()
    if len(key) != 32:
        raise RuntimeError("Invalid lookup key in local share state directory")
    os.umask(0o077)
    with sqlite3.connect(DB_PATH) as db:
        db.execute("PRAGMA journal_mode=WAL")
        db.executescript("""
            CREATE TABLE IF NOT EXISTS shares (
                id TEXT PRIMARY KEY,
                code_digest TEXT NOT NULL UNIQUE,
                password_salt BLOB NOT NULL,
                password_hash BLOB NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('active','stopped')),
                latest_version INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                stopped_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS share_versions (
                share_id TEXT NOT NULL REFERENCES shares(id),
                version INTEGER NOT NULL,
                package_path TEXT NOT NULL,
                sha256 TEXT NOT NULL,
                package_size INTEGER NOT NULL,
                manifest_json TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                PRIMARY KEY(share_id, version)
            );
            CREATE TABLE IF NOT EXISTS share_requests (
                request_digest TEXT PRIMARY KEY,
                share_id TEXT NOT NULL REFERENCES shares(id),
                package_hash TEXT NOT NULL
            );
            PRAGMA user_version=2;
        """)
    os.chmod(DB_PATH, 0o600)
    return key


KEY = initialize()


def db_connect() -> sqlite3.Connection:
    db = sqlite3.connect(DB_PATH, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    return db


def code_digest(code: str) -> str:
    return hmac.new(KEY, code.encode("ascii"), hashlib.sha256).hexdigest()


def password_record(password: str, salt: bytes | None = None) -> tuple[bytes, bytes]:
    salt = salt or secrets.token_bytes(16)
    return salt, hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 310_000)


def validate_package(data: bytes) -> dict:
    if not data or len(data) > MAX_PACKAGE:
        raise ValueError("package_size")
    try:
        import io
        archive = zipfile.ZipFile(io.BytesIO(data))
        entries = archive.infolist()
        if len(entries) > MAX_FILES or sum(item.file_size for item in entries) > MAX_EXPANDED:
            raise ValueError("package_size")
        for item in entries:
            name = item.filename
            mode = item.external_attr >> 16
            if (name.startswith(("/", "\\")) or "\\" in name
                    or any(part in {"", ".", ".."} for part in name.rstrip("/").split("/"))
                    or stat.S_ISLNK(mode)):
                raise ValueError("package_invalid")
        manifest_info = archive.getinfo("manifest.json")
        if manifest_info.file_size > 1024 * 1024:
            raise ValueError("package_size")
        raw_manifest = archive.read(manifest_info)
        manifest = json.loads(raw_manifest)
    except (zipfile.BadZipFile, KeyError, json.JSONDecodeError, UnicodeDecodeError, RuntimeError, NotImplementedError):
        raise ValueError("package_invalid") from None
    if not isinstance(manifest, dict) or manifest.get("format") != "typing-pet-pack":
        raise ValueError("package_invalid")
    if not isinstance(manifest.get("name"), str) or not manifest["name"].strip():
        raise ValueError("package_invalid")
    if manifest.get("formatVersion") != 1 or not isinstance(manifest.get("configuration"), dict):
        raise ValueError("package_invalid")
    images = manifest.get("images")
    configuration = manifest["configuration"]
    presets = configuration.get("presets") if isinstance(configuration, dict) else None
    if not isinstance(images, dict) or not isinstance(presets, list):
        raise ValueError("package_invalid")
    names = {item.filename for item in entries}
    preset_ids_list = [item.get("id") for item in presets if isinstance(item, dict)]
    if (len(preset_ids_list) != len(presets)
            or not all(isinstance(value, str) and value for value in preset_ids_list)
            or len(set(preset_ids_list)) != len(preset_ids_list)
            or set(images) != set(preset_ids_list)):
        raise ValueError("package_invalid")
    for path in images.values():
        if (not isinstance(path, str) or not path.startswith("images/")
                or path.startswith("/") or "\\" in path
                or any(part in {"", ".", ".."} for part in path.split("/"))
                or path not in names):
            raise ValueError("package_invalid")
    if not isinstance(configuration.get("name"), str) or configuration["name"] != manifest["name"]:
        raise ValueError("package_invalid")
    mappings = configuration.get("mappings", [])
    if not isinstance(mappings, list) or len(mappings) > 500:
        raise ValueError("package_invalid")
    strokes = set()
    for mapping in mappings:
        if not isinstance(mapping, dict) or not isinstance(mapping.get("stroke"), dict):
            raise ValueError("package_invalid")
        stroke = mapping["stroke"]
        marker = json.dumps(stroke, sort_keys=True)
        if marker in strokes:
            raise ValueError("package_invalid")
        strokes.add(marker)
    for preset in presets:
        if not isinstance(preset.get("name"), str) or not preset["name"].strip():
            raise ValueError("package_invalid")
    message = manifest.get("creatorMessage", "")
    if not isinstance(message, str) or len(message) > 500:
        raise ValueError("message_length")
    if len(names) != len(entries) or not presets or len(presets) > 100:
        raise ValueError("package_invalid")
    ids = set(preset_ids_list)
    for selection in [configuration.get("idle"), configuration.get("unassigned")] + [
            item.get("selection") for item in configuration.get("mappings", []) if isinstance(item, dict)]:
        if (not isinstance(selection, dict) or selection.get("mode") not in {"random", "cycle"}
                or not isinstance(selection.get("presetIDs"), list)
                or not selection["presetIDs"] or not all(isinstance(i, str) for i in selection["presetIDs"])
                or len(set(selection["presetIDs"])) != len(selection["presetIDs"])
                or not set(selection["presetIDs"]).issubset(ids)):
            raise ValueError("package_invalid")
    allowed = {"manifest.json", "images/", *images.values()}
    if not names.issubset(allowed):
        raise ValueError("package_invalid")
    try:
        # Read every entry to verify CRC; decode each image before publication.
        for item in entries:
            archive.read(item)
        for path in set(images.values()):
            with warnings.catch_warnings():
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(archive.read(path))) as image:
                    if image.width * image.height > 16_000_000 or getattr(image, "n_frames", 1) > 500:
                        raise ValueError("package_invalid")
                    image.verify()
    except (OSError, SyntaxError, zipfile.BadZipFile, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise ValueError("package_invalid") from None
    return manifest


def serialized_mutation(operation):
    @wraps(operation)
    def wrapped(self, *args, **kwargs):
        # Backups take the same cross-process lock before copying DB and packages.
        with (STATE / "mutation.lock").open("a+b") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            return operation(self, *args, **kwargs)
    return wrapped


class API(BaseHTTPRequestHandler):
    server_version = "TypingPetLocalShare/0.1"
    protocol_version = "HTTP/1.1"
    rate_lock = threading.Lock()
    rate_windows = {}

    def setup(self):
        super().setup()
        self.connection.settimeout(30)


    def log_message(self, *_args) -> None:
        return

    def send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Connection", "close")
        self.close_connection = True
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def read_body(self) -> bytes:
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            raise ValueError("invalid_content_length") from None
        if size < 1 or size > MAX_PACKAGE:
            raise ValueError("package_size")
        body = self.rfile.read(size)
        if len(body) != size:
            raise ValueError("incomplete_body")
        return body

    def loopback_only(self) -> bool:
        return self.client_address[0] in {"127.0.0.1", "::1"}

    def route(self):
        # The service remains loopback-only; a TLS reverse proxy can forward clients.
        # Bound aggregate requests as well as repeated management attempts.
        with self.rate_lock:
            now = int(time.time()) // 60
            key = (self.headers.get("X-Real-IP", self.client_address[0]), now)
            self.rate_windows = type(self).rate_windows
            for old in list(self.rate_windows):
                if old[1] < now:
                    del self.rate_windows[old]
            count = self.rate_windows.get(key, 0) + 1
            self.rate_windows[key] = count
        if count > 120:
            return self.send_json(429, {"error": "rate_limited"})
        path = unquote(urlsplit(self.path).path)
        if path == "/health" and self.command == "GET":
            return self.send_json(200, {"ok": True, "mode": os.environ.get("TYPINGPET_SHARE_MODE", "local-development"), "version": "0.20.0"})
        if path == "/v1/shares" and self.command == "POST":
            return self.create_share()
        parts = path.strip("/").split("/")
        if len(parts) >= 3 and parts[:2] == ["v1", "shares"]:
            code = parts[2]
            if len(parts) == 3 and self.command == "DELETE":
                return self.stop_share(code)
            if len(parts) == 3 and self.command == "GET":
                return self.describe(code)
            if len(parts) == 4 and parts[3] == "versions" and self.command == "POST":
                return self.add_version(code)
            if len(parts) == 4 and parts[3] == "stop" and self.command == "POST":
                return self.stop_share(code)
            if len(parts) == 5 and parts[3] == "versions" and self.command == "GET":
                return self.download_latest(code, parts[4])
        self.send_json(404, {"error": "not_found"})

    def do_GET(self):
        if not self.loopback_only():
            return self.send_json(403, {"error": "local_only"})
        return self.route()

    def do_POST(self):
        if not self.loopback_only():
            return self.send_json(403, {"error": "local_only"})
        return self.route()

    do_DELETE = do_POST

    def lookup(self, code: str):
        if len(code) != 6 or any(c not in CODE_ALPHABET for c in code):
            return None
        with db_connect() as db:
            return db.execute("SELECT * FROM shares WHERE code_digest=?", (code_digest(code),)).fetchone()

    @serialized_mutation
    def create_share(self):
        request_id = self.headers.get("X-Request-ID", "")
        recovery = self.headers.get("X-Request-Secret", "")
        if not (16 <= len(request_id) <= 128 and 32 <= len(recovery) <= 128):
            return self.send_json(400, {"error": "request_identity_required"})
        identity = hmac.new(KEY, (request_id + ":" + recovery).encode(), hashlib.sha256).hexdigest()
        # Recoverable on an authenticated retry, never persisted in plaintext.
        password = hmac.new(KEY, ("password:" + identity).encode(), hashlib.sha256).hexdigest()[:32]
        code_seed = hmac.new(KEY, ("code:" + identity).encode(), hashlib.sha256).digest()
        try:
            package = self.read_body()
            manifest = validate_package(package)
        except ValueError as error:
            return self.send_json(400, {"error": str(error)})
        package_hash = hashlib.sha256(package).hexdigest()
        with db_connect() as db:
            prior = db.execute("SELECT * FROM share_requests WHERE request_digest=?", (identity,)).fetchone()
            if prior:
                if prior["package_hash"] != package_hash:
                    return self.send_json(409, {"error": "request_conflict"})
                row = db.execute("SELECT * FROM shares WHERE id=?", (prior["share_id"],)).fetchone()
                code = self.generated_code(code_seed, 0)
                # Recover the collision attempt without persisting the plaintext code.
                for attempt in range(20):
                    candidate = self.generated_code(code_seed, attempt)
                    if code_digest(candidate) == row["code_digest"]:
                        code = candidate
                        break
                return self.send_json(200, {"code": code, "managementPassword": password,
                                           "status": row["status"], "latestVersion": row["latest_version"]})
        salt, hashed = password_record(password)
        share_id = secrets.token_hex(16)
        for attempt in range(20):
            code = self.generated_code(code_seed, attempt)
            digest = code_digest(code)
            try:
                with db_connect() as db:
                    db.execute("BEGIN IMMEDIATE")
                    if db.execute("SELECT COUNT(*) FROM shares").fetchone()[0] >= 10000:
                        return self.send_json(503, {"error": "storage_quota"})
                    db.execute("INSERT INTO shares VALUES (?, ?, ?, ?, 'active', 1, ?, NULL)",
                               (share_id, digest, salt, hashed, int(time.time())))
                    # Recheck inside the write transaction for simultaneous retries.
                    if db.execute("SELECT 1 FROM share_requests WHERE request_digest=?", (identity,)).fetchone():
                        db.rollback()
                        return self.create_share_retry(identity, package_hash, code_seed, password)
                    stored = self.store_version(db, share_id, 1, package, manifest)
                    db.execute("INSERT INTO share_requests VALUES (?, ?, ?)", (identity, share_id, package_hash))
                os.chmod(DB_PATH, 0o600)
                return self.send_json(201, {"code": code, "managementPassword": password, "status": "active", "latestVersion": 1, **stored})
            except sqlite3.IntegrityError:
                continue
        return self.send_json(503, {"error": "code_generation_failed"})

    @staticmethod
    def generated_code(seed, attempt):
        digest = hmac.new(seed, str(attempt).encode(), hashlib.sha256).digest()
        number = int.from_bytes(digest, "big") % (36 ** 6)
        result = ""
        for _ in range(6):
            number, index = divmod(number, 36)
            result += CODE_ALPHABET[index]
        return result

    def create_share_retry(self, identity, package_hash, code_seed, password):
        with db_connect() as db:
            prior = db.execute("SELECT * FROM share_requests WHERE request_digest=?", (identity,)).fetchone()
            if prior["package_hash"] != package_hash:
                return self.send_json(409, {"error": "request_conflict"})
            row = db.execute("SELECT * FROM shares WHERE id=?", (prior["share_id"],)).fetchone()
        code = next(self.generated_code(code_seed, a) for a in range(20)
                    if code_digest(self.generated_code(code_seed, a)) == row["code_digest"])
        return self.send_json(200, {"code": code, "managementPassword": password,
                                   "status": row["status"], "latestVersion": row["latest_version"]})

    def store_version(self, db, share_id: str, version: int, package: bytes, manifest: dict) -> dict:
        used = db.execute("SELECT COALESCE(SUM(v.package_size),0) FROM share_versions v JOIN shares s ON s.id=v.share_id WHERE s.status='active'").fetchone()[0]
        if used + len(package) > 5 * 1024 ** 3 or version > 100:
            raise OSError("storage_quota")
        folder = STATE / "packages" / share_id
        folder.mkdir(mode=0o700, parents=True, exist_ok=True)
        final = folder / f"v{version}.zip"
        temp = folder / f".v{version}-{secrets.token_hex(6)}.tmp"
        temp.write_bytes(package)
        os.chmod(temp, 0o600)
        os.replace(temp, final)
        digest = hashlib.sha256(package).hexdigest()
        db.execute("INSERT INTO share_versions VALUES (?, ?, ?, ?, ?, ?, ?)",
                   (share_id, version, str(final), digest, len(package),
                    json.dumps(manifest, ensure_ascii=False), int(time.time())))
        return {"packageSize": len(package), "sha256": digest, "manifest": manifest}

    def authorize(self, share) -> bool:
        password = self.headers.get("X-Share-Password", "")
        if not password or len(password) > 256:
            return False
        candidate = password_record(password, bytes(share["password_salt"]))[1]
        return hmac.compare_digest(candidate, bytes(share["password_hash"]))

    def describe(self, code: str):
        share = self.lookup(code)
        if share is None:
            return self.send_json(404, {"error": "share_unavailable"})
        if share["status"] != "active":
            return self.send_json(410, {"error": "share_unavailable"})
        with db_connect() as db:
            row = db.execute("SELECT version, manifest_json, package_size, sha256, created_at FROM share_versions WHERE share_id=? AND version=?",
                             (share["id"], share["latest_version"])).fetchone()
        return self.send_json(200, {"code": code, "status": share["status"],
                                    "latestVersion": row["version"],
                                    "manifest": json.loads(row["manifest_json"]),
                                    "packageSize": row["package_size"], "sha256": row["sha256"],
                                    "publishedAt": row["created_at"]})

    @serialized_mutation
    def add_version(self, code: str):
        share = self.lookup(code)
        if share is None or share["status"] != "active":
            return self.send_json(404, {"error": "share_unavailable"})
        if not self.authorize(share):
            return self.send_json(403, {"error": "invalid_password"})
        try:
            package = self.read_body()
            manifest = validate_package(package)
        except ValueError as error:
            return self.send_json(400, {"error": str(error)})
        try:
            with db_connect() as db:
                db.execute("BEGIN IMMEDIATE")
                current = db.execute("SELECT * FROM shares WHERE id=?", (share["id"],)).fetchone()
                if current["status"] != "active":
                    return self.send_json(404, {"error": "share_unavailable"})
                if self.headers.get("X-Base-Version") != str(current["latest_version"]):
                    return self.send_json(409, {"error": "version_conflict"})
                version = current["latest_version"] + 1
                result = self.store_version(db, share["id"], version, package, manifest)
                db.execute("UPDATE shares SET latest_version=? WHERE id=?", (version, share["id"]))
            return self.send_json(201, {"code": code, "status": "active", "latestVersion": version, **result})
        except OSError:
            return self.send_json(500, {"error": "package_storage_failed"})

    @serialized_mutation
    def stop_share(self, code: str):
        share = self.lookup(code)
        if share is None or share["status"] != "active":
            return self.send_json(404, {"error": "share_unavailable"})
        if not self.authorize(share):
            return self.send_json(403, {"error": "invalid_password"})
        with db_connect() as db:
            result = db.execute("UPDATE shares SET status='stopped', stopped_at=? WHERE id=? AND status='active'",
                                (int(time.time()), share["id"]))
        shutil.rmtree(STATE / "packages" / share["id"], ignore_errors=True)
        self.send_json(200, {"code": code, "status": "stopped", "latestVersion": share["latest_version"]})

    def download_latest(self, code: str, revision="latest"):
        share = self.lookup(code)
        if share is None or share["status"] != "active":
            return self.send_json(404, {"error": "share_unavailable"})
        if revision != "latest" and (not revision.isascii() or not revision.isdigit() or len(revision) > 9):
            return self.send_json(404, {"error": "version_unavailable"})
        version = share["latest_version"] if revision == "latest" else int(revision)
        with db_connect() as db:
            row = db.execute("SELECT * FROM share_versions WHERE share_id=? AND version=?",
                             (share["id"], version)).fetchone()
        if row is None:
            return self.send_json(404, {"error": "version_unavailable"})
        path = STATE / "packages" / share["id"] / f"v{version}.zip"
        try:
            payload = path.read_bytes()
        except OSError:
            return self.send_json(500, {"error": "package_missing"})
        if hashlib.sha256(payload).hexdigest() != row["sha256"]:
            return self.send_json(500, {"error": "package_corrupt"})
        self.send_response(200)
        self.send_header("Content-Type", "application/zip")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Content-Disposition", f'attachment; filename="typing-pet-{code}-v{version}.zip"')
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def handle_one_request(self):
        try:
            return super().handle_one_request()
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            return
        except (ValueError, TypeError, KeyError, OverflowError, OSError, sqlite3.Error):
            self.send_json(400, {"error": "invalid_request"})


class LocalServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    slots = threading.BoundedSemaphore(16)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


if __name__ == "__main__":
    try:
        with LocalServer((HOST, PORT), API) as httpd:
            print(f"Typing Pet local share API: http://{HOST}:{PORT}", flush=True)
            print(f"SQLite state: {DB_PATH}", flush=True)
            httpd.serve_forever()
    except OSError as error:
        print(f"Could not start local share API on {HOST}:{PORT}: {error}", file=sys.stderr)
        raise SystemExit(1)
