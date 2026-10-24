#!/usr/bin/env python3
"""Owner-only CLI. No HTTP endpoint exposes subscriber data or approval."""
import argparse
import getpass
import json
import os
from pathlib import Path

from store import InvalidInput, Store, normalize_email


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", default=os.environ.get("NEWSLETTER_STATE_DIR", str(Path.home() / "server/typing-pet-newsletter/state")))
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("counts", help="Show counts only; also run retention cleanup")
    commands.add_parser("notifications", help="Show notification IDs, receipts and safe delivery status")
    retry = commands.add_parser("retry-notification", help="Retry only after checking Telegram did not receive this message")
    retry.add_argument("id", type=int)
    retry.add_argument("--checked-not-delivered", action="store_true", required=True)
    approve = commands.add_parser("approve", help="Approve a request after independently checking consent/address")
    approve.add_argument("--verified-manually", action="store_true", required=True)
    export = commands.add_parser("export", help="Write a private CSV; active subscribers only by default")
    export.add_argument("--output", required=True)
    export.add_argument("--status", default="active", choices=["active", "pending", "unsubscribed"])
    export.add_argument("--locale", choices=["ko", "en", "ja", "zh-Hans", "zh-Hant"])
    backup = commands.add_parser("backup", help="Create a consistent private SQLite backup")
    backup.add_argument("--output", required=True)
    args = parser.parse_args()
    store = Store(args.state_dir)
    try:
        if args.command == "notifications":
            print(json.dumps(store.notifications()))
        elif args.command == "retry-notification":
            store.retry_notification(args.id)
            print("Notification queued for reviewed retry.")
        elif args.command == "approve":
            email = normalize_email(getpass.getpass("Email to approve (hidden): "))
            store.approve(email)
            print("Request approved. No email sent; no Fastmail group changed.")
        elif args.command == "export":
            print(json.dumps({"exported": store.export(args.output, args.status, args.locale), "status": args.status}))
        elif args.command == "backup":
            store.backup(args.output)
            print("Private database backup created. Back up hash.key separately with the same access restrictions.")
        else:
            print(json.dumps(store.counts()))
    except (InvalidInput, FileExistsError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
