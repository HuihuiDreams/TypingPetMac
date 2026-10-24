# Newsletter intake

The existing static site posts to a separate loopback API. Email is required; name/nickname
is optional. All five website languages are supported. No SMTP connection, confirmation email,
automatic campaign, Fastmail contact import or group creation happens in this implementation.
New requests can notify the operator's existing private Telegram chat. This is independent of
subscriber email delivery, and no additional notice or status is added to the signup screen.

## Storage choice

The live machine has PostgreSQL dedicated to Authentik and Immich and MySQL dedicated to Seafile,
without published database ports. The website has no database. Reusing those applications' databases
would couple a public newsletter form to unrelated services and their maintenance. A small, isolated
SQLite database is used instead: `~/server/typing-pet-newsletter/state/subscribers.sqlite3`.
The private state directory (0700), SQLite files and `hash.key` (0600) live outside static builds,
the repository and website release directories. Never publish or commit them.

## Local run and verification

```sh
cd /Users/miel/work/typing-pet-newsletter/website/newsletter
uv sync --frozen
uv run --frozen python -m unittest discover -s tests -v
NEWSLETTER_STATE_DIR=../.runtime/newsletter-dev \
NEWSLETTER_ORIGINS=http://127.0.0.1:4181 \
uv run --frozen uvicorn server:app_factory --factory --host 127.0.0.1 --port 17867 \
  --no-access-log --no-proxy-headers
```

In another terminal, run `npm run dev -- --port 4181 --strictPort` from `website/`.
Vite forwards `/api/newsletter/` to the loopback service. Use synthetic `example.com` addresses
only in this environment. For production HTML and all locale checks, run `npm run sync-release`
and `npm run build` in `website/`. Validate the prerendered output with `npm run preview -- --port 4181
--strictPort` after stopping the development server. The existing development entry hydrates an empty
Vite template, so it reports a hydration fallback; the built/prerendered pages are the authoritative
hydration check. Production build browser verification passed without hydration errors.

## What a submission means

- An explicit, unchecked-by-default pair of consent boxes is required. The API also validates
  the consent boolean and version. Requests include email, optional nickname, chosen language,
  timestamps, consent text version and a keyed email digest.
- New requests are **pending**, not verified subscribers. Pending requests expire after 7 days.
  There is no automated proof of email ownership. Before approval, the operator must separately
  check the address/consent, for example through a manually initiated confirmation and reply.
  Do not describe an operator approval as cryptographic or automatic verification.
- An exact duplicate gets the same public response and cannot edit an existing nickname/language.
  Email matching is case-insensitive, supports IDNA domains, and preserves dots and plus tags.
  Quoted addresses and SMTPUTF8 local parts are outside this intake's supported format.
- Public unsubscribe needs only the registered email and takes effect in this local DB immediately.
  No login is needed and no membership information is disclosed. **Someone who knows an address
  can opt it out.** This deliberate, limited opt-out behavior avoids sending verification emails;
  it cannot subscribe or reactivate an existing member. Stronger ownership checks would require
  a separate mail-confirmation or per-recipient signed-link flow.
- Unsubscribe clears the nickname immediately, keeps email for up to 30 days for manual group cleanup,
  then retains only the keyed suppression digest until day 180. The digest is still treated as personal
  data. Public submissions cannot override suppression. Deliberate resubscription needs a separate
  reviewed flow; the CLI will not reactivate an opted-out address.
- Cleanup runs hourly while the service is running, and on intake, health and CLI access.
  Expiry cleanup can lag by up to an hour; after downtime it runs again at startup.
  Stored raw IP addresses and user agents are not collected. Hourly IP/global rate counters use
  keyed, rotating digests and are removed when expired. Ordinary host/proxy security logs remain
  governed by the host's existing log policy; the newsletter nginx path disables access logging.
- Origins and JSON content type are checked; bodies are capped at 4 KiB. The hidden field and
  persistent rate limits reduce abuse but are not email ownership verification or a CAPTCHA.
- The form is excluded from automatic interaction/session capture by its privacy classes and
  attribute. No newsletter fields or form contents are passed to analytics. Retain these exclusions
  when merging the independent analytics work.

## Owner tools

Run `manage.py` on the server, with filesystem access to the private state. There are no HTTP
list, export or approval endpoints. The CLI never sends mail or changes Fastmail.

```sh
uv run --frozen python manage.py counts
uv run --frozen python manage.py notifications
uv run --frozen python manage.py retry-notification 1 --checked-not-delivered
uv run --frozen python manage.py approve --verified-manually
uv run --frozen python manage.py export --locale ko --output /private/path/active-ko.csv
uv run --frozen python manage.py export --status pending --output /private/path/review-requests.csv
uv run --frozen python manage.py export --status unsubscribed --output /private/path/remove-from-group.csv
uv run --frozen python manage.py backup --output /private/path/newsletter-backup.sqlite3
```

Approval prompts for the email without echoing it or putting it in shell history. Normal exports
contain **active** addresses only, with CSV columns `Email Address`, `Name`, `Language` and UTF-8 BOM.
Nickname is an empty cell when omitted. A leading apostrophe protects formula-like nicknames in
spreadsheets. Exports are 0600 and refuse to overwrite existing files. Treat CSV files as private
contact imports, not untrusted spreadsheet formulas; emails are preserved for correct delivery.
Remove review/export files when finished, following the same retention policy.

## Operator Telegram notification

For a newly inserted request, the same SQLite transaction queues one notification. An existing
email's repeated submission, rejected input and honeypot never create another notification.
An asynchronous worker sends it after commit; Telegram delays/errors do not turn a saved request
into a failed signup. Unsubscribed or expired requests are excluded before unsent alerts are claimed.
The payload is plain text (no HTML/Markdown interpretation), with link previews disabled:

```text
subscriber@example.com (미엘)가 뉴스레터를 신청했습니다.
subscriber@example.com가 뉴스레터를 신청했습니다.
```

The nickname and parentheses are omitted when not supplied. The endpoint must return `ok: true`
with a positive `message_id` and the configured chat ID before the queue is marked sent.
The message is an application notification, not proof of email ownership or subscription approval.

The production installer enables this worker with the machine's pre-existing configuration:

- `NEWSLETTER_TELEGRAM_ENABLED=1` (local runs remain disabled unless explicitly enabled).
- `NEWSLETTER_TELEGRAM_CONFIG_FILE` points to `~/dccon/data/telegram.json`. Only its `token_ref`
  and positive `user_id` owner chat are used. The separate sticker-channel target is never used.
- `NEWSLETTER_OP_SERVICE_TOKEN_FILE` points to `~/.config/1password/service-account-token`.
  Both files must be owned by this user and private (0600). `op read` retrieves the referenced
  bot token into memory via the existing service account. No bot token is copied into the source,
  LaunchAgent, SQLite, logs, or a new configuration file.
- The sender verifies the target is the configured **private** chat before sending. A future change
  to the existing owner config changes this target, so review that reference when reconfiguring it.

Credentials errors, known Telegram rejections and rate limits are retried with backoff. A network
timeout, malformed send response or interrupted in-flight send can mean Telegram already received
the message: these are **uncertain**, not automatically resent. Telegram sendMessage does not
provide a client idempotency key, so exactly-once delivery across network failures cannot be promised.
Use `manage.py notifications` to inspect safe metadata and receipt IDs. Retry an uncertain job only
after checking that the message did not arrive, using the explicit CLI flag shown above.

The outbox does not duplicate plaintext email/nickname; it joins the current subscriber record.
Finished/cancelled job metadata is removed after 30 days. The resulting message in Telegram is a
separate operator-held copy: SQLite expiry and unsubscribe do not delete Telegram messages.
Restrict this to the owner's private chat and manage Telegram message retention separately.
Schema v1 is upgraded additively to v2; existing subscriber data is preserved and historical rows
are not retroactively notified. Retain a private DB/key backup before deploying the new version.

The generic unsubscribe link for a manually written group message is:
`https://typing-pet.miel.ing/ko/?newsletter=unsubscribe#newsletter`
(replace `ko` with the recipient group's language).

**Before every manual Fastmail mailing, synchronize the group from the current active export and
remove opted-out addresses.** SQLite and an already imported Fastmail group are not automatically
synchronized. Do not merely append new CSV contacts to an old group. Compare the final recipients
and language to the current export before sending; if synchronization cannot be confirmed, do not
send. Fastmail's newsletter/bulk-use policy and author-only forwarding controls still need resolution
before using a group for real campaigns.

## Production integration

Implementation is isolated in branch `feature/newsletter`, based on `5642ed3`. The main checkout's
uncommitted analytics and app changes are intentionally not copied or overwritten. Merge the small
`App.tsx` import/render addition and nginx location/CSP changes with that work before publishing;
do not deploy this branch's older complete site configuration over newer production changes.

1. Review/merge the isolated source and run the API tests and website build.
2. Preview the service install with `uv run --frozen python install.py`. Add `--apply` only when
   installing the production service is intended. It creates a new LaunchAgent and timestamped code
   directory, binds only `127.0.0.1:17867`, refuses an occupied port/existing agent, and preserves state.
   It does not replace the website or nginx. Future upgrades require an explicit reviewed stop/switch;
   never run a second service against a different key or delete the existing state directory.
3. Merge the `/api/newsletter/` proxy from `../nginx/typing-pet-site.conf` into the active vhost.
   Keep the active analytics CSP/proxy additions. Set `NEWSLETTER_TRUST_PROXY=1` only behind this
   loopback proxy, which replaces X-Real-IP with nginx's trusted client address. Configure trusted
   Cloudflare real-IP handling in nginx if it is not already present; otherwise IP limits apply per
   Cloudflare edge address. Do not trust an arbitrary forwarded header from a public client.
4. Validate nginx with `nginx -t` before a graceful reload, then publish the merged static site using
   the existing deployment process. Verify public page, API, a synthetic pending row and opt-out.
   The browser response is only “request received”; it is not an email receipt or verified subscription.
5. Monitor `/api/newsletter/health` to detect service/database problems. Cleanup runs hourly.
   Backups contain personal data too: keep a short rolling window (at most 7 days), restrict access,
   and restore current suppression decisions before any export. A full restore requires both the
   SQLite backup and its original `hash.key`; missing keys fail closed at startup. Do not revive
   unsubscribed addresses from an older backup. A new confirmed request should be used after a
   deleted/expired request, rather than restoring stale private details.

Rollback: restore the previous static site/nginx config and validate/reload nginx, then boot out
only `gui/$(id -u)/com.miel.typing-pet-newsletter` if stopping the new service is intended. Preserve
`~/server/typing-pet-newsletter/state` and the private backups. App update assets and download
redirects are independent and must not be rolled back as part of newsletter work.
