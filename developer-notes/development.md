# Local development

Local builds use the development profile by default. You can keep the installed production app running.

| Setting | Development | Production |
|---|---|---|
| App name | TypingPet Dev | Typing Pet |
| Bundle | TypingPet Dev.app | TypingPet.app |
| Executable | TypingPetDev | TypingPet |
| Bundle identifier | ing.miel.typingpet.dev | ing.miel.typingpet |
| Settings domain | ing.miel.typingpet.dev.preferences | ing.miel.typingpet |
| Application Support folder | TypingPetDev | TypingPet |
| Menu bar | Flask icon and DEV | Paw icon |

Development separates Todos, image sets, key reaction images, preferences, and saved window positions.
It starts with its own data. It does not migrate or copy production data.
Input monitoring permissions belong to the separate development app.
The permission guide names `TypingPet Dev.app`.

## Build and run

From the source directory:

```sh
./scripts/run_dev.sh
```

This script builds a debug app at `dist-dev/TypingPet Dev.app`, signs it locally, and opens its Todo list.
Allow input monitoring for **TypingPet Dev** if you want to test global key reactions.
Development does not show a blocking permission prompt at startup.
Use the DEV menu > input monitoring settings when you want to enable global key reactions.
You can test the Todo UI first.
The installed production app does not need to stop.

### Input Monitoring onboarding

To open the new permission onboarding in a debug build, quit Dev and run:

```sh
open "dist-dev/TypingPet Dev.app" --args --show-input-guide
```

The welcome card receives keys only while its preview area has keyboard focus.
It animates the active pet images without requesting Input Monitoring or reading typed text.
Tab and Shift-Tab leave the preview so the setup button remains keyboard accessible.
Only selecting **다른 앱에서도 반응하도록 설정** requests system permission.
The guide follows System Settings, explains turning on the app's switch first, and expands
the existing draggable app icon under **목록에 없나요?**.

Permission approval and a connected event tap leave the guide waiting for a real global key event.
Only that event completes onboarding; the local preview cannot complete it.
If macOS requires reopening the app, follow its prompt. Connection help offers a retry and
explains how to quit and reopen. No Input Monitoring permission is granted by the app or its tests.
If macOS quits the app during setup, production resumes the verification step on relaunch.
Closing the guide with **나중에** or the close button cancels that automatic resume.

For visual checks without a system permission request, debug builds also accept
`--input-guide-preview preview`, `permission`, `verifying`, `connectionFailed`, or `complete`:

```sh
open "dist-dev/TypingPet Dev.app" --args --input-guide-preview permission
```

These screens use simulated permission/connection states and do not verify real global input.

Production shows the welcome once when monitoring is unavailable. **나중에** keeps the app
usable, and onboarding can be resumed from the menu's Input Monitoring item or Settings.
Dev continues to avoid automatic onboarding and system prompts at launch.

The menu bar has a `DEV` label. The settings title and Todo header also identify development mode.
Quit through `TypingPet Dev 종료`. Run the script again after source changes.
Native Swift/AppKit code needs a rebuild and restart; this script does not provide hot reload.
If Dev is already running, quit it before rebuilding so the executable and resources stay consistent.
A runtime file lock blocks a second Dev process from editing the same records.

You can also run the debug executable directly:

```sh
swift run TypingPet --show-todos
```

An unbundled runtime always uses development data and settings.
For macOS input permission tests, use the app bundle from `run_dev.sh`.

## Data

```text
~/Library/Application Support/TypingPetDev/todo-state.json
~/Library/Application Support/TypingPetDev/Images/
~/Library/Application Support/TypingPetDev/KeyReactions/
```

Settings > Todo shows the active record path.
Do not use the earlier test ZIP that shared the production bundle identifier.

## Explicit production builds

Only use this command when you intend to build the production identity:

```sh
TYPINGPET_BUILD_CHANNEL=production ./scripts/build_app.sh
```

The production build keeps the original names and storage locations.
An unknown or unbundled executable cannot select production mode.

## Updates

`./scripts/check_update.sh` checks the full update flow with two Dev builds and a local server.
See [automatic updates](updates.md).

## Interface localization

The five interface languages live under `Sources/TypingPet/Localization/`: `ko.lproj`, `en.lproj`, `ja.lproj`, `zh-Hans.lproj`, and `zh-Hant.lproj`, each with a `Localizable.strings` file. Call `L` with an English resource key; pass dynamic values as separate arguments using positional `%1$@` tokens. Keep matching keys and placeholders in all five files. User-created titles and image set names are never translated.

Settings > General > Language defaults to System. The first preferred system language selects Korean for `ko`, Japanese for `ja`, or Simplified/Traditional Chinese for `zh` according to script and region; other languages fall back to English. An explicit choice persists and updates the interface without restarting. [AppLanguageMode](../Sources/TypingPet/Localization.swift) defines this selection. The build script copies all language folders into the signed app. Settings uses a grouped sidebar and an 1100 × 820-point default window (minimum 900 × 700), with room for the keyboard and inline preset editor. Larger preferred body text scales these sizes. The saved appearance choice applies to Settings and both Todo panels.
