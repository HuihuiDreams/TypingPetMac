#!/usr/bin/env python3
"""Make a private, consistent snapshot. Run daily; retain seven snapshots."""
from pathlib import Path
from datetime import datetime, timezone
import fcntl
import os
import shutil
import sqlite3

root = Path(os.environ.get("TYPINGPET_SHARE_SERVICE_ROOT", "/Users/miel/server/typing-pet-share"))
data = root / "data"
backups = root / "backups"
os.umask(0o077)
backups.mkdir(parents=True, exist_ok=True)
stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
pending = backups / (".pending-" + stamp)
try:
    with (data / "mutation.lock").open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        pending.mkdir()
        with sqlite3.connect(data / "shares.sqlite3") as source, sqlite3.connect(pending / "shares.sqlite3") as target:
            source.backup(target)
        shutil.copy2(data / "lookup.key", pending / "lookup.key")
        if (data / "packages").exists(): shutil.copytree(data / "packages", pending / "packages")
    pending.rename(backups / stamp)
    for old in sorted(p for p in backups.iterdir() if p.is_dir() and not p.name.startswith("."))[:-7]:
        shutil.rmtree(old)
finally:
    if pending.exists(): shutil.rmtree(pending)
