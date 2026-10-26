# ADR-002: In-House Secure Auto-Update Subsystem vs. Third-Party Frameworks

## Status
Accepted

## Date
2026-10-23

## Context
TypingPetMac is distributed directly to end users as a standalone macOS application outside the Mac App Store. To deliver bug fixes, performance improvements, and security patches without requiring users to manually redownload and replace `.app` bundles from GitHub or the product website, an automated update mechanism was needed.

However, TypingPetMac operates under two foundational architectural and security constraints:
1. **Zero External Dependencies**: The project adheres to a strict policy of zero third-party packages, depending exclusively on Apple native system frameworks (`AppKit`, `Foundation`, `CoreGraphics`, `CryptoKit`).
2. **Absolute Offline Privacy Guarantee**: The core desktop pet runtime is 100% offline, executing zero network requests and transmitting zero telemetry, analytics, or user keystrokes.

Integrating mainstream third-party update frameworks (most notably Sparkle 2) would introduce significant external codebase volume, third-party package dependencies, and complex networking and telemetry surfaces that contradict these core tenets.

---

## Decision

We implement a custom, self-contained, and cryptographically verified in-house auto-update subsystem (`Sources/TypingPet/UpdateController.swift`, `UpdateManifest.swift`, `UpdateInstaller.swift`) composed of three key layers:

```
Update Subsystem Architecture
┌─────────────────────────┐
│   UpdateController      │  Scheduled or manual check trigger; UI presentation
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│   UpdateInstaller       │  Ephemeral URLSession fetch -> Manifest decode
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│   UpdateVerifier        │  Ed25519 signature + SHA-256 + Apple Notarization (spctl)
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│   Helper Script (zsh)   │  Outlives parent PID; atomic bundle swap & rollback on failure
└─────────────────────────┘
```

### Specific Architectural Mechanisms:

1. **Strictly Isolated Network Boundary**:
   - Networking is isolated solely to update check/download operations via an ephemeral `URLSession` (`UpdateInstaller.makeSession()`) that disables local caches, cookies, and credential storage.
   - Core pet animation, motion, and keystroke processing paths remain completely devoid of any network capabilities.
2. **Cryptographic & Gatekeeper Verification**:
   - Before executing or unpacking any archive, `UpdateVerifier` enforces:
     - **Ed25519 Signature Verification**: Validates the downloaded update archive using `CryptoKit.Curve25519.Signing.PublicKey` against the manifest signature.
     - **SHA-256 Hash Digest**: Asserts binary archive integrity.
     - **Apple Notarization & Developer ID**: For production builds, executes `/usr/sbin/spctl --assess --type execute` against the uncompressed application bundle and confirms Developer ID Team Identifier matches the running app.
3. **Decoupled Out-of-Process Atomic Helper Swap**:
   - Staged updates are extracted into an isolated cache directory (`~/Library/Caches/<bundle-id>/Updates/<build>-<uuid>/`).
   - Replacement occurs after the main app process terminates by launching an independent background `/bin/zsh` helper script (`install.sh`).
   - The helper script backs up the current `.app` bundle, performs an atomic filesystem swap with the staged bundle, attempts an optional relaunch, and automatically restores the previous bundle if the swap or verification fails.

---

## Alternatives Considered

### Alternative 1: Sparkle 2 Framework
- **Approach**: Import Sparkle via Swift Package Manager (`SPM`).
- **Pros**: Industry-standard, mature UI, automatic delta updates.
- **Cons**: Adds thousands of lines of external code, introduces external package dependencies violating the zero-dependency rule, increases bundle footprint, and complicates isolated security audits.
- **Decision**: Rejected.

### Alternative 2: Manual Browser Downloads Only
- **Approach**: Open a browser link to GitHub Releases when a newer version is detected.
- **Pros**: Zero local update code or filesystem replacement scripts.
- **Cons**: High user friction; users fail to update, leading to outdated installations and repeated reports of resolved issues.
- **Decision**: Rejected.

### Alternative 3: Homebrew Cask Only
- **Approach**: Delegate all updates to Homebrew (`brew upgrade typingpet`).
- **Pros**: Managed entirely by external package manager.
- **Cons**: Excludes the majority of non-developer users who download standalone zip packages directly from the website.
- **Decision**: Maintained as an auxiliary distribution channel (`ynifamily3/tap`), but rejected as the sole update mechanism.

---

## Consequences

### Positive Consequences
- **Zero Third-Party SPM Dependencies**: The entire update subsystem is implemented in fewer than 600 lines of standard Swift and native macOS command-line utilities.
- **Cryptographic Trust Guarantee**: Tampered archives, unnotarized binaries, or mismatched signatures are deterministically rejected prior to staging.
- **Deterministic Rollback**: The detached helper script ensures the user is never left with a corrupted or missing `.app` bundle if the installation fails midway.
- **Preserved Core Privacy**: The desktop pet and keystroke monitor remain strictly offline with zero telemetry.

### Negative Consequences / Trade-offs
- **Maintenance Responsibility**: Manifest schema versioning, key rotation, and helper script compatibility with macOS filesystem changes must be maintained in-house.
- **Manual Signature Configuration**: Developers must maintain an Ed25519 signing keypair alongside their Apple Developer ID certificates.

---

## References & Companion Notes
- Implementation & release runbook: [developer-notes/updates.md](file:///Users/huihui/Documents/TypingPetMac/developer-notes/updates.md)
- Release automation and signing: [developer-notes/releasing.md](file:///Users/huihui/Documents/TypingPetMac/developer-notes/releasing.md)
- Developer ID certificate and notarization setup: [developer-notes/developer-id.md](file:///Users/huihui/Documents/TypingPetMac/developer-notes/developer-id.md)
