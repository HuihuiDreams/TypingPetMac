import asyncio
import io
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
import urllib.error

from server import create_app
from store import CONSENT_VERSION, Store
from telegram_notify import NotificationFailure, TelegramSender, deliver_one, notification_text
from test_newsletter import request


class RecordingSender:
    def __init__(self, failure=None):
        self.messages = []
        self.failure = failure

    def send(self, email, nickname):
        self.messages.append((email, nickname))
        if self.failure:
            raise self.failure
        return 456


class NotificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.store = Store(Path(self.temp.name) / "state")
        self.email = "subscriber@example.com"

    def subscribe(self, nickname="작은 고양이", now=None):
        return self.store.subscribe(self.email, nickname, "ko", "192.0.2.1", now=now)

    def test_message_with_optional_nickname_and_literal_markup(self):
        self.assertEqual(notification_text(self.email, "미엘"), "subscriber@example.com (미엘)가 뉴스레터를 신청했습니다.")
        self.assertEqual(notification_text(self.email, ""), "subscriber@example.com가 뉴스레터를 신청했습니다.")
        self.assertIn("<b>cat</b>", notification_text(self.email, "<b>cat</b>"))

    def test_only_new_registration_enqueues_and_accepted_receipt_prevents_replay(self):
        self.assertTrue(self.subscribe())
        self.assertFalse(self.subscribe("different"))
        sender = RecordingSender()
        self.assertTrue(deliver_one(self.store, sender))
        self.assertFalse(deliver_one(self.store, sender))
        self.assertEqual(sender.messages, [(self.email, "작은 고양이")])
        self.assertEqual(self.store.notifications()[0]["message_id"], 456)
        self.assertEqual(self.store.notifications()[0]["state"], "sent")
        self.assertFalse(deliver_one(Store(self.store.directory), sender))

    def test_storage_and_queue_are_atomic(self):
        with self.store.connection() as db:
            db.execute("CREATE TRIGGER simulate_queue_failure BEFORE INSERT ON notification_outbox BEGIN SELECT RAISE(ABORT,'failure'); END")
        with self.assertRaises(Exception):
            self.subscribe()
        self.assertEqual(self.store.counts(), {})

    def test_known_rejection_retries_without_losing_signup(self):
        self.subscribe()
        sender = RecordingSender(NotificationFailure("rate_limited", 90))
        deliver_one(self.store, sender)
        self.assertEqual(self.store.counts(), {"pending": 1})
        self.assertEqual(self.store.notifications()[0]["state"], "pending")
        self.assertFalse(deliver_one(self.store, sender))
        with self.store.connection() as db:
            db.execute("UPDATE notification_outbox SET next_attempt_at=0")
        sender.failure = None
        deliver_one(self.store, sender)
        self.assertEqual(self.store.notifications()[0]["state"], "sent")

    def test_ambiguous_delivery_and_expired_worker_do_not_automatically_resend(self):
        self.subscribe()
        sender = RecordingSender(NotificationFailure("ambiguous"))
        deliver_one(self.store, sender)
        self.assertFalse(deliver_one(self.store, sender))
        self.assertEqual(self.store.notifications()[0]["state"], "uncertain")
        self.store.retry_notification(self.store.notifications()[0]["id"])
        self.assertIsNotNone(self.store.claim_notification(now=int(time.time())))
        self.assertIsNone(self.store.claim_notification(now=int(time.time()) + 121))
        self.assertEqual(self.store.notifications()[0]["last_error"], "interrupted")

    def test_unsubscribe_cancels_unsent_notification(self):
        self.subscribe()
        self.store.unsubscribe(self.email, "192.0.2.1")
        sender = RecordingSender()
        self.assertFalse(deliver_one(self.store, sender))
        self.assertEqual(sender.messages, [])
        self.assertEqual(self.store.notifications()[0]["state"], "cancelled")

    def test_existing_v1_data_is_preserved_without_historical_notifications(self):
        self.subscribe()
        with self.store.connection() as db:
            db.execute("DROP TABLE notification_outbox")
            db.execute("PRAGMA user_version=1")
        restored = Store(self.store.directory)
        self.assertEqual(restored.counts(), {"pending": 1})
        self.assertEqual(restored.notifications(), [])

    def test_no_personal_fields_in_notification_status(self):
        self.subscribe()
        text = json.dumps(self.store.notifications())
        self.assertNotIn(self.email, text)
        self.assertNotIn("nickname", text)
        self.assertNotIn("email_key", text)

    def test_background_failure_does_not_change_http_success(self):
        sender = RecordingSender(NotificationFailure("credentials", 300))
        app = create_app(self.store.directory, telegram=sender)

        async def run():
            async with app.router.lifespan_context(app):
                result = await request(app, "/api/newsletter/subscribe", {
                    "email": self.email, "nickname": "", "locale": "ko", "consent": True,
                    "consent_version": CONSENT_VERSION})
                self.assertEqual(result[0], 202)
                for _ in range(100):
                    if sender.messages:
                        break
                    await asyncio.sleep(.01)
        asyncio.run(run())
        self.assertEqual(self.store.counts(), {"pending": 1})
        self.assertEqual(len(sender.messages), 1)


class TelegramApiTests(unittest.TestCase):
    def setUp(self):
        self.sender = TelegramSender()

    def test_telegram_sender_verifies_private_target_and_uses_plain_text(self):
        calls = []

        def api(token, method, payload, **kwargs):
            calls.append((method, payload))
            return {"id": 123, "type": "private"} if method == "getChat" else {"message_id": 99, "chat": {"id": 123}}
        with patch.object(self.sender, "credentials", return_value=("test", 123)), patch.object(self.sender, "call", side_effect=api):
            self.assertEqual(self.sender.send("test@example.com", "<b>name</b>"), 99)
        self.assertNotIn("parse_mode", calls[1][1])
        self.assertTrue(calls[1][1]["link_preview_options"]["is_disabled"])
        self.assertEqual(calls[1][1]["chat_id"], 123)

    def test_non_private_target_does_not_send(self):
        with patch.object(self.sender, "credentials", return_value=("test", 123)), patch.object(self.sender, "call", return_value={"id":123,"type":"group"}) as api:
            with self.assertRaises(NotificationFailure):
                self.sender.send("test@example.com", "")
            self.assertEqual(api.call_count, 1)

    def test_missing_credentials_fail_safely_without_secret_in_exception(self):
        sender = TelegramSender(config_file="/nonexistent/private-config.json")
        with self.assertRaises(NotificationFailure) as raised:
            sender.credentials()
        self.assertEqual(str(raised.exception), "credentials")
        self.assertEqual(raised.exception.retry_after, 300)

    def test_timeout_is_ambiguous_but_preflight_can_retry(self):
        with patch("urllib.request.urlopen", side_effect=TimeoutError("token-must-not-be-logged")):
            for preflight in [False, True]:
                with self.assertRaises(NotificationFailure) as raised:
                    self.sender.call("123:secret", "getChat" if preflight else "sendMessage", {}, before_send=preflight)
                self.assertNotIn("secret", str(raised.exception))
                self.assertEqual(raised.exception.retry_after, 120 if preflight else None)

    def test_http_rate_limit_has_safe_retry_after(self):
        error = urllib.error.HTTPError("https://example.invalid", 429, "rate limited", {}, io.BytesIO(json.dumps({"ok":False,"parameters":{"retry_after":42}}).encode()))
        with patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(NotificationFailure) as raised:
                self.sender.call("123:secret", "sendMessage", {})
        self.assertEqual(raised.exception.category, "rate_limited")
        self.assertEqual(raised.exception.retry_after, 42)


if __name__ == "__main__":
    unittest.main()
