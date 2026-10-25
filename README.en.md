# Typing Pet for macOS

[한국어](README.md) | [English](README.en.md)

A native macOS menu bar app that reacts to your keystrokes with pet images you choose.

<img src="Sources/TypingPet/Resources/pet-idle.png" alt="Default keyboard cat" width="180">

This unofficial macOS app was inspired by [swoonqx/TypingPet](https://github.com/swoonqx/TypingPet) for Windows. It is a new implementation and does not include the original project's source code or image assets.

## Install

**Requirements:** Apple Silicon Mac with macOS 13 or later. The current public build is the `v0.18.1` prerelease. It is signed with an Apple-issued Developer ID certificate and notarized by Apple, so you do not need to bypass Gatekeeper.

### Install with Homebrew

```sh
brew tap ynifamily3/tap
brew install --cask ynifamily3/tap/typing-pet
```

Open `TypingPet.app` from Applications after installation. Use `--adopt` only if an existing app is identical to the release being installed; otherwise keep the old app separately before installing.

The app supports automatic updates. To update through Homebrew, quit the app, run `brew update`, then `brew upgrade --cask --greedy ynifamily3/tap/typing-pet`.

### Install the DMG manually

1. Download the [v0.18.1 DMG](https://github.com/ynifamily3/TypingPetMac/releases/download/v0.18.1/TypingPetMac-v0.18.1-arm64-installer.dmg) and double-click to open it.
2. Drag `TypingPet` into the `Applications` folder beside it.
3. Eject the disk image and open the app from Applications.

The DMG is also Developer ID signed and notarized by Apple. The release includes a `.dmg.sha256` file for integrity checks.

### Install the ZIP manually

1. Open the [v0.18.1 release](https://github.com/ynifamily3/TypingPetMac/releases/tag/v0.18.1) and download `TypingPetMac-v0.18.1-arm64.zip`. For an optional integrity check, download the `.sha256` file from the same page.
2. Double-click the ZIP to extract it. Move `TypingPet.app` to **Applications** before launching; do not run it from Downloads.
3. Open `TypingPet.app` from Applications. A paw icon appears in the menu bar.

If you downloaded both files into Downloads, verify the ZIP with:

```sh
cd ~/Downloads
shasum -a 256 -c TypingPetMac-v0.18.1-arm64.zip.sha256
```

### First launch: Input Monitoring

The app needs macOS **Input Monitoring** permission to react while you use other apps. The welcome window lets you try pet reactions before requesting permission.

1. Click the preview area and press keys. This local preview needs no permission.
2. Select `다른 앱에서도 반응하도록 설정` (Set up reactions in other apps), then enable TypingPet in System Settings > Privacy & Security > Input Monitoring.
3. If it is missing, expand `목록에 없나요?` (Not in the list?) and drag the app icon into the list. Alternatively, use `+` to select the app in Applications.
4. Return to another app and type. The guide closes after receiving the first real global key event. If macOS asks you to quit and reopen, follow its prompt; verification resumes on relaunch.

Choose `나중에` (Later) to continue using the app and resume setup from the menu bar or Settings.

> [!IMPORTANT]
> When moving from an older ad-hoc-signed build, you may need to grant Input Monitoring permission once more. If the pet does not react, remove the old `TypingPet` entry with `-`, add the app again, and enable its switch. Future updates signed by the same Developer ID team can retain the permission.

**If you have v0.14.1 or earlier, install the latest release manually once.** The old update signing key was lost and replaced, so those builds cannot accept the new feed. Starting with v0.14.2, the app checks daily and installs an update after you approve it, on restart or quit. The [update documentation](developer-notes/updates.md) explains verification.

## In action

An example compact list with `고양이 밥주기` (Feed the cat) and `회계사 시험 공부` (Study for the CPA exam):

<img src="developer-notes/images/todo-compact@2x.png" alt="Compact list with Feed the cat and Study for the CPA exam" width="360">

Start the study timer while keeping both tasks in the compact list:

<img src="developer-notes/images/todo-active@2x.png" alt="Compact list with the study timer running" width="360">

The focus bubble shows the remaining time; hover over it for pause, resume, and stop controls:

<img src="developer-notes/images/todo-focus@2x.png" alt="Focus timer for Study for the CPA exam" width="360">

These screenshots use sample tasks in the isolated development app. The distributed app has the same layout.

## Features

- Choose multiple image presets for typing and resting, with random or sequential playback.
- Assign presets to specific keys or modifier combinations; exact matches take priority over the default typing reaction.
- Drag the pet when position lock is off. A quick release glides a little before settling.
- Hover to enlarge the pet, or grab it for a pressed-down spring effect. Set resting and hover opacity independently.
- Optionally let a click-through, position-locked pet move away from the pointer while staying on-screen.
- Hover controls hide or proportionally resize the pet. A gear immediately left of the resize handle opens Settings. Restore a hidden pet from the menu bar.
- Return to the resting selection after 0.75 seconds without input.
- Never store ordinary typed characters. Custom key rules store only the selected physical key code and modifier combination locally.

## Todos and focus timer

Move the pointer near the pet and select `할 일` (Todo). Enter a title and press Return. Each task has its own countdown or count-up setting; use the arrow to change it and the main button to start. The focus view supports pause, resume, stop, and countdown extension.

Tasks and measured focus time are stored on this Mac in `~/Library/Application Support/TypingPet/todo-state.json`. Open the file from Settings > Todos and Focus > `기록 데이터 열기` (Reveal Record Data). Sleep and app restarts do not add offline time to a focus session. See the [Todo guide](developer-notes/todos.md) for details.

## Settings and images

Open `설정` (Settings) from the paw icon in the menu bar.

- Set Management: select a sidebar set to see its image presets and keyboard mappings on one page. Use the plus button to create an empty named set, or duplicate an existing set.
- Add, replace, rename, and delete images in custom sets. Built-in image presets are fixed; duplicate the set to customize them.
- Click a key to open its preset popover. Combine multiple modifier checkboxes to configure key combinations.
- Edits save automatically. Editing another set keeps the current pet set active; switch explicitly with Use Set.
- Appearance and Behavior: size, opacity, bounce, always-on-top, position lock, and pointer avoidance.
- Todos and Focus: timer and record preferences.
- General: language, appearance, launch at login, Input Monitoring, and updates.

Create a set and add images, or import a folder from the menu bar. The menu bar also offers quick idle/reaction replacements and restoring defaults. Imported presets are copied to `~/Library/Application Support/TypingPet/Images/Sets`; legacy key-specific images remain in `~/Library/Application Support/TypingPet/KeyReactions`, so their originals may be moved afterward.

For a folder set, name the idle image `idle.*` or `pet-idle.*`; other supported images become reactions. If there is no idle-named image, the first image in sorted order is used. A one-image folder works for both idle and reaction states. PNG, APNG, JPG, JPEG, GIF, TIFF, HEIC, HEIF, and WebP are supported. Images of different proportions are fitted inside a canvas based on the idle image.

## Develop and build

After development and manual checks, the [release pipeline](developer-notes/releasing.md) runs tests, builds, signs, notarizes, and deploys a new version. Update and commit `version.json` and the changelog, push the release commit, then run `./scripts/release.sh --homebrew`. Use `--dry-run` for a read-only preflight.

Local development uses **TypingPet Dev**, with separate app identity, settings, images, and Todo records. The installed production app can remain open.

```sh
./scripts/run_dev.sh
```

This builds and opens the debug app. Quit Dev and rerun the script after code changes. See [development setup and data separation](developer-notes/development.md).

Build requirements are an Apple Silicon Mac, macOS 13 or later, and Swift 6 with Xcode Command Line Tools:

```sh
swift test
./scripts/build_app.sh
open "dist/TypingPet Dev.app"
```

The build script selects a Developer ID Application, Apple Development, or ad-hoc signing identity from Keychain, in that order. Set `CODE_SIGN_IDENTITY` to choose one explicitly. Public distribution also requires an Apple Developer Program membership, a Developer ID Application certificate, and notarization credentials; see the [Developer ID guide](developer-notes/developer-id.md).

### Preset packs and keyboard mapping

Use the native sidebar to manage sets, then assign multiple presets to each key and modifier combination. Typing and resting selections sit above the keyboard, each with random or sequential playback. Clicking a key or behavior opens one anchored popover that stays open while you choose presets. Edits save immediately, and changes to the active set apply to the pet. The centered keyboard preserves its proportions and scrolls horizontally in narrower windows.

See the [preset editor notes](developer-notes/preset-editor.md) for storage and compatibility details.

## Developer notes

[Developer Notes](developer-notes/README.md) collect implementation guides and design rationale. Guides describe existing behavior; design reviews cover unimplemented ideas whose availability, timing, and pricing remain undecided.

`docs/` is a local planning and drafting workspace excluded from Git. Material intended for publication is reviewed and edited into developer notes.

## Privacy

- Ordinary typed characters are not stored or sent over the network.
- Custom key reactions store only the physical key code and modifiers you select, locally.
- Network requests are limited to update checks and downloads. Requests to `pet.miel.ing` do not include user information, device identifiers, or input history; automatic checks can be disabled in Settings.
- The local Todo JSON contains titles, completion dates, timer preferences, and measured focus time. There is no Todo account, sync, or server upload.

## License

- Source code: [MIT](LICENSE)
- Built-in keyboard-cat assets: [CC0 1.0](ASSET_LICENSE.md)

The built-in cat is an AI-generated placeholder created for this repository. Images imported by users remain subject to their original creators' rights.
