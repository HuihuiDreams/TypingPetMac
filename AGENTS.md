# AGENTS.md — TypingPetMac (桌面打字陪伴宠物)

A lightweight native macOS (macOS 13+) desktop typing pet written in Swift (AppKit + SPM). Borderless floating transparent overlay, global low-level keystroke reaction via `CGEventTap`, physics & pointer evasion, 100% offline & zero network privacy.

## Core Principles

0. **Verify Workspace Anchor first** — Always confirm commands run from this repository's root (`.` — the directory containing this `AGENTS.md`, `/Users/huihui/Documents/TypingPetMac`). Do NOT confuse with adjacent projects (e.g. `desktop-pet`, `qijiugame-juzuihulu`).
1. **Think first** — Surface assumptions and trade-offs before coding (Karpathy Guidelines). When AppKit floating window behaviors, CoreAnimation layer performance, `CGEventTap` session callbacks, or macOS permission flows are unclear, stop and state assumptions explicitly. Prefer simpler native paths over complex abstractions.
2. **Use skills first** — Before performing tasks like UI engineering, writing documentation, or debugging, proactively review the available agent skills and load the relevant skill first.
3. **Keep changes simple** — Write the minimum code needed. Zero external third-party dependencies: stick strictly to native Apple frameworks (`AppKit`, `Foundation`, `CoreGraphics`, `QuartzCore`, `ServiceManagement`). Avoid premature abstractions.
4. **Make surgical edits** — Modify only the lines needed. Match existing Swift idioms and architectural boundaries (ADR-001). Remove orphaned code created by your edits, and do not touch unrelated code.
5. **Verify intentionally** — Define verification steps before coding. Run unit tests (`swift test`), verify release packaging (`./scripts/build_app.sh`), and inspect window geometry, energy guards, and permissions flow.

## Must-Know After Editing

1. **Centralized Preferences (`PetPreferences.swift`)** — All `UserDefaults` keys and fallback values must go through `AppPreferencesKey` and `AppPreferencesDefault`. **Never introduce raw string literals** (e.g., `"alwaysOnTop"`, `"petScale"`, `"imageGalleryData-v1"`) into controllers, views, or stores. Guarded by `PetPreferencesContractTests`.
2. **Energy & CoreAnimation Transaction Guard** — In `PetController.swift`, opacity updates in `updatePetOpacity()` must preserve the diff threshold guard:
   ```swift
   guard abs(CGFloat(imageLayer.opacity) - targetOpacity) > 0.001 else { return }
   ```
   This blocks redundant high-frequency `CATransaction` commits on every mouse pixel movement, preventing CPU/GPU wakeups and battery drain.
3. **Disk Hygiene & Physical Cleanup** — Deleting or updating custom sets (`PetImageLibrary.deleteSet`) or key reactions (`KeyReactions.removeRule` / `setRule` override) must synchronously clean up the actual files/directories under `Application Support/TypingPet/` (e.g., `Sets/<id>/` and `KeyReactions/<file>`). Guarded by `DiskCleanupTests`. Never touch user source directories.
4. **Release Privacy & Path Hygiene** — **Never leak local machine paths into release binaries**. `#filePath` is strictly restricted to `#if DEBUG` (as a local development fallback in tests and debug runs). Never add network requests, telemetry, or analytics — maintain the zero-network offline privacy guarantee.
5. **Single Responsibility & Size Budget (ADR-001)** —
   - `Sources/TypingPet/main.swift` must stay an ultra-lean `@MainActor` bootstrap entry point (under 20 lines).
   - Decomposed components (`PetViews.swift`, `PetController.swift`, `GlobalKeyMonitor.swift`, `AppDelegate.swift`) should each remain focused, single-responsibility, and under 650 lines. Keep internal members `private` and top-level types `internal`.
6. **Input Monitoring & Permissions (`CGEventTap`)** — Global keystroke tracking relies on `CGEventTap` (`.listenOnly`), requiring macOS "Input Monitoring" (`ListenEvent`) access. Never write tests that require live hardware key events in CI/headless environments (test event models, state stores, and geometry math instead). For local manual permission testing, reset authorization using `tccutil reset ListenEvent`.
7. **Version & Bundle Synchronization** — When releasing a new version, update `version` and `build` in `version.json` (consumed by `scripts/build_app.sh` and `scripts/release.py`), promote `## [Unreleased]` in `CHANGELOG.md` to the new version section, and execute `./scripts/build_app.sh` to package `dist/TypingPet.app`.
8. **Mandatory Post-Edit Synchronization (`CHANGELOG.md`, Tests, & Global Docs)** — After **any** code, script, or documentation change:
   - **Always update `CHANGELOG.md`**: Record the change under `## [Unreleased]` (using `Added`, `Changed`, `Fixed`, `Security`). Never modify already-tagged release sections unless fixing a historical typo.
   - **Always check & update tests + standalone CI scripts**: When modifying code or adding/renaming files or symbols, inspect `Tests/TypingPetTests/*` to add or update unit tests, and verify standalone compilation/check scripts in `scripts/` (specifically `./scripts/check_todo.sh`, `python3 -m unittest discover -s scripts -p 'test_release.py'`, and `./scripts/check_publish_update.sh`) so file lists and assertions stay in sync.
   - **Always check global documentation**: Evaluate whether the change affects architectural components, trust boundaries, domain terms, or user workflows, and synchronously update `docs/architecture.md`, `docs/TypingPetMac-threat-model.md`, `GLOSSARY.md`, `docs/decisions/ADR-*.md`, or `README.md`.

## Commands

| Command | Purpose |
| --- | --- |
| `swift build` | Compile debug executable (`.build/debug/TypingPet`) |
| `swift test` | Run all Swift Testing test suites |
| `swift test --filter <Name>` | Run a focused test suite (e.g. `swift test --filter PetPreferencesContractTests`) |
| `./scripts/build_app.sh [dist_dir]` | Compile release, bundle resources, generate Info.plist, and code-sign into `dist/TypingPet.app` |
| `./scripts/notarize_release.sh [app] [zip]` | Package zip, submit to Apple Notary Service (`xcrun notarytool`), staple ticket, and verify |
| `xattr -cr /Applications/TypingPet.app` | Clear Gatekeeper quarantine flag for unsigned/ad-hoc local testing |
| `tccutil reset ListenEvent` | Reset macOS Input Monitoring permission status to test onboarding flow |

### Single test suite / test case

```bash
swift test --filter PetPreferencesContractTests
swift test --filter DiskCleanupTests
swift test --filter PetWindowGeometryTests
```

### SDKROOT & Sandboxed Builds Note

If the active CommandLineTools SDK version mismatches the compiler version, explicitly supply the matching SDK:

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build
```

When building in restricted container or agent sandbox environments where nested sandbox execution fails, append `--disable-sandbox`:

```bash
swift test --disable-sandbox
```

## Architecture

- **Entry**: `Sources/TypingPet/main.swift` (lean `@MainActor` bootstrap) → initializes `AppDelegate` and starts runloop with `.accessory` policy.
- **Lifecycle & Menu**: `AppDelegate.swift` (`NSApplicationDelegate`, `NSStatusItem` menu bar tray, `SMAppService` launch at login, permissions onboarding coordination).
- **Window & Physics**: `PetController.swift` (manages floating panel, spring physics `PetMotionPhysics`, cursor evasion `PetPointerAvoidance`, shake bounce, opacity transitions) → `PetViews.swift` (`PetPanel` borderless non-activating floating panel, `PetContentView` hit-testing/tracking, `PetResizeHandleView` diagonal scale handle).
- **Geometry & Math**: `PetWindowGeometry.swift` (screen docking, bounds clamping, coordinate normalization, scale math).
- **Input Monitoring**: `GlobalKeyMonitor.swift` (low-level C-callback `CGEventTapCreate`, mach port lifecycle, key code & modifier mapping to `KeyStroke`).
- **Configuration**: `PetPreferences.swift` (centralized `AppPreferencesKey` and `AppPreferencesDefault`).
- **Assets & Gallery**: `PetImageLibrary.swift` (custom image sets, `NSCache` memory cache for thumbnails, disk persistence), `KeyReactions.swift` (per-keystroke reaction rules & image storage).
- **UI & Settings**: `SettingsWindow.swift` (tabbed AppKit preferences window, grid layout, custom rule recorder), `InputMonitoringGuide.swift` (floating guidance panel to assist user with System Settings authorization), `ImagePicker.swift` (file & folder selection panels).
- **Resources**: `Sources/TypingPet/Resources/` (`AppIcon.icns`, default cat frames `basic.png`, `left.png`, `right.png`).
- **Tests**: `Tests/TypingPetTests/` (Swift Testing suites: `PetPreferencesContractTests`, `DiskCleanupTests`, `ThumbnailCacheTests`, `PetWindowGeometryTests`, `KeyReactionTests`, `FolderImageSelectionTests`, `ImagePickerTests`).
- **Scripts**: `scripts/build_app.sh` (standalone bundle packager), `scripts/notarize_release.sh` (Developer ID notarization & stapling).
- **Docs**: `GLOSSARY.md` (canonical domain terms), `docs/architecture.md`, `docs/TypingPetMac-threat-model.md`, `docs/decisions/` (ADR records, e.g. `ADR-001` through `ADR-004`), `CHANGELOG.md` (Keep a Changelog format).

## Style & Engineering Standards

- **Swift 6 & Swift Testing**: Uses Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`) over legacy XCTest.
- **Zero Third-Party Dependencies**: No external SPM packages. Rely exclusively on Apple system frameworks (`AppKit`, `Foundation`, `CoreGraphics`, `QuartzCore`, `ServiceManagement`, `CryptoKit`).
- **ADRs & Global Docs**: Architectural decisions recorded in `docs/decisions/` as `ADR-NNN-xxx.md`. Whenever architectural boundaries, security controls, or domain models change, synchronously update `docs/architecture.md`, `docs/TypingPetMac-threat-model.md`, `GLOSSARY.md`, and relevant ADRs.
- **CHANGELOG**: Maintain `CHANGELOG.md` following strict Keep a Changelog principles (`Added`, `Changed`, `Fixed`, `Security`). Every unreleased modification must be recorded under `## [Unreleased]` before finishing the task.
- **Execution Loop**: Always follow: `Code edit -> Check & update Tests/TypingPetTests/* and scripts/check_*.sh -> Run tests (swift test & ./scripts/check_todo.sh) -> Check & update global docs -> Update CHANGELOG.md (## [Unreleased])`.

## Gotchas

- **Non-Activating Floating Panel**: `PetPanel` must override `canBecomeKey` and `canBecomeMain` to return `false` so clicking or dragging the pet never steals active keyboard focus from users' typing applications (IDE, browser, terminal).
- **Click-Through Mode**: When position is locked, `panel.ignoresMouseEvents = true` enables click-through. Pointer avoidance monitors global mouse location to dodge cursor even when click-through is enabled.
- **CGEventTap Headless / CI Limitation**: `CGEventTap` requires an active macOS window server session and granted permissions. Never write unit tests that simulate live hardware keystrokes through `CGEventTap`; test the event model parsing and controller layers instead.
- **Path Privacy in Releases**: Never use `#filePath` or `#file` outside `#if DEBUG` blocks to prevent developer machine paths from embedding into release binaries.
- **Disk Set Isolation**: All user-imported image sets are stored inside `~/Library/Application Support/TypingPet/Images/Sets/<UUID>/`. Deleting a set must delete this directory, never user source files.
- **Gatekeeper Quarantine**: Locally distributed unsigned or ad-hoc builds trigger macOS "App is damaged" or "Unidentified developer" prompt. Advise users to run `xattr -cr /Applications/TypingPet.app`.
- **Thumbnail Cache Lifetime**: Memory thumbnails are cached in `NSCache` inside `PetImageLibrary`. When replacing or deleting sets, explicitly invalidate or purge cached entries to prevent stale UI states.
