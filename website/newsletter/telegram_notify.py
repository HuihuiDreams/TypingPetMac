"""Owner's Telegram alerts, with credentials read only into process memory."""
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import urllib.error
import urllib.request


class NotificationFailure(Exception):
    def __init__(self, category, retry_after=None):
        super().__init__(category)
        self.category = category
        self.retry_after = retry_after


def notification_text(email, nickname):
    name = f" ({nickname})" if nickname else ""
    return f"{email}{name}가 뉴스레터를 신청했습니다."


def private_file(path):
    path = Path(path).expanduser()
    mode = path.stat()
    if mode.st_uid != os.getuid() or stat.S_IMODE(mode.st_mode) & 0o077 or not stat.S_ISREG(mode.st_mode):
        raise ValueError("private file required")
    return path


class TelegramSender:
    def __init__(self, config_file=None, service_token_file=None):
        self.config_file = config_file or os.environ.get("NEWSLETTER_TELEGRAM_CONFIG_FILE", str(Path.home() / "dccon/data/telegram.json"))
        self.service_token_file = service_token_file or os.environ.get("NEWSLETTER_OP_SERVICE_TOKEN_FILE", str(Path.home() / ".config/1password/service-account-token"))

    def credentials(self):
        try:
            config = json.loads(private_file(self.config_file).read_text())
            reference, chat = config["token_ref"], config["user_id"]
            # The pre-existing config's owner private chat, never its sticker notification channel.
            if type(chat) is not int or chat <= 0 or not re.fullmatch(r"op://[^/\s]+/[^/\s]+/[^/\s]+", reference):
                raise ValueError()
            environment = os.environ.copy()
            environment["OP_SERVICE_ACCOUNT_TOKEN"] = private_file(self.service_token_file).read_text().strip()
            result = subprocess.run(["/opt/homebrew/bin/op", "read", reference], env=environment,
                                    capture_output=True, text=True, timeout=30)
            token = result.stdout.strip()
            if result.returncode or not re.fullmatch(r"\d+:[A-Za-z0-9_-]+", token):
                raise ValueError()
            return token, chat
        except Exception:
            # op errors or subprocess results can contain credentials: never propagate them.
            raise NotificationFailure("credentials", 300) from None

    def call(self, token, method, payload, *, before_send=False):
        request = urllib.request.Request(f"https://api.telegram.org/bot{token}/{method}",
            data=json.dumps(payload, ensure_ascii=False).encode(), headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                body = json.load(response)
        except urllib.error.HTTPError as error:
            try:
                body = json.loads(error.read(16384))
            except Exception:
                body = {}
            if error.code == 429 and body.get("ok") is False:
                delay = body.get("parameters", {}).get("retry_after", 60)
                raise NotificationFailure("rate_limited", max(1, min(int(delay), 86400))) from None
            if body.get("ok") is False and 400 <= error.code < 500:
                raise NotificationFailure("preflight" if before_send else "rejected", 300) from None
            raise NotificationFailure("preflight" if before_send else "ambiguous", 120 if before_send else None) from None
        except Exception:
            # A timeout after sendMessage may mean Telegram already delivered it.
            raise NotificationFailure("preflight" if before_send else "ambiguous", 120 if before_send else None) from None
        if not isinstance(body, dict) or body.get("ok") is not True:
            raise NotificationFailure("preflight" if before_send else "ambiguous", 120 if before_send else None)
        return body.get("result")

    def send(self, email, nickname):
        token, chat_id = self.credentials()
        chat = self.call(token, "getChat", {"chat_id": chat_id}, before_send=True)
        if not isinstance(chat, dict) or chat.get("id") != chat_id or chat.get("type") != "private":
            raise NotificationFailure("preflight", 300)
        result = self.call(token, "sendMessage", {"chat_id": chat_id, "text": notification_text(email, nickname),
            "link_preview_options": {"is_disabled": True}})
        if (not isinstance(result, dict) or type(result.get("message_id")) is not int
                or result["message_id"] <= 0 or result.get("chat", {}).get("id") != chat_id):
            raise NotificationFailure("ambiguous")
        return result["message_id"]


def deliver_one(store, sender):
    job = store.claim_notification()
    if job is None:
        return False
    try:
        message_id = sender.send(job["email"], job["nickname"])
    except NotificationFailure as error:
        delay = error.retry_after
        if delay is not None:
            delay = max(delay, min(3600, 30 * 2 ** min(job["attempts"], 7)))
        store.finish_notification(job["id"], error=error.category, retry_after=delay)
    except Exception:
        store.finish_notification(job["id"], error="ambiguous")
    else:
        store.finish_notification(job["id"], message_id=message_id)
    return True
