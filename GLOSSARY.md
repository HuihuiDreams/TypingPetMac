# TypingPetMac Domain Glossary

A lightweight native macOS desktop typing pet overlay with global low-level keystroke reaction, floating companion tools, and zero-network offline privacy.

## Language

### Host & Windows

**Pet (桌宠主窗口)**:
The primary transparent floating overlay (`PetPanel`) hosting the animated pet character and handling physics and pointer evasion.
_Avoid_: Main window, key window, pet widget

**Companion Bubble (伴生气泡)**:
The secondary speech bubble panel (`TodoPanel`) anchored to the pet that displays focus timers and todo tasks.
_Avoid_: Tooltip, popover, notification, dialog

**Status Item (状态栏菜单)**:
The persistent tray item in the macOS menu bar (`NSStatusItem`) providing quick controls and access to settings.
_Avoid_: Dock icon, tray icon, menu bar extra

### Assets & Expressions

**Pet Pack (动作包)**:
A unified character configuration bundle containing image presets, unassigned keystroke fallbacks, idle state rules, and key-specific mappings.
_Avoid_: Skin, theme, mod

**Image Set (图集目录)**:
The physical file directory under `Application Support/TypingPet/Images/Sets/<UUID>/` containing imported image assets.
_Avoid_: Asset folder, album, gallery

**Preset (预设动作帧)**:
A named image asset within a pet pack that can be bound to key reactions, idle loops, or fallback states.
_Avoid_: Frame, sprite, picture, sticker

**Idle (待机/发呆)**:
The default resting visual state displayed when no keyboard input has occurred within the debounce window.
_Avoid_: Resting, static, waiting, default frame

**Reaction (按键反应/出击)**:
A momentary visual reaction frame displayed immediately upon a hardware keystroke.
_Avoid_: Punch, stroke animation, hit state

**Unassigned (通用反应)**:
The fallback preset selection triggered when a keystroke has no specific mapped reaction rule.
_Avoid_: Default reaction, catch-all, generic punch

### Hardware & Input

**KeyStroke (击键)**:
A typed model representing a single physical hardware keycode combined with active modifier flags.
_Avoid_: Key event, hotkey, character, shortcut

**KeyReaction (专属按键规则)**:
A direct mapping from a specific `KeyStroke` to an image preset or file.
_Avoid_: Macro, hotkey binding, shortcut rule

**ListenEvent Access (输入监控权限)**:
The macOS TCC permission (`ListenEvent`) required for session-level read-only `CGEventTap` keystroke monitoring.
_Avoid_: Accessibility permission (辅助功能), Keylogger permission

### Interaction & Energy

**Non-Activating Panel (非激活浮窗)**:
A window configuration (`NSPanel` with `.nonactivatingPanel` and `canBecomeKey = false`) that accepts clicks without stealing focus from the user's active application.
_Avoid_: Transparent window, background app, daemon window

**Click-Through (点击穿透)**:
A mode where window mouse events are ignored (`panel.ignoresMouseEvents = true`), passing all clicks directly to the underlying application.
_Avoid_: Transparent mode, ghost mode, ignore clicks

**Pointer Avoidance (指针避让)**:
The physics behavior where the pet automatically glides away when the cursor approaches within the avoidance threshold while position is locked.
_Avoid_: Cursor dodge, mouse fleeing, auto-move

**Energy Guard (能耗守卫)**:
The diff-threshold check (`abs(current - target) > 0.001`) and on-demand mouse tracking lifecycle preventing redundant `CATransaction` commits and CPU/GPU wakeups.
_Avoid_: Throttling, debounce, FPS limiter

### Distribution & Lifecycle

**Staged Update (暂存更新)**:
A downloaded and cryptographically verified update bundle staged in the user cache directory awaiting app restart.
_Avoid_: Temp update, downloaded installer, cached zip

**Helper Swap (辅助脚本替换)**:
The background `/bin/zsh` helper process that waits for the main application to terminate, atomically swaps the `.app` bundle, and restores the backup on failure.
_Avoid_: Sparkle installer, daemon replacer, updater thread
