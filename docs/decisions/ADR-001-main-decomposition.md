# ADR-001: Decomposition of Monolithic main.swift into Single-Responsibility Components & Centralization of Preferences

## Status
Accepted

## Date
2026-10-10

## Context
During initial rapid prototyping, `TypingPetMac` concentrated application bootstrap, window physics, custom AppKit view hierarchies, global low-level C event tap callbacks, and macOS menu bar management into a single source file: `Sources/TypingPet/main.swift` (1,397 lines).

While this monolithic structure allowed rapid feature iteration, it introduced several severe engineering liabilities:
1. **Coupled Domain Concerns**:
   - Presentation logic (`PetPanel`, `PetResizeHandleView`, `PetContentView`), animation dynamics (`PetController`), hardware input tapping (`GlobalKeyMonitor`), and OS menu bar interactions (`AppDelegate`) coexisted in a single scope.
2. **Impaired Automated Testing**:
   - All classes in `main.swift` were marked `private`, preventing `@testable import TypingPet` unit test suites from instantiating or validating window behaviors, resize controllers, or event tap translation.
3. **Configuration Sprawl & Literal Duplication**:
   - Persistence keys were scattered across multiple source files as bare String literals (`"alwaysOnTop"`, `"positionLocked"`, `"petScale"`, `"restingOpacity"`, `"hoverOpacity"`, `"avoidsPointerWhenLocked"`, `"shakeLevel"`, `"TypingPetWindow"`, `"imageGalleryData-v1"`, `"activeImageSetID-v1"`, `"customIdleImageFile"`, `"customReactionImageFiles"`, `"keyReactionRules-v1"`), creating typo hazards and inconsistent default value fallbacks.
4. **Energy Inefficiency (High-Frequency Event Overhead)**:
   - Global pointer motion monitors invoked `updatePetOpacity()` on every pixel movement, triggering redundant CoreAnimation transactions (`CATransaction.begin()` / `commit()`) even when computed opacity was identical to the layer's current state.

A clean architectural separation was required to restore maintainability, enable robust unit testing, eliminate redundant energy consumption, and isolate startup bootstrap code.

---

## Decision

We decompose `Sources/TypingPet/main.swift` into five specialized, single-responsibility files, accompanied by a centralized preferences module:

```
Sources/TypingPet/
├── PetPreferences.swift       # Centralized AppPreferencesKey & AppPreferencesDefault
├── PetViews.swift             # PetPanel, PetResizeHandleView, PetContentView
├── GlobalKeyMonitor.swift     # Low-level CGEventTap C-bridged keyboard listener
├── PetController.swift        # Window controller, physics, opacity guard, docking
├── AppDelegate.swift          # NSApplicationDelegate, status item, menus, permissions
└── main.swift                 # Concise top-level @MainActor bootstrap (~20 lines)
```

### Specific Structural Changes:
1. **Extraction of Views (`PetViews.swift`)**:
   - `PetPanel`: Floating borderless panel overriding `canBecomeKey` and `canBecomeMain`.
   - `PetResizeHandleView`: Corner circular handle with custom cursor tracking and resize gestures.
   - `PetContentView`: Custom host view managing close/resize hit-testing, mouse tracking areas, and spring scale animations.
2. **Extraction of Global Hardware Monitor (`GlobalKeyMonitor.swift`)**:
   - Self-contained `CGEventTap` session listener (`.listenOnly`), bridging C function pointer callbacks into Swift closures emitting strongly typed `KeyStroke` models.
3. **Extraction of Window & Motion Engine (`PetController.swift`)**:
   - Manages window frame restoration, scale clamping, inertia simulation (`PetMotionPhysics`), pointer evasion (`PetPointerAvoidance`), and keystroke-to-reaction rendering.
   - **Energy Optimization Guard**: Incorporates a delta guard in `updatePetOpacity()`:
     ```swift
     guard abs(CGFloat(imageLayer.opacity) - targetOpacity) > 0.001 else { return }
     ```
     eliminating redundant CoreAnimation transaction commits.
4. **Extraction of Lifecycle & Menu Management (`AppDelegate.swift`)**:
   - Implements `NSApplicationDelegate` and `NSMenuDelegate`, coordinating `NSStatusItem`, system authorization onboarding (`CGRequestListenEventAccess`), settings coordinator, and Login Item registration (`SMAppService`).
5. **Centralization of Configuration (`PetPreferences.swift`)**:
   - Declares `AppPreferencesKey` (all 13 UserDefaults storage keys) and `AppPreferencesDefault` (fallback constants, scale bounds, presets, base size, and autosave names).
6. **Visibility Adjustments**:
   - Elevate top-level class declarations (`PetPanel`, `PetResizeHandleView`, `PetContentView`, `PetController`, `GlobalKeyMonitor`, `AppDelegate`) from `private` to `internal` (module default).
   - Internal state, timers, private calculation helpers, and backing layers remain strictly `private` within their owning classes.
7. **Streamlined Bootstrap (`main.swift`)**:
   - `main.swift` is reduced to top-level execution initializing `NSApplication.shared`, setting `AppDelegate`, setting `.accessory` activation policy, and calling `run()`.

---

## Alternatives Considered

### Alternative 1: Monolithic Partitioning via `// MARK:` Directives
- **Approach**: Retain all 1,397 lines in `main.swift` and organize sections using `// MARK: - Views`, `// MARK: - Controller`, etc.
- **Pros**: Zero file creation, zero risk of cross-file reference mistakes.
- **Cons**: Does not resolve the testability problem (types remain `private` to the file), git conflicts remain clustered in one file, cognitive load remains high.
- **Decision**: Rejected.

### Alternative 2: Multi-Target Swift Package Manager Breakdown
- **Approach**: Split `TypingPet` into multiple SPM targets (`TypingPetCore`, `TypingPetUI`, `TypingPetInput`, `TypingPetApp`).
- **Pros**: Enforces compiler-level dependency boundaries.
- **Cons**: Excessive engineering overhead for a lightweight macOS menu bar utility; complicates resource bundling, dynamic/static linking, and module interface maintenance.
- **Decision**: Rejected as over-engineering violating the Karpathy Simplicity First principle.

### Alternative 3: Rewrite UI Layer in SwiftUI / `MenuBarExtra`
- **Approach**: Discard AppKit windows and rewrite everything in SwiftUI with `MenuBarExtra`.
- **Pros**: Declarative UI syntax.
- **Cons**: High regression risk. SwiftUI lacks native support for non-activating transparent floating panels, click-through window ignore flags, low-level cursor tracking rects, and smooth spring physics integration without window-level AppKit bridges.
- **Decision**: Rejected.

---

## Consequences

### Positive Consequences
- **High Cohesion & Readability**: Every source file has a single, well-defined domain responsibility under 600 lines.
- **Direct Testability**: Controllers, views, and helpers can be directly tested via `@testable import TypingPet` in automated test suites without artificial shims.
- **Type-Safe Preferences**: Single source of truth for all UserDefaults keys and default values prevents typographical errors, schema drift, and magic string proliferation.
- **Energy Efficiency**: Opacity delta guard eliminates idle CPU/GPU wakeups during rapid cursor movement across the screen.
- **Clear Git History**: Future features and bugfixes touch only relevant isolated files, minimizing merge conflict surface.

### Negative Consequences / Trade-offs
- **Internal Scope Visibility**: Classes are visible to all files within the `TypingPet` module rather than strictly file-private. Mitigated by maintaining rigorous private access modifiers on members and state variables.
- **File Management**: Package now contains multiple focused Swift files rather than a single monolithic entry point.

---

## Compliance & Acceptance Criteria

To ensure continuous adherence to this architectural decision, the following verification gates must pass:

1. **Bootstrap File Budget**:
   - `Sources/TypingPet/main.swift` must not exceed 30 lines of code.
2. **File Size Budget**:
   - No individual decomposed source file (`PetViews.swift`, `PetController.swift`, etc.) may exceed 650 lines.
3. **No Literal Keys**:
   - Zero raw string literals for preferences in `PetController.swift`, `PetImageLibrary.swift`, `KeyReactions.swift`, and `AppDelegate.swift`. All must reference `AppPreferencesKey`.
4. **Toolchain Compilation**:
   - Clean compilation without warnings or errors via:
     ```bash
     SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build
     ```
5. **App Packaging**:
   - Execution of `./scripts/build_app.sh` must successfully generate `dist/TypingPet.app` with `0.12.0` in `Info.plist`.
6. **Regression Verification**:
   - Existing unit test suites must pass without regression in geometry, opacity behavior, or keystroke handling.
