#!/usr/bin/env python3
"""Preview or install the dedicated loopback service; never modifies nginx or the site."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import sys

LABEL = "com.miel.typing-pet-newsletter"
SOURCE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Install and start the new LaunchAgent")
    args = parser.parse_args()
    root = Path.home() / "server/typing-pet-newsletter"
    agent = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
    print(json.dumps({"apply": args.apply, "listen": "127.0.0.1:17867", "state": str(root / "state"),
                      "launch_agent": str(agent), "nginx_changes": False, "mail_sending": False,
                      "telegram_notifications": True, "telegram_target": "existing owner private chat"}, indent=2))
    if not args.apply:
        return
    if sys.platform != "darwin":
        parser.error("LaunchAgent installation requires macOS")
    uv = shutil.which("uv")
    if not uv:
        parser.error("Install uv before installing this service")
    if agent.exists() or subprocess.run(["launchctl", "print", f"gui/{os.getuid()}/{LABEL}"], capture_output=True).returncode == 0:
        parser.error("A service already exists. Keep its state and perform an explicit reviewed upgrade instead.")
    with socket.socket() as probe:
        try:
            probe.bind(("127.0.0.1", 17867))
        except OSError:
            parser.error("Port 17867 is already in use")
    os.umask(0o077)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    release = root / "releases" / stamp
    release.mkdir(parents=True, mode=0o700)
    for name in ["server.py", "store.py", "telegram_notify.py", "manage.py", "pyproject.toml", "uv.lock", ".python-version"]:
        shutil.copyfile(SOURCE / name, release / name)
    subprocess.run([uv, "sync", "--frozen", "--project", str(release)], check=True)
    logs = root / "logs"
    logs.mkdir(mode=0o700, exist_ok=True)
    for name in ["stdout.log", "stderr.log"]:
        (logs / name).touch(mode=0o600, exist_ok=True)
    payload = {
        "Label": LABEL,
        "ProgramArguments": [uv, "run", "--frozen", "uvicorn", "server:app_factory", "--factory",
                             "--host", "127.0.0.1", "--port", "17867", "--no-access-log", "--no-proxy-headers"],
        "WorkingDirectory": str(release),
        "EnvironmentVariables": {"NEWSLETTER_STATE_DIR": str(root / "state"),
                                 "NEWSLETTER_ORIGINS": "https://typing-pet.miel.ing", "NEWSLETTER_TRUST_PROXY": "1",
                                 "NEWSLETTER_TELEGRAM_ENABLED": "1",
                                 "NEWSLETTER_TELEGRAM_CONFIG_FILE": str(Path.home() / "dccon/data/telegram.json"),
                                 "NEWSLETTER_OP_SERVICE_TOKEN_FILE": str(Path.home() / ".config/1password/service-account-token"),
                                 "PYTHONUNBUFFERED": "1"},
        "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 10,
        "StandardOutPath": str(logs / "stdout.log"), "StandardErrorPath": str(logs / "stderr.log"),
    }
    agent.parent.mkdir(parents=True, exist_ok=True)
    with agent.open("xb") as file:
        plistlib.dump(payload, file)
    subprocess.run(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(agent)], check=True)
    print(f"Service installed from {release}. Keep state/hash.key together with SQLite backups.")


if __name__ == "__main__":
    main()
