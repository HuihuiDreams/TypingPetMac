import AppKit

@MainActor
final class InputMonitoringGuideModel: ObservableObject {
    enum Phase: String {
        case preview, permission, verifying, connectionFailed, complete
    }

    @Published private(set) var phase: Phase = .preview
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var hasTriedPreview = false
    @Published var showsMissingAppHelp = false
    @Published var showsConnectionHelp = false

    private let idleImage: NSImage?
    private let reactionImages: [NSImage]
    private let isPermissionGranted: () -> Bool
    private let connectMonitoring: (_ restart: Bool) -> Bool
    private let requestPermission: () -> Void
    private let openSettings: @MainActor () -> Void
    private let onSetupStarted: () -> Void
    private var previewGeneration = 0
    private var reactionIndex = 0

    init(
        idleImage: NSImage? = nil,
        reactionImages: [NSImage] = [],
        resumeSetup: Bool = false,
        isPermissionGranted: @escaping () -> Bool = { CGPreflightListenEventAccess() },
        connectMonitoring: @escaping (_ restart: Bool) -> Bool,
        requestPermission: @escaping () -> Void = { _ = CGRequestListenEventAccess() },
        openSettings: @escaping @MainActor () -> Void = { InputMonitoringSettings.open() },
        onSetupStarted: @escaping () -> Void = {}
    ) {
        self.idleImage = idleImage
        self.reactionImages = reactionImages
        previewImage = idleImage
        self.isPermissionGranted = isPermissionGranted
        self.connectMonitoring = connectMonitoring
        self.requestPermission = requestPermission
        self.openSettings = openSettings
        self.onSetupStarted = onSetupStarted
        if resumeSetup { phase = .permission }
    }

    // Local preview events never request permission or count as global verification.
    func previewKeystroke() {
        guard phase == .preview else { return }
        hasTriedPreview = true
        if !reactionImages.isEmpty {
            previewImage = reactionImages[reactionIndex % reactionImages.count]
            reactionIndex = (reactionIndex + 1) % reactionImages.count
        }
        previewGeneration += 1
        let generation = previewGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self, self.previewGeneration == generation else { return }
            self.previewImage = self.idleImage
        }
    }

    func beginSetup() {
        guard phase == .preview else { return }
        phase = .permission
        onSetupStarted()
        previewGeneration += 1
        previewImage = idleImage
        if !isPermissionGranted() {
            requestPermission()
            openSettings()
        }
        refresh()
    }

    func showSettings() {
        openSettings()
    }

    func refresh(restart: Bool = false) {
        guard phase != .preview else { return }
        guard isPermissionGranted() else {
            phase = .permission
            return
        }
        guard connectMonitoring(restart) else {
            phase = .connectionFailed
            return
        }
        if phase != .complete || restart {
            phase = .verifying
        }
    }

    @discardableResult
    func receivedGlobalKeystroke() -> Bool {
        guard phase != .preview else { return false }
        refresh()
        guard phase == .verifying else { return false }
        phase = .complete
        return true
    }
}
