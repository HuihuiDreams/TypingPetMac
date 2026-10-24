"""Private SQLite storage. No Fastmail credentials or email sending live here."""
from contextlib import contextmanager
import csv
import hashlib
import hmac
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time
import unicodedata

LOCALES = {"ko", "en", "ja", "zh-Hans", "zh-Hant"}
CONSENT_VERSION = "2026-10-24-v1"
DAY = 86400


class InvalidInput(ValueError):
    pass


class RateLimited(Exception):
    pass


def normalize_email(value):
    if not isinstance(value, str) or len(value) > 254:
        raise InvalidInput("email")
    value = value.strip()
    if value.count("@") != 1:
        raise InvalidInput("email")
    local, domain = value.rsplit("@", 1)
    try:
        domain = domain.encode("idna").decode("ascii").lower()
    except UnicodeError:
        raise InvalidInput("email") from None
    if (not 1 <= len(local) <= 64 or local.startswith(".") or local.endswith(".")
            or ".." in local or not re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+", local)
            or len(domain) > 253 or "." not in domain
            or any(not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", part)
                   for part in domain.split("."))):
        raise InvalidInput("email")
    result = f"{local.lower()}@{domain}"
    if len(result) > 254:
        raise InvalidInput("email")
    return result


def signup_fields(data):
    email = normalize_email(data.get("email"))
    name = data.get("nickname", "")
    if not isinstance(name, str):
        raise InvalidInput("nickname")
    name = unicodedata.normalize("NFC", name).strip()
    if len(name) > 80 or any(unicodedata.category(c) in {"Cc", "Cs"} for c in name):
        raise InvalidInput("nickname")
    locale = data.get("locale")
    if not isinstance(locale, str) or locale not in LOCALES:
        raise InvalidInput("locale")
    if data.get("consent") is not True or data.get("consent_version") != CONSENT_VERSION:
        raise InvalidInput("consent")
    return email, name, locale


class Store:
    def __init__(self, directory):
        self.directory = Path(directory).expanduser().resolve()
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.directory, 0o700)
        self.path = self.directory / "subscribers.sqlite3"
        keyfile = self.directory / "hash.key"
        if self.path.exists() and not keyfile.exists():
            raise RuntimeError("Restore the original hash.key with the database; refusing to change subscriber identities")
        try:
            fd = os.open(keyfile, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            pass
        else:
            with os.fdopen(fd, "wb") as file:
                file.write(secrets.token_bytes(32))
        os.chmod(keyfile, 0o600)
        self.key = keyfile.read_bytes()
        if len(self.key) != 32:
            raise RuntimeError("Invalid newsletter hash key")
        # umask also covers SQLite journals and restricted CLI output files.
        os.umask(0o077)
        with self.connection() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS subscribers (
                    email_key TEXT PRIMARY KEY,
                    email TEXT,
                    nickname TEXT NOT NULL DEFAULT '',
                    locale TEXT NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('pending','active','unsubscribed')),
                    consent_version TEXT NOT NULL,
                    requested_at INTEGER NOT NULL,
                    reviewed_at INTEGER,
                    unsubscribed_at INTEGER
                );
                CREATE TABLE IF NOT EXISTS rate_limits (
                    bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS subscribers_status ON subscribers(status);
                PRAGMA user_version = 1;
            """)
        os.chmod(self.path, 0o600)

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def digest(self, value):
        return hmac.new(self.key, value.encode(), hashlib.sha256).hexdigest()

    def maintain(self, db, now):
        db.execute("DELETE FROM rate_limits WHERE expires_at <= ?", (now,))
        db.execute("DELETE FROM subscribers WHERE status='pending' AND requested_at < ?", (now - 7 * DAY,))
        db.execute("UPDATE subscribers SET email=NULL, nickname='' WHERE status='unsubscribed' AND unsubscribed_at < ?", (now - 30 * DAY,))
        db.execute("DELETE FROM subscribers WHERE status='unsubscribed' AND unsubscribed_at < ?", (now - 180 * DAY,))

    def limit(self, db, ip, action, now):
        # Only keyed, rotating digests are stored; neither raw IPs nor user agents.
        windows = [(f"{action}:ip:{ip}:{now // 3600}", 20, (now // 3600 + 1) * 3600),
                   (f"{action}:global:{now // 3600}", 500, (now // 3600 + 1) * 3600)]
        for value, maximum, expires in windows:
            key = self.digest(value)
            row = db.execute("SELECT count FROM rate_limits WHERE bucket=?", (key,)).fetchone()
            if row and row[0] >= maximum:
                raise RateLimited()
            db.execute("INSERT INTO rate_limits VALUES (?,1,?) ON CONFLICT(bucket) DO UPDATE SET count=count+1", (key, expires))

    def subscribe(self, email, nickname, locale, ip, now=None):
        now = int(time.time()) if now is None else now
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.maintain(db, now)
            self.limit(db, ip, "subscribe", now)
            # Repeated public submissions cannot rename, change language or resubscribe a member.
            db.execute("""INSERT INTO subscribers
                (email_key,email,nickname,locale,status,consent_version,requested_at)
                VALUES (?,?,?,?,'pending',?,?) ON CONFLICT(email_key) DO NOTHING""",
                (self.digest(email), email, nickname, locale, CONSENT_VERSION, now))

    def unsubscribe(self, email, ip, now=None):
        now = int(time.time()) if now is None else now
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.maintain(db, now)
            self.limit(db, ip, "unsubscribe", now)
            # The public opt-out intentionally needs only an email address, not a login.
            # Unknown addresses receive the same response, but are not stored.
            db.execute("""UPDATE subscribers SET status='unsubscribed',nickname='',
                unsubscribed_at=COALESCE(unsubscribed_at,?) WHERE email_key=?""",
                (now, self.digest(email)))

    def approve(self, email):
        with self.connection() as db:
            self.maintain(db, int(time.time()))
            changed = db.execute("""UPDATE subscribers SET status='active',reviewed_at=?
                WHERE email_key=? AND status='pending'""", (int(time.time()), self.digest(email))).rowcount
        if not changed:
            raise InvalidInput("No pending request; unsubscribed addresses cannot be approved")

    def counts(self):
        with self.connection() as db:
            self.maintain(db, int(time.time()))
            return {row[0]: row[1] for row in db.execute("SELECT status,count(*) FROM subscribers GROUP BY status")}

    def export(self, output, status="active", locale=None):
        if status not in {"active", "pending", "unsubscribed"} or (locale and locale not in LOCALES):
            raise InvalidInput("export filter")
        with self.connection() as db:
            self.maintain(db, int(time.time()))
            rows = db.execute("SELECT email,nickname,locale FROM subscribers WHERE status=? AND email IS NOT NULL AND (? IS NULL OR locale=?) ORDER BY email", (status, locale, locale)).fetchall()
        # Exclusive creation avoids clobbering earlier exports; refuse public permissions.
        fd = os.open(Path(output).expanduser(), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", newline="", encoding="utf-8-sig") as file:
            writer = csv.writer(file)
            writer.writerow(["Email Address", "Name", "Language"])
            for row in rows:
                # Preserve addresses for contact import. The strict dot-atom validator
                # rejects quotes, spaces, parentheses, colons and brackets in email.
                name = row["nickname"]
                if name.startswith(("=", "+", "-", "@", "\t", "\r")):
                    name = "'" + name
                writer.writerow([row["email"], name, row["locale"]])
        return len(rows)

    def backup(self, output):
        fd = os.open(Path(output).expanduser(), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(fd)
        with self.connection() as source:
            target = sqlite3.connect(output)
            try:
                source.backup(target)
            finally:
                target.close()
