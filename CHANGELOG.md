# Changelog

## 0.17.0 - 2026-10-24

- Add Japanese, Simplified Chinese, and Traditional Chinese throughout the app, alongside Korean and English.
- Detect Japanese and Chinese system languages, honoring explicit Chinese scripts and regional defaults, and allow a saved language override in Settings.
- Localize the website, installation guides, FAQs, release notes, accessibility labels, and search and social metadata in all five languages.
- Keep the current website page and anchor when switching languages, and remember the choice for future visits.

## 0.16.0 - 2026-10-24

- Keep Settings at a compact 490-point default width, with room to grow for larger accessibility text and manual resizing.
- Add System, Korean, and English language choices in Settings. Follow the first system language by default, using English for languages other than Korean.
- Maintain Korean and English interface strings in separate localization files, including Settings, menus, Todo bubbles, Input Monitoring guidance, and update messages.
- Apply the saved System, Light, or Dark appearance to both Settings and Todo bubbles, including the collapsed entry button.

## 0.15.0 - 2026-10-24

- Let users try pet key reactions inside the welcome window before requesting Input Monitoring permission.
- Guide users through enabling the permission switch, with optional drag-and-drop help when the app is missing from the list.
- Confirm a real global key event before completing setup, and resume verification after a required app relaunch.
- Add a gear button immediately to the left of the pet's resize handle on hover to open Settings.
- Publish the signed and notarized Apple Silicon app through the ynifamily3/tap Homebrew cask alongside GitHub and automatic updates.
- Add guarded release automation for testing, signing, notarization, update-server deployment, and Homebrew publication.

## 0.14.3 - 2026-10-24

- Add System, Light, and Dark appearance choices for the Settings window, with an immediate preview and a saved preference.
- Keep the pet and Todo bubble appearance independent of the Settings window choice.

## 0.14.2 - 2026-10-24

- Publish the production update feed and verify release archives with the app's Ed25519 key, Developer ID signature, and Apple notarization.
- Replace the lost update signing key. Builds through 0.14.1 cannot update automatically to 0.14.2; install this release manually once. Later releases can use automatic update checks.
- Add a single-command, guarded update deployment that publishes the archive before atomically replacing the feed.

## 0.14.1 - 2026-10-24

- Release the existing 0.14.0 features with an Apple-issued Developer ID Application signature and Apple notarization.
- Keep the production update public key from 0.14.0 so existing installations continue to trust future updates signed with the original private key.
- Existing ad-hoc installations may need Input Monitoring permission granted again when switching to this Developer ID-signed build.

## 0.14.0 - 2026-10-23

- Add a compact view for a Todo bubble that stays open: up to three open Todos, one line each with checkboxes, and `+N개 더` to open the full view.
- Switch views from the bubble header, the hover button, the context menu, or Settings > `할 일` > `목록 보기`. The choice persists across relaunches.
- Right-click a compact row to pause, resume, or stop its timer, or start it with its saved setting, count-up, or 20 minutes.
- Keep the compact view when a timer starts from it. Endings and absences show their own bubble until answered, then the compact view returns.

## 0.13.0 - 2026-10-23

- Check for updates once a day and from the menu bar or the General settings tab.
- Install an update after you accept it, then restart. A later quit installs an accepted update.
- Verify each update with SHA-256, an Ed25519 signature, the bundle identity, and the Developer ID Team ID.
- Restore the previous app when the swap fails, and report the result on the next launch.
- Ad-hoc builds update with the Ed25519 signature alone. Grant Input Monitoring again after each update until builds are Developer ID signed.

## 0.12.0 - 2026-10-21

- Add a Todo speech bubble beside the pet with a per-Todo countdown or count-up focus timer and measured session time.
- Edit Todo titles in place, zoom the bubble from 80% to 200%, and show it always or only on hover.
- Pause a running timer after a configurable idle period, on screen lock, or on sleep, then ask how to treat the time away.
- Bounce the bubble like a Dock icon when a countdown ends or a missed notice is waiting.
- Build local development copies as a separate TypingPet Dev app with its own settings, images, and Todo records.

## 0.11.2 - 2026-09-27

- Replace the permission guide's Finder shortcut with a prominent button that reopens Input Monitoring settings.
- Share the same Input Monitoring deep link between the menu, settings window, and floating guide.

## 0.11.1 - 2026-09-27

- Keep the Input Monitoring guide above normal application windows.
- Follow the open System Settings window without requesting Accessibility permission.
- Prefer placement beside System Settings and stay inside the visible screen when space is limited.

## 0.11.0 - 2026-09-27

- Add a floating guide for granting Input Monitoring permission.
- Make the real TypingPet.app icon draggable into the system permission list.
- Detect permission changes automatically and dismiss the guide after access is granted.
- Warn when the app is outside Applications and provide Finder and manual-picker fallbacks.

## 0.10.0 - 2026-09-27

- Simplify the menu bar menu to the essential pet, position, permission, login, and quit actions.
- Show key-input monitoring availability in green or red when the menu opens.

## 0.9.1 - 2026-09-25

- Show the native diagonal frame-resize cursor over the pet's resize handle.
- Add a drag-to-resize tooltip and accessibility help to make the control easier to discover.

## 0.9.0 - 2026-09-25

- Standardize settings spacing on a 4-point grid across all tabs.
- Replace the nested grouped form with flat sections and aligned rows.
- Unify gallery cards, action groups, empty states, and window margins.

## 0.8.1 - 2026-09-25

- Let pointer avoidance favor playful diagonal escape paths when space permits.
- Rotate around the direct escape vector and retain edge-aware fallback behavior.

## 0.8.0 - 2026-09-25

- Add an optional pointer-avoidance mode for click-through position lock.
- Move away with damped spring motion while remaining inside the current display.
- Choose an alternate escape direction when the nearest screen edge blocks movement.

## 0.7.0 - 2026-09-25

- Replace distance-based fading with configurable resting and hover opacity settings.
- Default to 100% resting opacity and 30% hover opacity.
- Apply hover entry and exit opacity immediately without a transition.

## 0.6.0 - 2026-09-25

- Fade the pet image smoothly based on pointer proximity, down to 30% opacity on hover.
- Keep hide and resize controls fully visible while the pet image fades.

## 0.5.1 - 2026-09-25

- Center the image-layer anchor so hover and pressed spring effects scale around the pet's midpoint.

## 0.5.0 - 2026-09-25

- Add velocity-based drag inertia with smooth friction and screen-edge containment.
- Add springy hover enlargement and pressed-down drag feedback.

## 0.4.0 - 2026-09-25

- Show hover controls for hiding and resizing the pet.
- Allow proportional corner resizing and keep it synchronized with the size setting.
- Make the close control hide only the pet while the menu bar app and key monitor continue running.
- Add a menu item for showing the hidden pet again.

## 0.3.0 - 2026-09-25

- Add a dedicated settings window with general, gallery, and key-reaction tabs.
- Add reusable image-set galleries with migration from the earlier single-set format.
- Add exact key and modifier-combination reactions.
- Add four bounce-strength levels.
- Add an original CC0 keyboard-cat placeholder image set and app icon.
- Add Developer ID-aware build and notarization scripts.
