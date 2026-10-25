import AppKit

/// Centralized storage keys for UserDefaults persistence across TypingPet.
enum AppPreferencesKey {
    // MARK: - Window & View Behavior
    /// Whether the pet window stays above standard floating windows (`Bool`).
    static let alwaysOnTop = "alwaysOnTop"

    /// Whether window dragging and clicking are locked/passed through (`Bool`).
    static let positionLocked = "positionLocked"

    /// Normalized pet rendering scale (`Double`).
    static let petScale = "petScale"

    /// Pet view opacity when pointer is not hovering (`Double`).
    static let restingOpacity = "restingOpacity"

    /// Pet view opacity when pointer is hovering (`Double`).
    static let hoverOpacity = "hoverOpacity"

    /// Whether locked pet dodges cursor proximity (`Bool`).
    static let avoidsPointerWhenLocked = "avoidsPointerWhenLocked"

    /// Pet keystroke animation shake intensity level (0-3, `Int`).
    static let shakeLevel = "shakeLevel"

    /// NSWindow frame autosave name (`String`).
    static let windowFrame = "TypingPetWindow"

    // MARK: - Image Library & Reaction Storage
    /// JSON encoded custom image set gallery catalog (`Data`).
    static let gallery = "imageGalleryData-v1"

    /// UUID of the currently active image set (`String`).
    static let activeSetID = "activeImageSetID-v1"

    /// Legacy custom idle image file name (`String`).
    static let legacyIdleFile = "customIdleImageFile"

    /// Legacy custom reaction image file names (`[String]`).
    static let legacyReactionFiles = "customReactionImageFiles"

    /// Custom image pack order (`[String]`).
    static let imagePackOrder = "imagePackOrder-v1"

    /// JSON encoded key reaction rules mapping key strokes to custom images (`Data`).
    static let keyReactionRules = "keyReactionRules-v1"
}

/// Standard fallback defaults and bounds for configuration options.
enum AppPreferencesDefault {
    // MARK: - Window Defaults
    static let alwaysOnTop: Bool = true
    static let positionLocked: Bool = false
    static let avoidsPointerWhenLocked: Bool = false

    // MARK: - Opacity Defaults
    static let restingOpacity: CGFloat = 1.0
    static let hoverOpacity: CGFloat = 0.3

    // MARK: - Scale Defaults & Presets
    static let petScale: CGFloat = 0.62
    static let minScale: CGFloat = 0.35
    static let maxScale: CGFloat = 1.25

    static let smallScale: CGFloat = 0.46
    static let mediumScale: CGFloat = 0.62
    static let largeScale: CGFloat = 0.82
    static let extraLargeScale: CGFloat = 1.08

    // MARK: - Shake Level Bounds & Default
    static let shakeLevel: Int = 2
    static let minShakeLevel: Int = 0
    static let maxShakeLevel: Int = 3

    // MARK: - Timing & Dimensions
    static let idleDelay: TimeInterval = 0.75
    static let fallbackBaseSize = NSSize(width: 453, height: 354)
}
