# ADR-004: Dual-Window Companion Architecture & Non-Activating Focus Safety Invariants

## Status
Accepted

## Date
2026-10-26

## Context
TypingPetMac expanded beyond a pure typing-reaction toy to incorporate desktop companion utilities: a persistent Todo checklist and a Pomodoro/focus countdown timer.

However, introducing interactive text editing into an application with TypingPetMac's unique architectural characteristics created severe windowing, focus, and security conflicts:
1. **Focus Stealing Invariant vs. Inline Text Input**:
   - The primary pet window (`PetPanel`) strictly enforces `canBecomeKey = false` and `canBecomeMain = false` to guarantee that user clicks, drags, or animations **never steal focus** from the user's active IDE, terminal, or browser.
   - Conversely, creating and renaming Todo tasks requires an active `NSTextField` that can become first responder and accept keyboard focus (`canBecomeKey = true`).
2. **Keystroke Hijacking & TCC Trust Boundary**:
   - TypingPetMac holds the high-value macOS "Input Monitoring" (`ListenEvent`) TCC permission.
   - If an interactive text field in a floating overlay retains key window status after the user switches focus to another app, keystrokes intended for external applications could accidentally type into the pet's Todo list, creating an unacceptable user data hazard.
3. **Menu Bar App Shortcut Absence**:
   - In `.accessory` mode (`LSUIElement = true`), the application does not own the macOS system menu bar. Standard AppKit Edit commands (Cut `⌘X`, Copy `⌘C`, Paste `⌘V`, Select All `⌘A`, Undo `⌘Z`) do not dispatch through a global Edit menu.
4. **Window Geometry & Physics Interference**:
   - If Todo views were embedded directly inside `PetPanel`, the window frame would expand dynamically, corrupting inertia glide physics, edge bounce calculations, and pointer avoidance raycasting.

---

## Decision

We adopt a **Dual-Window Companion Architecture** backed by strict **Non-Activating Focus Safety Invariants** (`Sources/TypingPet/TodoBubbleWindowController.swift`, `TodoStore.swift`, `TextEditingShortcuts.swift`):

```
Dual-Window Companion Architecture
┌──────────────────────────┐         ┌──────────────────────────┐
│        PetPanel          │         │        TodoPanel         │
│  canBecomeKey: false     │         │  canBecomeKey: true      │
│  canBecomeMain: false    │◄────────┤  canBecomeMain: false    │
│  (Physics, Evasion, Art) │ Anchor  │  (Timers, Todos, Input)  │
└──────────────────────────┘         └────────────┬─────────────┘
                                                  │
                                                  ▼ Focus Protection
                                     ┌──────────────────────────┐
                                     │   Aggressive Surrender   │
                                     │  • Outside click monitor │
                                     │  • App blur / key loss   │
                                     │  • Screen lock / sleep   │
                                     └──────────────────────────┘
```

### Specific Architectural Mechanisms:

1. **Independent Panel Separation & Dynamic Tail Anchoring**:
   - `PetPanel`: Remains strictly non-key (`canBecomeKey = false`), dedicated exclusively to rendering sprite frames, inertia physics, and cursor dodging.
   - `TodoPanel`: A secondary floating panel (`canBecomeKey = true`, `canBecomeMain = false`) managed by `TodoBubbleWindowController`. It dynamically computes its placement and tail orientation relative to `PetPanel`'s screen frame while keeping its physics bounding box completely decoupled.
2. **Aggressive Focus Surrender Invariant**:
   - The Todo bubble only acquires key window status when the user deliberately clicks an input field or opens the list.
   - To prevent capturing typing intended for external apps, `TodoBubbleWindowController` forcibly resigns `firstResponder` and releases key status upon:
     - Any mouse click outside the bubble frame (monitored globally).
     - Window losing key status.
     - System lock screen or sleep notifications (`NSWorkspace.screensDidSleepNotification`, `willSleepNotification`).
3. **Direct Shortcut Interception (`TextEditingShortcuts`)**:
   - `TodoPanel` overrides `performKeyEquivalent(with:)`. In the absence of a system Edit menu, standard shortcuts (`⌘C`, `⌘V`, `⌘X`, `⌘A`, `⌘Z`) are parsed via `TextEditingShortcuts.action` and forwarded directly through `NSApp.sendAction(_:to:from:)` to the active text field.
4. **Hardened POSIX Atomic Persistence (`TodoFileStorage`)**:
   - To defend against symlink injection, FIFO blocking, and unauthorized file access under `Application Support/TypingPet/`, `TodoFileStorage` utilizes low-level Darwin descriptors:
     - `Darwin.open` with `O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC`.
     - File size capped at 10 MiB; regular file validation via `fstat`.
     - Permissions clamped strictly to user-only `0600` via `Darwin.fchmod`.
     - Atomic replacement using `mkstemp` temporary files followed by atomic `Darwin.rename`.

---

## Alternatives Considered

### Alternative 1: Single Window (Embed Todo Inside `PetPanel`)
- **Approach**: Combine pet sprite and Todo speech bubble into a single expanding `NSPanel`.
- **Pros**: Only one window to manage.
- **Cons**: Destroys pointer avoidance geometry, complicates click-through hit-testing, forces the entire pet to become key when editing text, and increases redraw overhead.
- **Decision**: Rejected.

### Alternative 2: Separate Traditional Window or Settings Tab
- **Approach**: Move Todo checklist and focus timers into a tab in the Settings window.
- **Pros**: Standard macOS window lifecycle with default menu bar shortcut support.
- **Cons**: Destroys the core companion user experience of having the pet "speak" your tasks and timers in a dynamic speech bubble on the desktop.
- **Decision**: Rejected.

---

## Consequences

### Positive Consequences
- **Uncompromised Desktop Flow**: The pet retains its non-intrusive, zero-focus-stealing property during typing, while providing an intuitive floating companion bubble on demand.
- **Guaranteed Keystroke Isolation**: Aggressive focus surrender ensures user keystrokes never leak into background text fields when switching tasks.
- **Robust Storage Security**: Low-level POSIX file handling prevents symlink traversals and race conditions.
- **Independent Layout & Zoom**: Bubble zoom (80% to 200%) and visibility modes (always vs. hover) operate independently of pet scale.

### Negative Consequences / Trade-offs
- **Multi-Window Coordinate Synchronization**: Controller must listen to pet movement, screen reconfiguration, and window bounds changes to maintain seamless tail anchoring.
- **Manual Shortcut Maintenance**: Requires maintaining `TextEditingShortcuts` to emulate standard menu-driven editing commands.

---

## References & Companion Notes
- User interface guide, character length limits, and timer rules: [developer-notes/todos.md](file:///Users/huihui/Documents/TypingPetMac/developer-notes/todos.md)
- Multi-Mac cloud sync proposal (under review): [developer-notes/todo-sync.md](file:///Users/huihui/Documents/TypingPetMac/developer-notes/todo-sync.md)
