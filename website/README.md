# Typing Pet landing page

Public Korean, English, Japanese, Simplified Chinese, and Traditional Chinese site at https://typing-pet.miel.ing, served by nginx on the Mac mini.
React + Base UI (Tabs, Accordion, Button), with a neo-brutalist design and local fonts.
PostHog Cloud (US) receives a small, explicit set of website events through the same-origin nginx proxy at `/relay/`.
The ten locale/page combinations are pre-rendered to HTML; React hydrates only their interactions.

```sh
cd website
npm ci --ignore-scripts
npm run sync-release
npm run build
npm run preview
```

`sync-release` reads the production feed and the matching public GitHub release. It checks version,
archive size and SHA-256, and requires notes in all five languages in `src/releases.json` before building.
Unpublished notes are omitted. The website journal starts at 0.16.0; historical repository changelogs remain intact.

When the matching release includes a DMG and its checksum, `sync-release` also checks the server's
full DMG against the GitHub asset digest and checksum file. The homepage then adds a DMG download
and a translated installation tab, alongside ZIP and Homebrew. Releases without a DMG retain ZIP
and Homebrew. The styled `-installer.dmg` asset takes priority over the earlier plain DMG when both exist.
DMG packaging is currently a separate step for v0.17.1; see the release guide.

To publish on this Mac after a public GitHub release:

```sh
./scripts/deploy_website.sh
```

Run that command from the repository root. It prepares a timestamped directory, writes the nginx site
and download configurations, validates nginx, and gracefully reloads it before atomically switching
the website's `current` link. A failure restores the previous configurations and link and reloads nginx.
Old directories and configuration backups remain in `~/server/typing-pet-site` for recovery.
The shared update feed lock prevents switching the download destination during another app deployment.
The publication command then verifies all ten live pages, Open Graph, assets, all four download
routes using GET and HEAD, the full ZIP and DMG hashes from both sources, Range and conditional
requests, and non-cacheable error responses. Its report is saved under
`~/server/typing-pet-site/verification/verification.json`. These are requests from this Mac;
independent Internet probes must be recorded separately.

All homepage download buttons use the following stable entry points:

| Source | DMG | ZIP |
| --- | --- | --- |
| GitHub | `https://pet.miel.ing/latest?from=github&type=dmg` | `https://pet.miel.ing/latest?from=github&type=zip` |
| Direct | `https://pet.miel.ing/latest?from=direct&type=dmg` | `https://pet.miel.ing/latest?from=direct&type=zip` |

`/latest` returns `302` with `Cache-Control: no-store` and explicit CDN no-store headers.
GitHub targets point straight to the pinned GitHub release asset; nginx does not proxy its bytes.
Direct targets point to the production server's version/build asset. Fixed ZIP and DMG responses
(200, 206 and 304) have `public, max-age=31536000, immutable` in browser and CDN cache headers.
Missing files and other errors use `no-store`; the app's `latest.json` keeps `no-cache` and CDN bypass.
GitHub controls the cache headers after its redirect. Never overwrite a published asset URL.

Omitting `from` defaults to GitHub. Omitting `type` selects DMG when available, otherwise ZIP.
Either query parameter order works. Unknown, duplicated, empty or invalid parameters return 400;
explicit DMG requests return 404 when that release has no DMG. Only GET and HEAD are accepted.
The original `/download/latest` remains a ZIP-only direct alias for compatibility.

nginx templates: `nginx/typing-pet-site.conf` and `nginx/typing-pet-downloads.conf` (installed as
`~/.config/nginx/conf.d/typing-pet.conf`). Publication generates the HTTP-context map
`~/.config/nginx/snippets/typing-pet-download-targets.conf` from the verified release metadata.
All source/format targets advance together without calling GitHub's API for each visitor.
The compatibility location includes `~/.config/nginx/snippets/typing-pet-latest.conf`.
The landing hostname is a Cloudflare-proxied CNAME to `pet.miel.ing`, following its existing
DDNS-managed A record. Only `typing-pet.miel.ing` is proxied; `pet.miel.ing` remains DNS-only.
HTML uses `no-cache`; hashed JS/CSS/fonts use a one-year immutable policy and other site images
use a one-day policy.

For each app release, add bilingual website notes along with the app's `CHANGELOG.md` entry.
After installation here, the app's `--github` / `--homebrew` release pipeline refreshes this website
after the matching GitHub release is public. If website publication fails, app artifacts remain published;
fix the notes or site and rerun `./scripts/deploy_website.sh` without rebuilding or republishing the app.

`deploy_update.sh` refreshes only the compatibility `/download/latest` redirect after verifying
each production archive, including update-server-only releases. The four normalized `/latest`
targets advance together with the website after the matching GitHub release is public and verified.
Generated release metadata stays ignored so publication
does not dirty the source snapshot or interfere with a prepared app release retry.

`npm run test:downloads` checks target validation, runs the actual download nginx template on an
isolated loopback port (when nginx is installed), and checks publication rollback after a reload
failure. It never changes live configuration or publishes artifacts.

The social preview image is a 1200×630 browser rendering of `design/social-card.html`, using
the app's existing CC0 cat image. Optimized WebP assets derive from the repository's resources
and example screenshots. No third-party character assets are used.

Locale metadata is shared in `src/locales.json`. The root follows the first browser language,
recognizing Chinese scripts and regions, and remembers an explicit language choice. Language
switching preserves the current home/changelog page, query, and anchor. `npm run build` checks
language detection, translated content and release notes, canonical/alternate metadata, and all ten static pages.

The header appearance menu offers System (default), Light, and Dark in all five languages.
Language navigation uses Base UI `Menu.LinkItem`; appearance uses `Menu.RadioGroup`.
Both use portaled, collision-aware popups with keyboard navigation, dismissal and focus restoration.
The preference stays in this browser's `typingpet-theme` localStorage entry across page/language
changes and synchronizes between tabs. System follows OS appearance changes. A blocking,
content-hashed head script applies the palette before paint; the mounted controller handles later
changes. If storage is unavailable, manual choices still work until the page is reloaded.
`npm test` covers preference resolution, OS/storage changes, and blocked storage; the build also
checks the pre-paint script and its fingerprint on every rendered page.
The newsletter uses Base UI Form/Field/Input, a labelled Select and required Checkbox controls;
disclosures use Collapsible, and analytics preferences use a stable-label Switch.
See the [component audit and keyboard verification](../developer-notes/website-accessibility.md).

Website analytics use a pinned, locally bundled `posthog-js` SDK, loaded separately from the main UI.
They run only on the production hostname. The public project token is intentionally client-visible;
personal and project-secret API keys are not needed for collection.

| Event | Properties specific to the event |
| --- | --- |
| `$pageview` | locale, page, app_version |
| `download_clicked` | source (`github` / `direct`), placement (`hero` / `install`), format (`zip` / `dmg`) |
| `homebrew_copied` | command (`install` / `update`), sent only after a successful copy |
| `language_changed` | to_locale, sent only when choosing a different language |

All events include locale, page, and app_version. Downloads measure clicks, not completed installations.
Autocapture, pageleave, recording, surveys, feature flags, and remote script loading are disabled.
The event/property allowlist strips input/DOM data, person updates, URL queries and fragments, and referrer paths.
The SDK uses a browser-local anonymous identifier in localStorage, without analytics cookies or person profiles.
Visitors can disable collection in the footer; browser Do Not Track and Global Privacy Control also disable it.
The Mac app and its update/download hosts do not gain an analytics SDK.

The proxy only accepts event POSTs at `/relay/e[/]` (the browser SDK) or `/relay/i/v0/e[/]` (the capture API), and read-only SDK asset/config requests.
Cookies and Authorization headers are removed before forwarding, and upstream HTTPS certificates are verified.
Other POSTs, apart from the newsletter endpoints below, remain rejected. The proxy does not guarantee passage through every ad blocker.
Build-time analytics policy checks require a Node release with native TypeScript support (the publisher uses Node 26).

## Newsletter requests

The home and changelog pages include a newsletter form in all five languages. Email and explicit
consent are required; name/nickname is optional. A separate loopback service stores requests in
private SQLite outside the static website. It provides opt-out and owner-only review/CSV export,
and does not send emails or modify Fastmail groups. Requests remain pending until manually reviewed.
See [the newsletter service guide](newsletter/README.md) for tests, data retention, local development,
production integration, backups and the manual Fastmail group synchronization requirements.
