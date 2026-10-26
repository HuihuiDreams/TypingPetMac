# ADR-003: Unified Pet Pack Architecture & Preset-Based Expression Mapping

## Status
Accepted

## Date
2026-10-25

## Context
In versions prior to v0.18.0, the pet's visual state and keystroke mappings were divided across two disconnected subsystems:
1. **`PetImageSet` (`PetImageLibrary.swift`)**: Represented a folder under `Application Support/TypingPet/Images/Sets/<UUID>/` containing a single `idle` image and a flat list of `reaction` images randomly picked on any typing event.
2. **`KeyReactionStore` (`KeyReactions.swift`)**: Maintained an isolated JSON catalog and dedicated directory (`Application Support/TypingPet/KeyReactions/`) mapping individual hardware `KeyStroke` instances to single image files.

This disjoint data model created significant limitations:
- **No Sequential Multi-Frame Key Reactions**: Users could not configure alternating hand strikes (e.g., left-then-right hand on Space or Enter) or sequential typing cycles.
- **Static Idle State**: Resting state was constrained to a single stationary image rather than a configurable selection or cycle of resting poses.
- **Orphan File Hazards & Export Friction**: Deleting an image set could orphan key reaction rules referencing deleted files. Sharing or duplicating a character required synchronizing two separate storage stores and physical directories.

---

## Decision

We introduce a unified domain model centered on **Pet Packs (`PetPackConfiguration`)** supported by a preset-based asset abstraction (`Sources/TypingPet/PetPacks.swift`, `PackEditorModel.swift`, `NativeSetWorkspace.swift`):

```
Unified Pet Pack Domain Model
┌─────────────────────────────────────────────────────────────┐
│                   PetPackConfiguration                      │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Presets: [PetImagePreset (id, name, fileName, source)]│  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌─────────────────────────┐   ┌─────────────────────────┐  │
│  │ Idle: PresetSelection   │   │ Unassigned: Selection   │  │
│  │ (mode: random | cycle)  │   │ (fallback keystrokes)   │  │
│  └─────────────────────────┘   └─────────────────────────┘  │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Key Mappings: [PresetKeyMapping (KeyStroke, Selection)]│  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Specific Architectural Changes:

1. **Preset Abstraction (`PetImagePreset`)**:
   - All visual assets within a pack are normalized into strongly typed presets with a unique ID, human-readable name, and underlying filename.
2. **Flexible Playback Modes (`PresetSelection` & `PresetPlaybackMode`)**:
   - Keystroke mappings, unassigned typing reactions, and idle resting states each reference a `PresetSelection` specifying target preset IDs and an execution mode: `.random` (probabilistic) or `.cycle` (sequential).
3. **Channel-Isolated Playback Cursors (`PresetPlaybackCursor`)**:
   - Playback progress is tracked independently per mapped channel (e.g., Space advances its own left/right cycle without resetting the cursor for unassigned letter keystrokes or idle loops).
4. **Immutable Built-In Presets & Copy-on-Edit**:
   - Built-in character sets (e.g., Default Cat, Seven-Nine CP) are strictly read-only (`builtInPresetsReadOnly`). Users customize them by duplicating the pack, creating isolated physical file copies under application storage.
5. **Two-Tier Storage Adapter**:
   - To preserve backward compatibility and ensure clean disk isolation, `PetPackStore` serializes pack configurations to `packs.json` (format version 1) while continuing to delegate physical disk cleanup and image caching to `PetImageLibrary` (`Sets/<UUID>/`). Existing image sets and key reactions are automatically migrated without user data loss.

---

## Alternatives Considered

### Alternative 1: Ad-Hoc Expansion of `PetImageSet`
- **Approach**: Add fields to `PetImageSet` (e.g., `alternateReactionFiles: [String]`, `idleFiles: [String]`).
- **Pros**: Minimal new data structures.
- **Cons**: Combinatorial explosion of ad-hoc properties without unifying key rules; fails to resolve the disconnect between image sets and the `KeyReactionStore`.
- **Decision**: Rejected.

### Alternative 2: Complete Clean-Break Storage Rewrite
- **Approach**: Discard existing `Sets/<UUID>/` and `KeyReactions/` directories and require users to rebuild their character sets from scratch in a new archive format.
- **Pros**: Simpler schema with no legacy migration logic in `PetPackStore`.
- **Cons**: Destructive upgrade experience; existing users upgrading to v0.18.0 would lose custom-imported image sets and bindings.
- **Decision**: Rejected in favor of an adapter architecture.

---

## Consequences

### Positive Consequences
- **Expressive Character Choreography**: Enables complex character behaviors (alternating hands, sequential typing combos, multi-frame idle fidgets) within a unified model.
- **Encapsulated Entity**: A pet pack represents a complete, self-contained character definition suitable for future import/export.
- **Data Integrity & Immutability**: Built-in defaults are tamper-proof, and pack modifications operate on isolated copies.
- **Zero Data Loss Migration**: Legacy sets and key rules are migrated transparently on first launch.

### Negative Consequences / Trade-offs
- **Model Layering**: Requires coordinating between physical disk sets (`PetImageSet`) and logical pack configurations (`PetPackConfiguration`).
- **Cursor State Volatility**: `PresetPlaybackCursor` is held in memory during the app session; playback state resets to initial index on application restart.

---

## References & Companion Notes
- UI layout, split view, and keyboard popover interaction: [developer-notes/preset-editor.md](file:///Users/huihui/Documents/TypingPetMac/developer-notes/preset-editor.md)
- Future online cloud pack distribution proposal (under review): [developer-notes/pet-set-service.md](file:///Users/huihui/Documents/TypingPetMac/developer-notes/pet-set-service.md)
