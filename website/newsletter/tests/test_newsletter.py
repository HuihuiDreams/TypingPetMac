import asyncio
from concurrent.futures import ThreadPoolExecutor
import csv
import json
from pathlib import Path
import stat
import tempfile
import time
import unittest

from server import create_app
from store import CONSENT_VERSION, DAY, InvalidInput, Store, normalize_email, signup_fields


async def request(app, path, data=None, *, origin="https://typing-pet.miel.ing", method="POST", raw=None, ip="192.0.2.10", content_type="application/json", extra_headers=()):
    body = raw if raw is not None else json.dumps(data or {}).encode()
    headers = [(b"content-type", content_type.encode()), *extra_headers]
    if origin is not None:
        headers.append((b"origin", origin.encode()))
    scope = {"type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "scheme": "https",
             "method": method, "path": path, "raw_path": path.encode(), "query_string": b"",
             "root_path": "", "headers": headers, "client": (ip, 1234), "server": ("test", 443)}
    messages = []

    async def receive():
        return {"type": "http.request", "body": body, "more_body": False}

    async def send(message):
        messages.append(message)

    await app(scope, receive, send)
    start = next(m for m in messages if m["type"] == "http.response.start")
    output = b"".join(m.get("body", b"") for m in messages if m["type"] == "http.response.body")
    return start["status"], output, dict(start["headers"])


class NewsletterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = create_app(Path(self.temp.name) / "private")
        self.store = self.app.state.store
        self.data = {"email": "User+news@Example.com", "nickname": "", "locale": "ko",
                     "consent": True, "consent_version": CONSENT_VERSION}

    def call(self, path="subscribe", data=None, **kwargs):
        return asyncio.run(request(self.app, "/api/newsletter/" + path, self.data if data is None else data, **kwargs))

    def row(self, email="user+news@example.com"):
        with self.store.connection() as db:
            return db.execute("SELECT * FROM subscribers WHERE email_key=?", (self.store.digest(email),)).fetchone()

    def test_optional_nickname_persists_and_restart(self):
        for locale in ["ko", "en", "ja", "zh-Hans", "zh-Hant"]:
            self.assertEqual(self.call(data={**self.data, "email": locale + "@example.com", "locale": locale})[0], 202)
        self.assertEqual(self.call()[0], 202)
        self.assertEqual(self.row()["nickname"], "")
        self.assertEqual(self.row()["status"], "pending")
        self.assertEqual(Store(self.store.directory).counts(), {"pending": 6})
        for path, mode in [(self.store.directory, 0o700), (self.store.path, 0o600), (self.store.directory / "hash.key", 0o600)]:
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), mode)

    def test_name_language_and_consent_record(self):
        self.call(data={**self.data, "nickname": " 작은 고양이 🐈 ", "locale": "ja"})
        row = self.row()
        self.assertEqual(row["nickname"], "작은 고양이 🐈")
        self.assertEqual(row["locale"], "ja")
        self.assertEqual(row["consent_version"], CONSENT_VERSION)
        self.assertLess(abs(row["requested_at"] - time.time()), 5)

    def test_duplicates_do_not_modify_existing_subscriber(self):
        first = self.call(data={**self.data, "nickname": "Original"})
        self.store.approve("user+news@example.com")
        second = self.call(data={**self.data, "nickname": "Attacker", "locale": "en"})
        self.assertEqual(first[:2], second[:2])
        self.assertEqual(self.row()["nickname"], "Original")
        self.assertEqual(self.row()["locale"], "ko")
        self.assertEqual(self.row()["status"], "active")

    def test_rejects_bad_input_and_old_or_missing_consent(self):
        for change in [{"email": "a\r\nBcc: x@example.com"}, {"email": ".x@example.com"}, {"email": "a..b@example.com"},
                       {"email": "x@localhost"}, {"email": "x@-example.com"}, {"nickname": "x" * 81},
                       {"nickname": None}, {"nickname": "a\nb"}, {"locale": []}, {"locale": "fr"},
                       {"consent": False}, {"consent": "true"}, {"consent_version": "old"}]:
            with self.subTest(change=change):
                self.assertEqual(self.call(data={**self.data, **change})[0], 400)
        self.assertEqual(self.store.counts(), {})

    def test_honeypot_never_enters_database(self):
        self.assertEqual(self.call(data={**self.data, "website": "bot"})[0], 202)
        self.assertEqual(self.store.counts(), {})

    def test_origin_content_type_method_and_body_limits(self):
        self.assertEqual(self.call(origin="https://evil.example")[0], 403)
        self.assertEqual(self.call(origin=None)[0], 403)
        self.assertEqual(self.call(extra_headers=[(b"sec-fetch-site", b"cross-site")])[0], 403)
        self.assertEqual(self.call(content_type="text/plain")[0], 415)
        self.assertEqual(self.call(content_type="application/x-www-form-urlencoded")[0], 415)
        self.assertEqual(self.call(raw=b"{" )[0], 400)
        self.assertEqual(self.call(raw=b"[]")[0], 400)
        self.assertEqual(self.call(raw=b"x" * 4097)[0], 413)
        self.assertEqual(self.call(method="GET")[0], 405)
        self.assertEqual(self.call()[2][b"cache-control"], b"no-store")

    def test_rate_limit_shared_across_restart_and_forwarded_header_ignored(self):
        for i in range(20):
            self.assertEqual(self.call(extra_headers=[(b"x-real-ip", f"192.0.2.{i}".encode())])[0], 202)
        self.app = create_app(self.store.directory)
        status, _, headers = self.call()
        self.assertEqual(status, 429)
        self.assertIn(b"retry-after", headers)
        with self.store.connection() as db:
            self.assertNotIn("192.0.2.10", " ".join(str(tuple(row)) for row in db.execute("SELECT * FROM rate_limits")))

    def test_parallel_duplicate_requests_remain_one_row(self):
        with ThreadPoolExecutor(max_workers=8) as pool:
            futures = [pool.submit(self.store.subscribe, "same@example.com", "cat", "en", f"192.0.2.{i}") for i in range(12)]
            for future in futures:
                future.result()
        self.assertEqual(self.store.counts(), {"pending": 1})

    def test_unsubscribe_prevents_export_and_public_resubscribe(self):
        self.call()
        self.store.approve("user+news@example.com")
        first = self.call("unsubscribe")
        unknown = self.call("unsubscribe", {"email": "unknown@example.com"})
        self.assertEqual(first[:2], unknown[:2])
        self.assertEqual(self.row()["status"], "unsubscribed")
        self.assertEqual(self.row()["nickname"], "")
        self.call()
        self.assertEqual(self.row()["status"], "unsubscribed")
        with self.assertRaises(InvalidInput):
            self.store.approve("user+news@example.com")
        self.assertEqual(self.store.export(Path(self.temp.name) / "active.csv"), 0)

    def test_csv_requires_approval_and_handles_optional_and_formula_names(self):
        self.call(data={**self.data, "nickname": "=HYPERLINK(\"bad\")"})
        out = Path(self.temp.name) / "active.csv"
        self.assertEqual(self.store.export(out), 0)
        self.store.approve("user+news@example.com")
        out = Path(self.temp.name) / "approved.csv"
        self.assertEqual(self.store.export(out, locale="ko"), 1)
        with out.open(encoding="utf-8-sig", newline="") as file:
            rows = list(csv.reader(file))
        self.assertEqual(rows[1][0], "user+news@example.com")
        self.assertTrue(rows[1][1].startswith("'="))
        self.assertEqual(stat.S_IMODE(out.stat().st_mode), 0o600)
        with self.assertRaises(FileExistsError):
            self.store.export(out)

    def test_retention_purges_pending_and_unsubscribed_personal_data(self):
        now = int(time.time())
        self.store.subscribe("old@example.com", "cat", "ko", "ip", now=now - 8 * DAY)
        self.store.counts()
        self.assertIsNone(self.row("old@example.com"))
        self.store.subscribe("gone@example.com", "cat", "ko", "ip", now=now - 32 * DAY)
        self.store.unsubscribe("gone@example.com", "ip", now=now - 31 * DAY)
        # Insert a previously active member to exercise the independent opt-out retention.
        with self.store.connection() as db:
            db.execute("INSERT OR REPLACE INTO subscribers VALUES (?,?,?,'ko','unsubscribed',?,?,NULL,?)",
                       (self.store.digest("gone@example.com"), "gone@example.com", "cat", CONSENT_VERSION, now - 32 * DAY, now - 31 * DAY))
        self.store.counts()
        self.assertIsNone(self.row("gone@example.com")["email"])
        self.assertEqual(self.row("gone@example.com")["nickname"], "")
        with self.store.connection() as db:
            db.execute("UPDATE subscribers SET unsubscribed_at=?", (now - 181 * DAY,))
        self.store.counts()
        self.assertIsNone(self.row("gone@example.com"))

    def test_backup_is_consistent_private_and_does_not_overwrite(self):
        self.call()
        target = Path(self.temp.name) / "backup.sqlite3"
        self.store.backup(target)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
        import sqlite3
        with sqlite3.connect(target) as db:
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
            self.assertEqual(db.execute("SELECT count(*) FROM subscribers").fetchone()[0], 1)
        with self.assertRaises(FileExistsError):
            self.store.backup(target)

    def test_lost_hash_key_fails_closed(self):
        self.call()
        (self.store.directory / "hash.key").unlink()
        with self.assertRaisesRegex(RuntimeError, "original hash.key"):
            Store(self.store.directory)

    def test_service_lifespan_starts_and_stops_cleanup(self):
        async def check():
            async with self.app.router.lifespan_context(self.app):
                status, _, _ = await request(self.app, "/api/newsletter/health", method="GET")
                self.assertEqual(status, 200)
        asyncio.run(check())


if __name__ == "__main__":
    unittest.main()
