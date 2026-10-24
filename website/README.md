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

To publish on this Mac after a public GitHub release:

```sh
./scripts/deploy_website.sh
```

Run that command from the repository root. It deploys a new timestamped directory, atomically switches
the website's `current` link, writes the nginx site configuration and download redirect, validates nginx, and gracefully reloads it.
Old directories, site configurations, and redirect backups remain in `~/server/typing-pet-site` for recovery.
The shared update feed lock prevents switching the download destination during another app deployment.
The publication command then verifies all ten live pages, Open Graph, assets, the redirect,
the full downloaded ZIP's SHA-256, and Range requests. Its report is saved under
`~/server/typing-pet-site/verification/verification.json`. These are requests from this Mac;
independent Internet probes must be recorded separately.

The fixed `https://pet.miel.ing/download/latest` URL returns `302` with `Cache-Control: no-store`
and explicit CDN no-store headers. Its destination is the feed's immutable version/build URL.
That ZIP retains `public, max-age=31536000, immutable`. Published ZIPs are never overwritten.

nginx site configuration: `nginx/typing-pet-site.conf`. The update vhost includes
`~/.config/nginx/snippets/typing-pet-latest.conf` inside its exact `/download/latest` location.
The landing hostname is a Cloudflare-proxied CNAME to `pet.miel.ing`, following its existing
DDNS-managed A record. Only `typing-pet.miel.ing` is proxied; `pet.miel.ing` remains DNS-only.
HTML uses `no-cache`; hashed JS/CSS/fonts use a one-year immutable policy and other site images
use a one-day policy. The download host keeps its explicit CDN no-store headers.

For each app release, add bilingual website notes along with the app's `CHANGELOG.md` entry.
After installation here, the app's `--github` / `--homebrew` release pipeline refreshes this website
after the matching GitHub release is public. If website publication fails, app artifacts remain published;
fix the notes or site and rerun `./scripts/deploy_website.sh` without rebuilding or republishing the app.

`deploy_update.sh` also refreshes the `latest` redirect after verifying each production archive,
including update-server-only releases. The landing page's recommended GitHub link advances after
the matching GitHub release is public. Generated release metadata stays ignored so publication
does not dirty the source snapshot or interfere with a prepared app release retry.

The social preview image is a 1200×630 browser rendering of `design/social-card.html`, using
the app's existing CC0 cat image. Optimized WebP assets derive from the repository's resources
and example screenshots. No third-party character assets are used.

Locale metadata is shared in `src/locales.json`. The root follows the first browser language,
recognizing Chinese scripts and regions, and remembers an explicit language choice. Language
switching preserves the current home/changelog page, query, and anchor. `npm run build` checks
language detection, translated content and release notes, canonical/alternate metadata, and all ten static pages.

The header appearance menu offers System (default), Light, and Dark in all five languages.
The preference stays in this browser's `typingpet-theme` localStorage entry across page/language
changes and synchronizes between tabs. System follows OS appearance changes. A blocking,
content-hashed head script applies the palette before paint; the mounted controller handles later
changes. If storage is unavailable, manual choices still work until the page is reloaded.
`npm test` covers preference resolution, OS/storage changes, and blocked storage; the build also
checks the pre-paint script and its fingerprint on every rendered page.

Website analytics use a pinned, locally bundled `posthog-js` SDK, loaded separately from the main UI.
They run only on the production hostname. The public project token is intentionally client-visible;
personal and project-secret API keys are not needed for collection.

| Event | Properties specific to the event |
| --- | --- |
| `$pageview` | locale, page, app_version |
| `download_clicked` | source (`github` / `direct`), placement (`hero` / `install`) |
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
