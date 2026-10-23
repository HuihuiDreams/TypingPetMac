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
See [automatic updates](UPDATE.md).
