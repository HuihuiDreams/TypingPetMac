# Preset packs and keyboard mapping

Settings opens a grouped, rounded sidebar with My Packs, Image Presets, Keyboard Mapping, Appearance and Behavior, Todos and Focus, and General. The layout follows the system appearance or the explicit light/dark preference.

Each image pack owns freely named image presets, exact physical key mappings with any combination of Control, Option, Shift, and Command, and independent Unassigned and IDLE selections. Each selection can contain multiple presets with random or sequential playback. Random playback avoids repeating the last image when alternatives exist. Sequential playback follows the selected order, which can be changed in the expanded editor.

Unassigned and IDLE appear above the keyboard. Clicking either card or a key opens one inline accordion; selecting a different target replaces it. Editing uses onscreen keys and modifier toggles. There is no “press a key to select” capture mode. Imported images are copied into app storage, leaving originals intact. Import accepts an image folder or multiple files to create a pack. Save Pack saves and activates the current pack.

Preview Mode uses the current draft, including unsaved edits. It accepts onscreen clicks and physical keys only while the preview input has focus, without requesting global Input Monitoring. Tab leaves that input. Each key chooses a mapped preset or Unassigned; after 0.75 seconds without input, IDLE resumes. Next IDLE Image advances its independent selection. Preview and the desktop pet share `PresetPlaybackCursor`.

## Persistence and compatibility

Pack configurations are stored atomically in `Images/packs-v1.json` under the current profile's Application Support directory. Development and production remain separate. Existing image sets become packs on first load. Existing global key rules are preserved in every existing pack, referencing their existing copied images. Newly imported packs start without those global mappings. Unreadable or future-version pack documents are preserved and cannot be overwritten by the editor.

Original image-set metadata and legacy key rules remain available; no source files are deleted by migration. The desktop pet, menu image replacements, saved pack, and local preview use the same preset configurations. The desktop pet still requires Input Monitoring for keys pressed in other apps.

## Local verification

```sh
swift test
SWIFT_BUILD_CONFIGURATION=debug TYPINGPET_BUILD_CHANNEL=development CODE_SIGN_IDENTITY=- ./scripts/build_app.sh dist-dev
open "dist-dev/TypingPet Dev.app" --args --show-settings
```

Quit the development app before rebuilding. Native UI checks should cover one accordion at a time, multi-select and order controls, modifier layers, pack save/reopen, local preview reactions and IDLE, gallery names, and both system appearances. Tests cover migration, imported-image independence, persisted selections, exact modifiers, playback, invalid writes, and preservation of unreadable documents.
