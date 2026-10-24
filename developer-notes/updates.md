# Automatic updates

The app checks a static JSON feed once a day and installs an update only after the user accepts it.

| | Development | Production |
|---|---|---|
| Feed | `UpdateFeedURL` default, unset by default | `https://pet.miel.ing/update/production/latest.json` |
| Feed scheme | HTTPS, or http on `localhost` / `127.0.0.1` | HTTPS only |
| Archive check | Size, SHA-256, Ed25519 | Size, SHA-256, Ed25519 |
| App check | Bundle ID, channel, build, valid signature | Same. Once the running app has a Team ID, also Developer ID with that Team ID and Gatekeeper notarization |

An ad-hoc production build has no Team ID, so it trusts the Ed25519 signature alone and can update to the first Developer ID build.
Each ad-hoc build has a different code signature, so macOS asks for Input Monitoring again after such an update.

The request carries no query and no identifiers. The server sees the default `URLSession` user agent and the IP address.

## Feed

```json
{
  "version": "0.13.0",
  "build": 19,
  "minimumSystemVersion": "13.0",
  "url": "https://pet.miel.ing/update/production/TypingPet-0.13.0-19-arm64.zip",
  "size": 7191671,
  "sha256": "…",
  "signature": "base64 Ed25519 signature of the zip bytes",
  "notes": "- Changes"
}
```

`build` is `CFBundleVersion`. Only a build greater than the running build is offered.
The zip contains one `.app`.

## Install flow

1. Download the zip into `~/Library/Caches/<bundle id>/Updates/`.
2. Check size, SHA-256, and the Ed25519 signature with the public key in Info.plist.
3. Extract with `ditto` and check the bundle ID, channel, build number, and code signature.
4. Ask to restart. If the user chooses later, the update installs when the app quits.
5. After the app quits, a helper moves the current bundle aside, moves the new bundle into place, and relaunches it. It restores the old bundle when the move fails.
6. The next launch reports the result and removes the update cache.

The app cannot update itself from App Translocation or from a folder the user cannot write.

## Keys

```sh
swift scripts/update_keys.swift generate production
```

Keys are stored in `~/.config/typingpet/update-keys/` (`TYPINGPET_UPDATE_KEY_DIR` overrides this).
`build_app.sh` writes `<channel>.pub` into Info.plist. A production build stops when the public key is missing.
Back up `production.key`. Released apps trust only its public key; losing it means users must reinstall by hand.
Never commit a `.key` file.

**Do not generate a replacement production key once a build has shipped.** Recover the original `production.key` and run
`swift scripts/update_keys.swift check production`. The check refuses a private key that does not match `production.pub`.
The private key is unrelated to the Apple Developer ID certificate and must not be uploaded or pasted into chat.

## Release

Use the [single-command release pipeline](releasing.md) after Developer ID setup:

```sh
# Update version.json and CHANGELOG.md, commit (and push for --github), then:
./scripts/release.sh --dry-run --github
./scripts/release.sh --github
```

For the individual steps, raise the version and build:

```sh
TYPINGPET_BUILD_CHANNEL=production TYPINGPET_VERSION=0.14.3 TYPINGPET_BUILD=23 ./scripts/build_app.sh
./scripts/notarize_release.sh
./scripts/deploy_update.sh production dist/TypingPet.app
```

`deploy_update.sh` requires the original update key, a notarized Developer ID app, and the local static server root
`~/TypingPetUpdate` (override with `TYPINGPET_UPDATE_ROOT` or the third argument). It creates the signed zip and manifest,
refuses a downgrade or a different archive for an already published build, copies the zip first, and atomically replaces
`latest.json` last. It then fetches both public URLs and compares them with the deployed files.
If public verification fails, inspect the server before retrying; the local feed may already have been updated.
Published builds are immutable. Increase `CFBundleVersion` for the next update.
Serve `latest.json` without caching.
The notes come from the matching `CHANGELOG.md` section, or from `UPDATE_NOTES`.

The production key was rotated for 0.14.2 after the old private key was lost. Builds through 0.14.1 embed the old public key,
so they cannot install 0.14.2 from the feed. Install 0.14.2 manually once; builds after that can use the new feed normally.

For a staged archive without deploying it, use `./scripts/publish_update.sh production dist/TypingPet.app`.

## Local check

Quit TypingPet Dev first, then run:

```sh
./scripts/check_update.sh
```

The publication pipeline has a separate non-GUI check: `./scripts/check_publish_update.sh`.

The script creates a development key when none exists, builds Dev 0.12.0 (18) and 0.13.0 (19), and serves the feed at `http://127.0.0.1:8787`.
It checks that a bad signature, a wrong hash, the same build, and a remote http archive are rejected.
It then installs and relaunches the new build, and checks the result.
It uses the Dev data folder and resets `UpdateFeedURL` afterward.

To try the UI by hand:

```sh
TYPINGPET_VERSION=0.13.0 TYPINGPET_BUILD=19 ./scripts/build_app.sh dist-dev/new
./scripts/publish_update.sh development "dist-dev/new/TypingPet Dev.app"
python3 -m http.server 8787 --bind 127.0.0.1 --directory dist-dev/update-server
defaults write ing.miel.typingpet.dev.preferences UpdateFeedURL http://localhost:8787/development/latest.json
./scripts/run_dev.sh
```

Then choose DEV menu > `업데이트 확인…`. Remove the override with `defaults delete ing.miel.typingpet.dev.preferences UpdateFeedURL`.
